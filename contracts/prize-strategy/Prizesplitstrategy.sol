// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../interfaces/IPrizeSplitStrategy.sol";
import "../interfaces/IPrizePool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
  * @title  PrizeSplitStrategy
  * @author Wyatt
  * @notice Captures PrizePool interest for PrizeReserve and additional PrizeSplit recipients.
            The PrizeSplitStrategy will have at minimum a single PrizeSplit with 100% of the captured
            interest transfered to the PrizeReserve. Additional PrizeSplits can be added, depending on
            the deployers requirements (i.e. percentage to charity). In contrast to previous PoolTogether
            iterations, interest can be captured independent of a new Draw. Ideally (to save gas) interest
            is only captured when also distributing the captured prize(s) to applicable Prize Distributor(s).
*/
contract PrizeSplitStrategy is IPrizeSplitStrategy,Ownable {
/* ============ Global Variables ============ */
    PrizeSplitConfig[] internal _prizeSplits;

    uint16 public constant ONE_AS_FIXED_POINT_3 = 1000;

    /**
     * @notice PrizePool address
     */
    IPrizePool internal immutable prizePool;

    /**
     * @notice Deployed Event
     * @param owner Contract owner
     * @param prizePool Linked PrizePool contract
     */
    event Deployed(address indexed owner, IPrizePool prizePool);

    /* ============ Constructor ============ */

    /**
     * @notice Deploy the PrizeSplitStrategy smart contract.
     * @param _owner     Owner address
     * @param _prizePool PrizePool address
     */
    constructor(address _owner, IPrizePool _prizePool) Ownable(_owner) {
        require(
            address(_prizePool) != address(0),
            "PrizeSplitStrategy/prize-pool-not-zero-address"
        );
        prizePool = _prizePool;
        emit Deployed(_owner, _prizePool);
    }

    /* ============ External Functions ============ */


    /// @inheritdoc IPrizeSplitStrategy
    function distribute() external override returns (uint256) {
        uint256 prize = prizePool.captureAwardBalance();

        if (prize == 0) return 0;

        uint256 prizeRemaining = _distributePrizeSplits(prize);

        emit Distributed(prize - prizeRemaining);

        return prize;
    }

    /// @inheritdoc IPrizeSplitStrategy
    function getPrizePool() external view override returns (IPrizePool) {
        return prizePool;
    }

    /// @inheritdoc IPrizeSplitStrategy
    function getPrizeSplit(uint256 _prizeSplitIndex)
        external
        view
        override
        returns (PrizeSplitConfig memory)
    {
        return _prizeSplits[_prizeSplitIndex];
    }

    /// @inheritdoc IPrizeSplitStrategy
    function getPrizeSplits() external view override returns (PrizeSplitConfig[] memory) {
        return _prizeSplits;
    }

    /// @inheritdoc IPrizeSplitStrategy
    function setPrizeSplits(PrizeSplitConfig[] calldata _newPrizeSplits)
        external
        override
        onlyOwner
    {
        uint256 newPrizeSplitsLength = _newPrizeSplits.length;
        require(newPrizeSplitsLength <= type(uint8).max, "PrizeSplit/invalid-prizesplits-length");

        // Add and/or update prize split configs using _newPrizeSplits PrizeSplitConfig structs array.
        for (uint256 index = 0; index < newPrizeSplitsLength; index++) {
            PrizeSplitConfig memory split = _newPrizeSplits[index];

            // REVERT when setting the canonical burn address.
            require(split.target != address(0), "PrizeSplit/invalid-prizesplit-target");

            // IF the CURRENT prizeSplits length is below the NEW prizeSplits
            // PUSH the PrizeSplit struct to end of the list.
            if (_prizeSplits.length <= index) {
                _prizeSplits.push(split);
            } else {
                // ELSE update an existing PrizeSplit struct with new parameters
                PrizeSplitConfig memory currentSplit = _prizeSplits[index];

                // IF new PrizeSplit DOES NOT match the current PrizeSplit
                // WRITE to STORAGE with the new PrizeSplit
                if (
                    split.target != currentSplit.target ||
                    split.percentage != currentSplit.percentage
                ) {
                    _prizeSplits[index] = split;
                } else {
                    continue;
                }
            }

            // Emit the added/updated prize split config.
            emit PrizeSplitSet(split.target, split.percentage, index);
        }

        // Remove old prize splits configs. Match storage _prizesSplits.length with the passed newPrizeSplits.length
        while (_prizeSplits.length > newPrizeSplitsLength) {
            uint256 _index;
            unchecked {
                _index = _prizeSplits.length - 1;
            }
            _prizeSplits.pop();
            emit PrizeSplitRemoved(_index);
        }

        // Total prize split do not exceed 100%
        uint256 totalPercentage = _totalPrizeSplitPercentageAmount();
        require(totalPercentage <= ONE_AS_FIXED_POINT_3, "PrizeSplit/invalid-prizesplit-percentage-total");
    }

    /// @inheritdoc IPrizeSplitStrategy
    function setPrizeSplit(PrizeSplitConfig memory _prizeSplit, uint8 _prizeSplitIndex)
        external
        override
        onlyOwner
    {
        require(_prizeSplitIndex < _prizeSplits.length, "PrizeSplit/nonexistent-prizesplit");
        require(_prizeSplit.target != address(0), "PrizeSplit/invalid-prizesplit-target");

        // Update the prize split config
        _prizeSplits[_prizeSplitIndex] = _prizeSplit;

        // Total prize split do not exceed 100%
        uint256 totalPercentage = _totalPrizeSplitPercentageAmount();
        require(totalPercentage <= ONE_AS_FIXED_POINT_3, "PrizeSplit/invalid-prizesplit-percentage-total");

        // Emit updated prize split config
        emit PrizeSplitSet(
            _prizeSplit.target,
            _prizeSplit.percentage,
            _prizeSplitIndex
        );
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Calculates total prize split percentage amount.
     * @dev Calculates total PrizeSplitConfig percentage(s) amount. Used to check the total does not exceed 100% of award distribution.
     * @return Total prize split(s) percentage amount
     */
    function _totalPrizeSplitPercentageAmount() internal view returns (uint256) {
        uint256 _tempTotalPercentage;
        uint256 prizeSplitsLength = _prizeSplits.length;

        for (uint256 index = 0; index < prizeSplitsLength; index++) {
            _tempTotalPercentage += _prizeSplits[index].percentage;
        }

        return _tempTotalPercentage;
    }

    /**
     * @notice Distributes prize split(s).
     * @dev Distributes prize split(s) by awarding share or sponsorship tokens.
     * @param _prize Starting prize award amount
     * @return The remainder after splits are taken
     */
    function _distributePrizeSplits(uint256 _prize) internal returns (uint256) {
        uint256 _prizeTemp = _prize;
        uint256 prizeSplitsLength = _prizeSplits.length;

        for (uint256 index = 0; index < prizeSplitsLength; index++) {
            PrizeSplitConfig memory split = _prizeSplits[index];
            uint256 _splitAmount = (_prize * split.percentage) / 1000;

            // Award the prize split distribution amount.
            _awardPrizeSplitAmount(split.target, _splitAmount);

            // Update the remaining prize amount after distributing the prize split percentage.
            _prizeTemp -= _splitAmount;
        }

        return _prizeTemp;
    }

    /**
     * @notice Award share tokens to prize split recipient.
     * @dev Award share tokens to prize split recipient via the linked PrizePool contract.
     * @param _to Recipient of minted tokens.
     * @param _amount Amount of minted tokens.
     */
    function _awardPrizeSplitAmount(address _to, uint256 _amount) internal {
        IControlledToken _share = prizePool.getShare();
        prizePool.award(_to, _amount);
        emit PrizeSplitAwarded(_to, _amount, _share);
    }

}
