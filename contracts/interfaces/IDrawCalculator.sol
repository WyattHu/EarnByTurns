// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./IShare.sol";
import "./IDrawBuffer.sol";
import "../PrizeDistributionBuffer.sol";
import "../PrizeDistributor.sol";

//用于计算用户在多个抽奖中的奖金额。

/**
 * @title  IDrawCalculator
 * @author Wyatt
 * @notice The DrawCalculator interface.
 */
interface IDrawCalculator {
    struct PickPrize {
        bool won;
        uint8 tierIndex;
    }
    //won: 表示是否中奖。
    //tierIndex: 表示中奖的等级索引。

    ///@notice Emitted when the contract is initialized
    event Deployed(
        IShare indexed share,
        IDrawBuffer indexed drawBuffer,
        IPrizeDistributionBuffer indexed prizeDistributionBuffer
    );

    ///@notice Emitted when the prizeDistributor is set/updated
    event PrizeDistributorSet(PrizeDistributor indexed prizeDistributor);

    /**
     * @notice Calculates the prize amount for a user for Multiple Draws. Typically called by a PrizeDistributor.
     * @param user User for which to calculate prize amount.
     * @param drawIds drawId array for which to calculate prize amounts for.
     * @param data The ABI encoded pick indices for all Draws. Expected to be winning picks. Pick indices must be less than the totalUserPicks.
     * @return List of awardable prize amounts ordered by drawId.
     */
     //计算用户在多个抽奖中的奖金额，通常由PrizeDistributor调用。
    function calculate(
        address user,
        uint32[] calldata drawIds,
        bytes calldata data
    ) external view returns (uint256[] memory, bytes memory);

    /**
     * @notice Read global DrawBuffer variable.
     * @return IDrawBuffer
     */
    function getDrawBuffer() external view returns (IDrawBuffer);

    /**
     * @notice Read global prizeDistributionBuffer variable.
     * @return IPrizeDistributionBuffer
     */
    function getPrizeDistributionBuffer() external view returns (IPrizeDistributionBuffer);

    /**
     * @notice Returns a users balances expressed as a fraction of the total supply over time.
     * @param user The users address
     * @param drawIds The drawIds to consider
     * @return Array of balances
     */
     //返回以一段时间内总供应量的比例表示的用户余额。
    function getNormalizedBalancesForDrawIds(address user, uint32[] calldata drawIds)
        external
        view
        returns (uint256[] memory);

}
