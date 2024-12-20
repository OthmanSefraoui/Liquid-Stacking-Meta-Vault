# StakerRewards Contract

## Overview

The StakerRewards contract manages reward distribution for a staking system with multiple validator vaults. It handles scenarios where validators can stake different amounts of ETH for varying durations, with a bid-based reward structure.

## Key Concepts

### Vaults

- Each vault represents a staking position with a specific amount of ETH (multiple of 32)
- Vaults can be created at different timestamps
- Each vault has a predefined staking period and associated bid amount
- Bid amounts determine the rewards to be distributed over the staking period

### Reward Distribution

The contract implements an index-based reward tracking system. This system:

- Efficiently tracks rewards across multiple vaults
- Handles dynamic rate changes when vaults enter/exit
- Maintains precision using RAY (27 decimals)
- Distributes rewards proportionally to staked amounts

### Reward Calculation

For each vault:

- Rate = bidAmount / (stakedETH \* period)
- Average rate is maintained across all active vaults
- Rewards accumulate through an index that increases based on the average rate
- Individual rewards are calculated using index differences

## Contract Design

### Key State Variables

```solidity
struct VaultInfo {
    uint256 stakedETH;
    uint256 bidAmount;
    uint256 rewardPeriod;
    uint256 lastUpdateTimestamp;
    uint256 startTime;
    uint256 endTime;
    uint256 rewardsPerETHPerSecond;
    uint256 rewardsIndex;
    bool isActive;
}

struct GlobalRewards {
    uint256 averageRewardsPerETHPerSecond;
    uint256 totalStakedETH;
    uint256 rewardsIndex;
    uint256 lastUpdateTimestamp;
}
```

### Core Functions

1. `registerVault`: Creates a new vault with specified stake, bid, and period
2. `claimRewards`: Allows periodic reward claims during active period
3. `claimFinalRewards`: Handles final reward distribution at period end

### Reward Tracking Mechanism

- Global index accumulates at the average rate
- Each vault tracks its last-seen index
- Rewards = stakedETH \* (currentIndex - lastSeenIndex)

## Technical Implementation

### Index Updates

The index updates follow these rules:

- Updated before any reward calculations
- Accumulates based on time elapsed and current average rate

### Rate Calculations

When multiple vaults are active:

- Each vault's rate = bidAmount / (stakedETH \* period)
- Global average rate updates when vaults join/leave
- All calculations use RAY precision (1e27)

### Edge Cases Handled

- Multiple vaults with different stake amounts
- Varying staking periods
- Vault registration at different times
- Rate changes when vaults end

## Usage Example

```solidity
// Register a vault with 32 ETH stake
uint256 stake = 32 ether;
uint256 bid = 1 ether;
uint256 period = 100 days;
stakerRewards.registerVault(vault, stake, bid, period);

// Claim rewards periodically
stakerRewards.claimRewards();

// Claim final rewards at period end
stakerRewards.claimFinalRewards();
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```
