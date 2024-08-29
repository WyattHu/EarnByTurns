// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/ExtendedSafeCastLib.sol";
import "./libraries/TwabLib.sol";
import "./interfaces/IShare.sol";
import "./ControlledToken.sol";

/**
  * @title  Share
  * @author Wyatt
  * @notice The Share extends the standard ERC20 and ControlledToken interfaces with time-weighted average balance functionality.
            The average balance held by a user between two timestamps can be calculated, as well as the historic balance.  The
            historic total supply is available as well as the average total supply between two timestamps.

            A user may "delegate" their balance; increasing another user's historic balance while retaining their tokens.
*/
contract Share is ControlledToken, IShare {
    using SafeERC20 for IERC20;
    using ExtendedSafeCastLib for uint256;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _DELEGATE_TYPEHASH =
        keccak256("Delegate(address user,address delegate,uint256 nonce,uint256 deadline)");

    //用户的账户信息
    /// @notice Record of token holders TWABs for each account.
    mapping(address => TwabLib.Account) internal userTwabs;

    ///总供应量的信息
    /// @notice Record of share total supply and ring buff parameters used for observation.
    TwabLib.Account internal totalSupplyTwab;

    // //对应委托人
    // /// @notice Mapping of delegates.  Each address can delegate their share power to another.
    // mapping(address => address) internal delegates;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs Share with passed parameters.
     * @param _name ERC20 share token name.
     * @param _symbol ERC20 share token symbol.
     * @param decimals_ ERC20 share token decimals.
     * @param _controller ERC20 share controller address (ie: Prize Pool address).
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _controller
    ) ControlledToken(_name, _symbol, decimals_, _controller) {}

    /* ============ External Functions ============ */

    /// @inheritdoc IShare
    function getAccountDetails(address _user)
        external
        view
        override
        returns (TwabLib.AccountDetails memory)
    {
        return userTwabs[_user].details;
    }

    /// @inheritdoc IShare
    function getTwab(address _user, uint16 _index)
        external
        view
        override
        returns (ObservationLib.Observation memory)
    {
        return userTwabs[_user].twabs[_index];
    }

    /// @inheritdoc IShare
    function getBalanceAt(address _user, uint64 _target) external view override returns (uint256) {
        TwabLib.Account storage account = userTwabs[_user];

        return
            TwabLib.getBalanceAt(
                account.twabs,
                account.details,
                uint32(_target),
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc IShare
    function getAverageBalancesBetween(
        address _user,
        uint64[] calldata _startTimes,
        uint64[] calldata _endTimes
    ) external view override returns (uint256[] memory) {
        return _getAverageBalancesBetween(userTwabs[_user], _startTimes, _endTimes);
    }

    /// @inheritdoc IShare
    function getAverageTotalSuppliesBetween(
        uint64[] calldata _startTimes,
        uint64[] calldata _endTimes
    ) external view override returns (uint256[] memory) {
        return _getAverageBalancesBetween(totalSupplyTwab, _startTimes, _endTimes);
    }

    /// @inheritdoc IShare
    function getAverageBalanceBetween(
        address _user,
        uint64 _startTime,
        uint64 _endTime
    ) external view override returns (uint256) {
        TwabLib.Account storage account = userTwabs[_user];

        return
            TwabLib.getAverageBalanceBetween(
                account.twabs,
                account.details,
                uint32(_startTime),
                uint32(_endTime),
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc IShare
    function getBalancesAt(address _user, uint64[] calldata _targets)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = _targets.length;
        uint256[] memory _balances = new uint256[](length);

        TwabLib.Account storage twabContext = userTwabs[_user];
        TwabLib.AccountDetails memory details = twabContext.details;

        for (uint256 i = 0; i < length; i++) {
            _balances[i] = TwabLib.getBalanceAt(
                twabContext.twabs,
                details,
                uint32(_targets[i]),
                uint32(block.timestamp)
            );
        }

        return _balances;
    }

    /// @inheritdoc IShare
    function getTotalSupplyAt(uint64 _target) external view override returns (uint256) {
        return
            TwabLib.getBalanceAt(
                totalSupplyTwab.twabs,
                totalSupplyTwab.details,
                uint32(_target),
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc IShare
    function getTotalSuppliesAt(uint64[] calldata _targets)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = _targets.length;
        uint256[] memory totalSupplies = new uint256[](length);

        TwabLib.AccountDetails memory details = totalSupplyTwab.details;

        for (uint256 i = 0; i < length; i++) {
            totalSupplies[i] = TwabLib.getBalanceAt(
                totalSupplyTwab.twabs,
                details,
                uint32(_targets[i]),
                uint32(block.timestamp)
            );
        }

        return totalSupplies;
    }


    /* ============ Internal Functions ============ */

    /**
     * @notice Retrieves the average balances held by a user for a given time frame.
     * @param _account The user whose balance is checked.
     * @param _startTimes The start time of the time frame.
     * @param _endTimes The end time of the time frame.
     * @return The average balance that the user held during the time frame.
     */
    function _getAverageBalancesBetween(
        TwabLib.Account storage _account,
        uint64[] calldata _startTimes,
        uint64[] calldata _endTimes
    ) internal view returns (uint256[] memory) {
        uint256 startTimesLength = _startTimes.length;
        require(startTimesLength == _endTimes.length, "Share/start-end-times-length-match");

        TwabLib.AccountDetails memory accountDetails = _account.details;

        uint256[] memory averageBalances = new uint256[](startTimesLength);
        uint32 currentTimestamp = uint32(block.timestamp);

        for (uint256 i = 0; i < startTimesLength; i++) {
            averageBalances[i] = TwabLib.getAverageBalanceBetween(
                _account.twabs,
                accountDetails,
                uint32(_startTimes[i]),
                uint32(_endTimes[i]),
                currentTimestamp
            );
        }

        return averageBalances;
    }

    // // @inheritdoc ERC20
    // function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal override {
    //     if (_from == _to) {
    //         return;
    //     }

    //     address _fromDelegate;
    //     if (_from != address(0)) {
    //         _fromDelegate = delegates[_from];
    //     }

    //     address _toDelegate;
    //     if (_to != address(0)) {
    //         _toDelegate = delegates[_to];
    //     }

    //     _transferTwab(_fromDelegate, _toDelegate, _amount);
    // }

    /// @notice Transfers the given TWAB balance from one user to another
    /// @param _from The user to transfer the balance from.  May be zero in the event of a mint.
    /// @param _to The user to transfer the balance to.  May be zero in the event of a burn.
    /// @param _amount The balance that is being transferred.
    function transferTwab(address _from, address _to, uint256 _amount) external override{
        // If we are transferring tokens from a delegated account to an undelegated account
        if (_from != address(0)) {
            _decreaseUserTwab(_from, _amount);

            if (_to == address(0)) {
                _decreaseTotalSupplyTwab(_amount);
            }
        }

        // If we are transferring tokens from an undelegated account to a delegated account
        if (_to != address(0)) {
            _increaseUserTwab(_to, _amount);

            if (_from == address(0)) {
                _increaseTotalSupplyTwab(_amount);
            }
        }
    }

    /**
     * @notice Increase `_to` TWAB balance.
     * @param _to Address of the delegate.
     * @param _amount Amount of tokens to be added to `_to` TWAB balance.
     */
    function _increaseUserTwab(
        address _to,
        uint256 _amount
    ) internal {
        require(_amount > 0, "Share/increaseUserTwab needs more amount!");

        TwabLib.Account storage _account = userTwabs[_to];

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory twab,
            bool isNew
        ) = TwabLib.increaseBalance(_account, _amount.toUint208(), uint32(block.timestamp));

        _account.details = accountDetails;

        if (isNew) {
            emit NewUserTwab(_to, twab);
        }
    }

    /**
     * @notice Decrease `_to` TWAB balance.
     * @param _to Address of the delegate.
     * @param _amount Amount of tokens to be added to `_to` TWAB balance.
     */
    function _decreaseUserTwab(
        address _to,
        uint256 _amount
    ) internal {
        require(_amount > 0, "Share/decreaseUserTwab needs more amount!");

        TwabLib.Account storage _account = userTwabs[_to];

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory twab,
            bool isNew
        ) = TwabLib.decreaseBalance(
                _account,
                _amount.toUint208(),
                "Share/twab-burn-lt-balance",
                uint32(block.timestamp)
            );

        _account.details = accountDetails;

        if (isNew) {
            emit NewUserTwab(_to, twab);
        }
    }

    /// @notice Decreases the total supply twab.  Should be called anytime a balance moves from delegated to undelegated
    /// @param _amount The amount to decrease the total by
    function _decreaseTotalSupplyTwab(uint256 _amount) internal {
        require(_amount > 0, "Share/decreaseTotalSupplyTwab needs more amount!");

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory tsTwab,
            bool tsIsNew
        ) = TwabLib.decreaseBalance(
                totalSupplyTwab,
                _amount.toUint208(),
                "Share/burn-amount-exceeds-total-supply-twab",
                uint32(block.timestamp)
            );

        totalSupplyTwab.details = accountDetails;

        if (tsIsNew) {
            emit NewTotalSupplyTwab(tsTwab);
        }
    }

    /// @notice Increases the total supply twab.  Should be called anytime a balance moves from undelegated to delegated
    /// @param _amount The amount to increase the total by
    function _increaseTotalSupplyTwab(uint256 _amount) internal {
        require(_amount > 0, "Share/increaseTotalSupplyTwab needs more amount!");

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory _totalSupply,
            bool tsIsNew
        ) = TwabLib.increaseBalance(totalSupplyTwab, _amount.toUint208(), uint32(block.timestamp));

        totalSupplyTwab.details = accountDetails;

        if (tsIsNew) {
            emit NewTotalSupplyTwab(_totalSupply);
        }
    }
}
