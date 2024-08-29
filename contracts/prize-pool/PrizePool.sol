// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "../external/compound/ICompLike.sol";
import "../interfaces/IPrizePool.sol";
import "../interfaces/IShare.sol";

/**
  * @title  PrizePool
  * @author Wyatt
  * @notice Escrows assets and deposits them into a yield source.  Exposes interest to Prize Strategy.
            Users deposit and withdraw from this contract to participate in Prize Pool.
            Accounting is managed using Controlled Tokens, whose mint and burn functions can only be called by this contract.
            Must be inherited to provide specific yield-bearing asset control, such as Compound cTokens
*/
abstract contract PrizePool is IPrizePool, Ownable, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    /// @notice Semver Version
    string public constant VERSION = "1.0.0";

    /// @notice Prize Pool share. Can only be set once by calling `setShare()`.
    IShare internal share;

    /// @notice The Prize Strategy that this Prize Pool is bound to.
    address internal prizeStrategy;

    /// @notice The total amount of share a user can hold.
    uint256 internal balanceCap;

    /// @notice The total amount of funds that the prize pool can hold.
    uint256 internal liquidityCap;

    /// @notice the The awardable balance
    uint256 internal _currentAwardBalance;

    /* ============ Modifiers ============ */

    /// @dev Function modifier to ensure caller is the prize-strategy
    modifier onlyPrizeStrategy() {
        require(msg.sender == prizeStrategy, "PrizePool/only-prizeStrategy");
        _;
    }

    /// @dev Function modifier to ensure the deposit amount does not exceed the liquidity cap (if set)
    modifier canAddLiquidity(uint256 _amount) {
        require(_canAddLiquidity(_amount), "PrizePool/exceeds-liquidity-cap");
        _;
    }

    /* ============ Constructor ============ */

    /// @notice Deploy the Prize Pool
    /// @param _owner Address of the Prize Pool owner
    constructor(address _owner) Ownable(_owner) ReentrancyGuard() {
        _setLiquidityCap(type(uint256).max);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IPrizePool
    function balance() external override returns (uint256) {
        return _balance();
    }

    /// @inheritdoc IPrizePool
    function awardBalance() external view override returns (uint256) {
        return _currentAwardBalance;
    }

    /// @inheritdoc IPrizePool
    function isControlled(IShare _controlledToken) external view override returns (bool) {
        return _isControlled(_controlledToken);
    }

    /// @inheritdoc IPrizePool
    function getAccountedBalance() external view override returns (uint256) {
        return _shareTotalSupply();
    }

    /// @inheritdoc IPrizePool
    function getBalanceCap() external view override returns (uint256) {
        return balanceCap;
    }

    /// @inheritdoc IPrizePool
    function getLiquidityCap() external view override returns (uint256) {
        return liquidityCap;
    }

    /// @inheritdoc IPrizePool
    function getShare() external view override returns (IShare) {
        return share;
    }

    /// @inheritdoc IPrizePool
    function getPrizeStrategy() external view override returns (address) {
        return prizeStrategy;
    }

    /// @inheritdoc IPrizePool
    function getToken() external view override returns (address) {
        return address(_token());
    }

    /// @inheritdoc IPrizePool
    function captureAwardBalance() external override nonReentrant returns (uint256) {
        uint256 shareTotalSupply = _shareTotalSupply();
        uint256 currentAwardBalance = _currentAwardBalance;

        // it's possible for the balance to be slightly less due to rounding errors in the underlying yield source
        uint256 currentBalance = _balance();
        uint256 totalInterest = (currentBalance > shareTotalSupply)
            ? currentBalance - shareTotalSupply
            : 0;

        uint256 unaccountedPrizeBalance = (totalInterest > currentAwardBalance)
            ? totalInterest - currentAwardBalance
            : 0;

        if (unaccountedPrizeBalance > 0) {
            currentAwardBalance = totalInterest;
            _currentAwardBalance = currentAwardBalance;

            emit AwardCaptured(unaccountedPrizeBalance);
        }

        return currentAwardBalance;
    }

    /// @inheritdoc IPrizePool
    function depositTo(address _to, uint256 _amount)
        external
        override
        nonReentrant
        canAddLiquidity(_amount)
    {
        _depositTo(msg.sender, _to, _amount);
    }

    /// @notice Transfers tokens in from one user and mints share to another
    /// @notice _operator The user to transfer tokens from
    /// @notice _to The user to mint share to
    /// @notice _amount The amount to transfer and mint
    function _depositTo(address _operator, address _to, uint256 _amount) internal
    {
        require(_canDeposit(_to, _amount), "PrizePool/exceeds-balance-cap");

        IShare _share = share;

        _token().safeTransferFrom(_operator, address(this), _amount);

        _mint(_to, _amount, _share);
        _supply(_amount);

        _share.transferTwab(address(0), _to, _amount);

        emit Deposited(_operator, _to, _share, _amount);
    }

    /// @inheritdoc IPrizePool
    function withdrawFrom(address _from, uint256 _amount)
        external
        override
        nonReentrant
        returns (uint256)
    {
        IShare _share = share;

        // burn the share
        _share.controllerBurnFrom(msg.sender, _from, _amount);

        // redeem the share
        uint256 _redeemed = _redeem(_amount);

        _token().safeTransfer(_from, _redeemed);

        _share.transferTwab(_from, address(0), _amount);

        emit Withdrawal(msg.sender, _from, _share, _amount, _redeemed);

        return _redeemed;
    }

    /// @inheritdoc IPrizePool
    function award(address _to, uint256 _amount) external override onlyPrizeStrategy {
        if (_amount == 0) {
            return;
        }

        uint256 currentAwardBalance = _currentAwardBalance;

        require(_amount <= currentAwardBalance, "PrizePool/award-exceeds-avail");

        unchecked {
            _currentAwardBalance = currentAwardBalance - _amount;
        }

        IShare _share = share;

        _mint(_to, _amount, _share);

        _share.transferTwab(address(0), _to, _amount);


        emit Awarded(_to, _share, _amount);
    }

    /// @inheritdoc IPrizePool
    function setBalanceCap(uint256 _balanceCap) external override onlyOwner returns (bool) {
        _setBalanceCap(_balanceCap);
        return true;
    }

    /// @inheritdoc IPrizePool
    function setLiquidityCap(uint256 _liquidityCap) external override onlyOwner {
        _setLiquidityCap(_liquidityCap);
    }

    /// @inheritdoc IPrizePool
    function setShare(IShare _share) external override onlyOwner returns (bool) {
        require(address(_share) != address(0), "PrizePool/share-not-zero-address");
        require(address(share) == address(0), "PrizePool/share-already-set");

        share = _share;

        emit ShareSet(_share);

        _setBalanceCap(type(uint256).max);

        return true;
    }

    /// @inheritdoc IPrizePool
    function setPrizeStrategy(address _prizeStrategy) external override onlyOwner {
        _setPrizeStrategy(_prizeStrategy);
    }

    // /// @inheritdoc IPrizePool
    // function compLikeDelegate(ICompLike _compLike, address _to) external override onlyOwner {
    //     if (_compLike.balanceOf(address(this)) > 0) {
    //         _compLike.delegate(_to);
    //     }
    // }

    /* ============ Internal Functions ============ */

    /// @notice Called to mint controlled tokens.  Ensures that token listener callbacks are fired.
    /// @param _to The user who is receiving the tokens
    /// @param _amount The amount of tokens they are receiving
    /// @param _controlledToken The token that is going to be minted
    function _mint(
        address _to,
        uint256 _amount,
        IShare _controlledToken
    ) internal {
        _controlledToken.controllerMint(_to, _amount);
    }

    /// @dev Checks if `user` can deposit in the Prize Pool based on the current balance cap.
    /// @param _user Address of the user depositing.
    /// @param _amount The amount of tokens to be deposited into the Prize Pool.
    /// @return True if the Prize Pool can receive the specified `amount` of tokens.
    function _canDeposit(address _user, uint256 _amount) internal view returns (bool) {
        uint256 _balanceCap = balanceCap;

        if (_balanceCap == type(uint256).max) return true;

        return (share.balanceOf(_user) + _amount <= _balanceCap);
    }

    /// @dev Checks if the Prize Pool can receive liquidity based on the current cap
    /// @param _amount The amount of liquidity to be added to the Prize Pool
    /// @return True if the Prize Pool can receive the specified amount of liquidity
    function _canAddLiquidity(uint256 _amount) internal view returns (bool) {
        uint256 _liquidityCap = liquidityCap;
        if (_liquidityCap == type(uint256).max) return true;
        return (_shareTotalSupply() + _amount <= _liquidityCap);
    }

    /// @dev Checks if a specific token is controlled by the Prize Pool
    /// @param _controlledToken The address of the token to check
    /// @return True if the token is a controlled token, false otherwise
    function _isControlled(IShare _controlledToken) internal view returns (bool) {
        return (share == _controlledToken);
    }

    /// @notice Allows the owner to set a balance cap per `token` for the pool.
    /// @param _balanceCap New balance cap.
    function _setBalanceCap(uint256 _balanceCap) internal {
        balanceCap = _balanceCap;
        emit BalanceCapSet(_balanceCap);
    }

    /// @notice Allows the owner to set a liquidity cap for the pool
    /// @param _liquidityCap New liquidity cap
    function _setLiquidityCap(uint256 _liquidityCap) internal {
        liquidityCap = _liquidityCap;
        emit LiquidityCapSet(_liquidityCap);
    }

    /// @notice Sets the prize strategy of the prize pool.  Only callable by the owner.
    /// @param _prizeStrategy The new prize strategy
    function _setPrizeStrategy(address _prizeStrategy) internal {
        require(_prizeStrategy != address(0), "PrizePool/prizeStrategy-not-zero");

        prizeStrategy = _prizeStrategy;

        emit PrizeStrategySet(_prizeStrategy);
    }

    /// @notice The current total of share.
    /// @return share total supply.
    function _shareTotalSupply() internal view returns (uint256) {
        return share.totalSupply();
    }

    /// @dev Gets the current time as represented by the current block
    /// @return The timestamp of the current block
    function _currentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /* ============ Abstract Contract Implementatiton ============ */

    /// @notice Returns the ERC20 asset token used for deposits.
    /// @return The ERC20 asset token
    function _token() internal view virtual returns (IERC20);

    /// @notice Returns the total balance (in asset tokens).  This includes the deposits and interest.
    /// @return The underlying balance of asset tokens
    function _balance() internal virtual returns (uint256);

    /// @notice Supplies asset tokens to the yield source.
    /// @param _mintAmount The amount of asset tokens to be supplied
    function _supply(uint256 _mintAmount) internal virtual;

    /// @notice Redeems asset tokens from the yield source.
    /// @param _redeemAmount The amount of yield-bearing tokens to be redeemed
    /// @return The actual amount of tokens that were redeemed.
    function _redeem(uint256 _redeemAmount) internal virtual returns (uint256);
}
