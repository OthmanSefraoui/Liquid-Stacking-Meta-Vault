// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";

contract StakerRewards is Ownable, ReentrancyGuard {
    uint256 public constant VALIDATOR_SIZE = 32 ether;
    uint256 public constant RAY = 1e27;

    struct VaultInfo {
        uint256 stakedETH; // Amount of ETH staked
        uint256 bidAmount; // Total bid amount paid upfront
        uint256 rewardPeriod; // Period length in seconds
        uint256 lastUpdateTimestamp; // Last time rewards were updated
        uint256 startTime; // When vault staking started
        uint256 endTime; // When vault staking ends
        uint256 rewardsPerETHPerSecond; // Vault-specific rewards per ETH per second
        uint256 rewardsIndex; // Accumulated rewards index for this vault
        bool isActive; // Whether vault is active
    }

    struct GlobalRewards {
        uint256 averageRewardsPerETHPerSecond; // Average rewards per ETH per second across all vaults
        uint256 totalStakedETH; // Total ETH staked across all active vaults
        uint256 rewardsIndex; // Global rewards accumulation index
        uint256 lastUpdateTimestamp; // Last time the global index was updated
    }

    // Interfaces and immutable variables
    IERC20 public immutable rewardToken;
    address public immutable bidInvestmentContract;

    // Global tracking
    GlobalRewards public globalRewards;
    uint256 public numberOfActiveVaults;

    // Mappings
    mapping(address => VaultInfo) public vaults;

    // Events
    event VaultRegistered(
        address indexed vault,
        uint256 stakedETH,
        uint256 bidAmount,
        uint256 rewardPeriod,
        uint256 rewardsPerETHPerSecond
    );
    event RewardsClaimed(address indexed vault, uint256 amount);
    event IndexUpdated(uint256 newIndex, uint256 timestamp);
    event AverageRewardsUpdated(uint256 newAverageRewards);

    constructor(IERC20 _rewardToken, address _bidInvestment) Ownable(msg.sender) {
        require(address(_rewardToken) != address(0), "Invalid reward token");
        require(_bidInvestment != address(0), "Invalid bid investment contract");

        rewardToken = _rewardToken;
        bidInvestmentContract = _bidInvestment;

        globalRewards = GlobalRewards({
            averageRewardsPerETHPerSecond: 0,
            totalStakedETH: 0,
            rewardsIndex: RAY,
            lastUpdateTimestamp: block.timestamp
        });
    }

    /**
     * @dev Calculates rewards per ETH per second for a vault
     */
    function _calculateRewardsPerETHPerSecond(uint256 _bidAmount, uint256 _stakedETH, uint256 _rewardPeriod)
        internal
        pure
        returns (uint256)
    {
        // rewardsPerETHPerSecond = (bidAmount * RAY) / (stakedETH * rewardPeriod)
        return (_bidAmount * RAY) / (_stakedETH * _rewardPeriod);
    }

    /**
     * @dev Updates average rewards when adding a new vault
     */
    function _updateAverageRewardsOnAdd(uint256 newRewardsPerETHPerSecond) internal {
        GlobalRewards storage rewards = globalRewards;

        if (numberOfActiveVaults == 0) {
            rewards.averageRewardsPerETHPerSecond = newRewardsPerETHPerSecond;
        } else {
            // Calculate new weighted average
            rewards.averageRewardsPerETHPerSecond = (
                rewards.averageRewardsPerETHPerSecond * numberOfActiveVaults + newRewardsPerETHPerSecond
            ) / (numberOfActiveVaults + 1);
        }

        emit AverageRewardsUpdated(rewards.averageRewardsPerETHPerSecond);
    }

    /**
     * @dev Updates average rewards when removing a vault
     */
    function _updateAverageRewardsOnRemove(uint256 vaultRewardsPerETHPerSecond) internal {
        GlobalRewards storage rewards = globalRewards;

        if (numberOfActiveVaults == 1) {
            rewards.averageRewardsPerETHPerSecond = 0;
        } else {
            // Remove vault's contribution from weighted average
            rewards.averageRewardsPerETHPerSecond = (
                rewards.averageRewardsPerETHPerSecond * numberOfActiveVaults - vaultRewardsPerETHPerSecond
            ) / (numberOfActiveVaults - 1);
        }

        emit AverageRewardsUpdated(rewards.averageRewardsPerETHPerSecond);
    }

    /**
     * @dev Updates the global rewards index based on time-weighted rewards
     */
    function _updateRewardsIndex() internal {
        GlobalRewards storage rewards = globalRewards;
        uint256 currentTimestamp = block.timestamp;

        if (currentTimestamp == rewards.lastUpdateTimestamp || rewards.totalStakedETH == 0) {
            return;
        }

        uint256 timeDelta = currentTimestamp - rewards.lastUpdateTimestamp;

        // Calculate rewards for the period, scaling by RAY for precision
        rewards.rewardsIndex += (rewards.averageRewardsPerETHPerSecond * timeDelta);
        rewards.lastUpdateTimestamp = currentTimestamp;

        emit IndexUpdated(rewards.rewardsIndex, currentTimestamp);
    }

    function registerVault(address _vault, uint256 _stakedETH, uint256 _bidAmount, uint256 _rewardPeriod)
        external
        onlyOwner
    {
        require(_vault != address(0), "Invalid vault address");
        require(_stakedETH % VALIDATOR_SIZE == 0, "Stake must be multiple of 32 ETH");
        require(_bidAmount > 0, "Bid amount must be positive");
        require(_rewardPeriod > 0, "Reward period must be positive");
        require(!vaults[_vault].isActive, "Vault already registered");

        // Update global index before adding new vault
        _updateRewardsIndex();

        // Calculate vault-specific rewards per ETH per second
        //uint256 rewardsPerETHPerSecond = _calculateRewardsPerETHPerSecond(_bidAmount, _stakedETH, _rewardPeriod);
        uint256 rewardsPerETHPerSecond = (_bidAmount * RAY) / (_stakedETH * _rewardPeriod);

        // Update average rewards rate
        _updateAverageRewardsOnAdd(rewardsPerETHPerSecond);

        // Transfer bid amount from investment contract
        require(
            rewardToken.transferFrom(bidInvestmentContract, address(this), _bidAmount), "Bid amount transfer failed"
        );

        // Update global tracking
        GlobalRewards storage rewards = globalRewards;
        rewards.totalStakedETH += _stakedETH;
        numberOfActiveVaults++;

        // Create vault info
        vaults[_vault] = VaultInfo({
            stakedETH: _stakedETH,
            bidAmount: _bidAmount,
            rewardPeriod: _rewardPeriod,
            lastUpdateTimestamp: block.timestamp,
            startTime: block.timestamp,
            endTime: block.timestamp + _rewardPeriod,
            rewardsPerETHPerSecond: rewardsPerETHPerSecond,
            rewardsIndex: rewards.rewardsIndex,
            isActive: true
        });

        emit VaultRegistered(_vault, _stakedETH, _bidAmount, _rewardPeriod, rewardsPerETHPerSecond);
    }

    function claimRewards() external nonReentrant returns (uint256) {
        _updateRewardsIndex();

        VaultInfo storage vault = vaults[msg.sender];
        GlobalRewards storage rewards = globalRewards;

        require(vault.isActive, "Vault not active");
        require(block.timestamp < vault.endTime, "Reward period ended");

        // uint256 timeDelta = block.timestamp - vault.lastUpdateTimestamp;
        // uint256 rewardsPerETH = rewards.averageRewardsPerETHPerSecond * timeDelta;
        // uint256 pendingRewards = (vault.stakedETH * rewardsPerETH) / RAY;

        uint256 rewardsPerETH = rewards.rewardsIndex - vault.rewardsIndex;
        uint256 pendingRewards = (vault.stakedETH * rewardsPerETH) / RAY;

        require(pendingRewards > 0, "No rewards available");

        // Update vault's tracking
        vault.rewardsIndex = rewards.rewardsIndex;
        vault.lastUpdateTimestamp = block.timestamp;

        // Check if this is the last claim (close to end period)
        if (block.timestamp + 1 days >= vault.endTime) {
            rewards.totalStakedETH -= vault.stakedETH;
            _updateAverageRewardsOnRemove(vault.rewardsPerETHPerSecond);
            numberOfActiveVaults--;
            vault.isActive = false;
        }

        // Transfer rewards
        require(rewardToken.transfer(msg.sender, pendingRewards), "Reward transfer failed");

        emit RewardsClaimed(msg.sender, pendingRewards);
        return pendingRewards;
    }

    

    function claimFinalRewards() external nonReentrant returns (uint256) {
        VaultInfo storage vault = vaults[msg.sender];
        GlobalRewards storage rewards = globalRewards;

        require(vault.isActive, "Vault not active");
        require(block.timestamp >= vault.endTime, "Reward period not ended");

        // Update index before calculating final rewards
        _updateRewardsIndex();

        // Calculate remaining rewards until end time
        uint256 timeUntilEnd = vault.endTime - vault.lastUpdateTimestamp;
        uint256 rewardsPerETH = rewards.averageRewardsPerETHPerSecond * timeUntilEnd;
        uint256 finalRewards = (vault.stakedETH * rewardsPerETH) / RAY;
        require(finalRewards > 0, "No final rewards available");

        // Store values before state changes
        uint256 vaultStakedETH = vault.stakedETH;

        rewards.totalStakedETH -= vaultStakedETH;
        uint256 vaultRate = vault.rewardsPerETHPerSecond;

        vault.isActive = false;
        vault.lastUpdateTimestamp = vault.endTime;
        vault.rewardsIndex += rewardsPerETH;

        _updateAverageRewardsOnRemove(vaultRate);
        numberOfActiveVaults--;

        // Transfer rewards
        require(rewardToken.transfer(msg.sender, finalRewards), "Reward transfer failed");

        emit RewardsClaimed(msg.sender, finalRewards);
        return finalRewards;
    }
}
