// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/StakerRewards.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract StakerRewardsTest is Test {
    StakerRewards public stakerRewards;
    MockToken public token;
    address public bidInvestment;
    address public vault1;
    address public vault2;
    address public vault3;

    uint256 public constant REWARD_PERIOD = 100 days;
    uint256 public constant VALIDATOR_SIZE = 32 ether;
    uint256 public constant RAY = 1e27;

    function setUp() public {
        token = new MockToken();
        bidInvestment = makeAddr("bidInvestment");
        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");
        vault3 = makeAddr("vault3");

        stakerRewards = new StakerRewards(token, bidInvestment);

        token.mint(bidInvestment, 1000 ether);
        vm.startPrank(bidInvestment);
        token.approve(address(stakerRewards), type(uint256).max);
        vm.stopPrank();
    }

    function test_registerFirstVault() public {
        uint256 stakedAmount = VALIDATOR_SIZE; // 32 ETH = 1 validator
        uint256 bidAmount = 1 ether;

        // Initial state checks
        (uint256 averageRewardsPerETHPerSecond, uint256 totalStakedETH,,) = stakerRewards.globalRewards();
        assertEq(totalStakedETH, 0);
        assertEq(averageRewardsPerETHPerSecond, 0);
        assertEq(stakerRewards.numberOfActiveVaults(), 0);

        // Register vault
        vm.prank(stakerRewards.owner());
        stakerRewards.registerVault(vault1, stakedAmount, bidAmount, REWARD_PERIOD);

        // Retrieve vault info
        (
            uint256 stakedETH,
            uint256 vaultBidAmount,
            uint256 rewardPeriod,
            uint256 lastUpdateTimestamp,
            uint256 startTime,
            uint256 endTime,
            uint256 rewardsPerETHPerSecond,
            uint256 rewardsIndex,
            bool isActive
        ) = stakerRewards.vaults(vault1);

        // Calculate expected rewards per ETH per second
        uint256 expectedRate = (bidAmount * RAY) / (stakedAmount * REWARD_PERIOD);
        (uint256 averageRewardsPerETHPerSecond_, uint256 totalStakedETH_,,) = stakerRewards.globalRewards();
        // Assertions
        assertEq(stakedETH, stakedAmount, "Incorrect staked amount");
        assertEq(vaultBidAmount, bidAmount, "Incorrect bid amount");
        assertEq(rewardsPerETHPerSecond, expectedRate, "Rewards per ETH per second incorrect");
        assertEq(averageRewardsPerETHPerSecond_, expectedRate, "Average rewards rate incorrect");
        assertEq(totalStakedETH_, stakedAmount, "Total staked ETH incorrect");
        assertEq(stakerRewards.numberOfActiveVaults(), 1, "Active vault count incorrect");
        assertTrue(isActive, "Vault should be active");
        assertEq(endTime - startTime, REWARD_PERIOD, "Incorrect period");
    }

    function test_multipleVaults() public {
        // Register Vault1: 1 validator, 1 ETH reward, 100 days
        vm.startPrank(stakerRewards.owner());
        stakerRewards.registerVault(vault1, VALIDATOR_SIZE, 1 ether, REWARD_PERIOD);
        uint256 rate1 = (1 ether * RAY) / (VALIDATOR_SIZE * REWARD_PERIOD);
        (uint256 averageRewardsPerETHPerSecond, uint256 totalStakedETH,,) = stakerRewards.globalRewards();
        assertEq(averageRewardsPerETHPerSecond, rate1, "First rate incorrect");
        console.log("Rate1:", rate1);

        // Move forward 30 days and register Vault2: 3 validators, 4.5 ETH, 150 days
        vm.warp(block.timestamp + 30 days);
        stakerRewards.registerVault(vault2, VALIDATOR_SIZE * 3, 4.5 ether, 150 days);
        uint256 rate2 = (4.5 ether * RAY) / (VALIDATOR_SIZE * 3 * 150 days);

        // New rate should be average
        uint256 expectedRate = (rate1 + rate2) / 2;
        (uint256 averageRewardsPerETHPerSecond_2,,,) = stakerRewards.globalRewards();
        console.log("Rate2:", rate2);
        console.log("Expected average rate:", expectedRate);
        console.log("Actual rate:", averageRewardsPerETHPerSecond_2);

        assertApproxEqAbs(averageRewardsPerETHPerSecond_2, expectedRate, 1e8, "Average rate incorrect");

        // Move forward 30 more days and register Vault3: 6 validators, 3.6 ETH, 90 days
        vm.warp(block.timestamp + 30 days);
        stakerRewards.registerVault(vault3, VALIDATOR_SIZE * 6, 3.6 ether, 90 days);
        uint256 rate3 = (3.6 ether * RAY) / (VALIDATOR_SIZE * 6 * 90 days);
        (uint256 averageRewardsPerETHPerSecond_3,,,) = stakerRewards.globalRewards();
        expectedRate = (rate1 + rate2 + rate3) / 3;
        console.log("Rate3:", rate3);
        console.log("Final expected rate:", expectedRate);
        console.log("Final actual rate:", averageRewardsPerETHPerSecond_3);

        assertApproxEqAbs(averageRewardsPerETHPerSecond_3, expectedRate, 1e8, "Final average rate incorrect");

        vm.stopPrank();
    }

    function test_claimRewardsAndEndPeriod() public {
        // Register vault with 1 validator, 1 ETH reward
        vm.prank(stakerRewards.owner());
        stakerRewards.registerVault(vault1, VALIDATOR_SIZE, 1 ether, REWARD_PERIOD);

        // Get initial state
        (uint256 rate,, uint256 initialIndex,) = stakerRewards.globalRewards();
        console.log("Initial index:", initialIndex);
        console.log("Rate:", rate);

        // Move halfway through period
        vm.warp(block.timestamp + REWARD_PERIOD / 2);

        // Claim first half rewards
        vm.prank(vault1);
        uint256 claimed = stakerRewards.claimRewards();
        console.log("First half claimed:", claimed);
        assertApproxEqRel(claimed, 0.5 ether, 1e16, "Should claim half rewards");

        // Move to end of period
        vm.warp(block.timestamp + REWARD_PERIOD / 2);

        // Claim final rewards using the new function
        vm.prank(vault1);
        uint256 finalClaim = stakerRewards.claimFinalRewards();
        console.log("Final claim:", finalClaim);
        assertApproxEqRel(finalClaim, 0.5 ether, 1e16, "Should claim remaining rewards");

        // Check final state
        (,,,,,,,, bool isActive) = stakerRewards.vaults(vault1);
        (uint256 averageRewardsPerETHPerSecond, uint256 totalStakedETH,,) = stakerRewards.globalRewards();

        assertFalse(isActive, "Vault should be inactive");
        assertEq(totalStakedETH, 0, "Should have no staked ETH");
        assertEq(stakerRewards.numberOfActiveVaults(), 0, "Should have no active vaults");
        assertEq(averageRewardsPerETHPerSecond, 0, "Average rate should be zero");
    }

    function test_removeVaultAverageRate() public {
        vm.startPrank(stakerRewards.owner());

        // Register vault1 with 1 validator (32 ETH) and 1 ETH reward for 100 days
        stakerRewards.registerVault(vault1, VALIDATOR_SIZE, 1 ether, REWARD_PERIOD);
        uint256 rate1 = (1 ether * RAY) / (VALIDATOR_SIZE * REWARD_PERIOD);

        console.log("Rate1:", rate1);
        (uint256 averageRate, uint256 totalStaked,,) = stakerRewards.globalRewards();
        console.log("Average rate after vault1:", averageRate);
        console.log("Total staked after vault1:", totalStaked);
        assertEq(averageRate, rate1, "Initial rate should equal rate1");
        assertEq(totalStaked, VALIDATOR_SIZE, "Initial stake should be 32 ETH");

        // Register vault2 with 2 validators (64 ETH) and 3 ETH reward for 100 days
        stakerRewards.registerVault(vault2, VALIDATOR_SIZE * 2, 3 ether, REWARD_PERIOD);
        uint256 rate2 = (3 ether * RAY) / (VALIDATOR_SIZE * 2 * REWARD_PERIOD);

        console.log("Rate2:", rate2);
        (uint256 initialAverageRate, uint256 totalStaked_2,,) = stakerRewards.globalRewards();
        console.log("Average rate after vault2:", initialAverageRate);
        console.log("Total staked after vault2:", totalStaked_2);

        // Expected average: (rate1 + rate2) / 2
        uint256 expectedInitialAverage = (rate1 + rate2) / 2;
        assertEq(initialAverageRate, expectedInitialAverage, "Initial average rate incorrect");
        assertEq(totalStaked_2, VALIDATOR_SIZE * 3, "Total stake should be 96 ETH");

        // Move to end of vault1's period
        vm.warp(block.timestamp + REWARD_PERIOD);

        // Claim final rewards for vault1 (this should remove it)
        vm.stopPrank();
        vm.prank(vault1);
        stakerRewards.claimFinalRewards();

        // Get new state
        (uint256 finalAverageRate, uint256 totalStaked_3,,) = stakerRewards.globalRewards();
        console.log("Final average rate:", finalAverageRate);
        console.log("Expected rate2:", rate2);
        console.log("Final total staked:", totalStaked_3);
        console.log("Expected total staked:", VALIDATOR_SIZE * 2);

        // After vault1 is removed, average rate should equal rate2
        assertEq(finalAverageRate, rate2, "Average rate should equal rate2 after vault1 removal");
        assertEq(stakerRewards.numberOfActiveVaults(), 1, "Should have 1 active vault");
        assertEq(totalStaked_3, VALIDATOR_SIZE * 2, "Should only have vault2's stake");

        // Verify vault1 is properly deactivated
        (,,,,,,,, bool isActive) = stakerRewards.vaults(vault1);
        assertFalse(isActive, "Vault1 should be inactive");
    }

    function test_twoVaultRewardsClaiming() public {
        // Initialize with clean timestamp
        vm.warp(1000);
        uint256 startTime = block.timestamp;
        uint256 DAY = 1 days;

        console.log("\n=== Initial Setup ===");
        console.log("Start time: %s", startTime);

        // ============ Register Vault1 ============
        vm.startPrank(stakerRewards.owner());

        uint256 vault1Stake = VALIDATOR_SIZE; // 32 ETH
        uint256 vault1Bid = 1 ether; // 1 ETH
        uint256 vault1Period = 100 * DAY; // 100 days

        stakerRewards.registerVault(vault1, vault1Stake, vault1Bid, vault1Period);

        (uint256 rateAfterV1, uint256 stakedAfterV1, uint256 indexAfterV1,) = stakerRewards.globalRewards();
        console.log("\n=== After Vault1 Registration ===");
        console.log("Rate: %s", rateAfterV1);
        console.log("Total staked: %s", stakedAfterV1);
        console.log("Index: %s", indexAfterV1);

        // ============ First Period (0 to 30 days) - Only Vault1 ============
        uint256 firstPeriodEnd = startTime + (30 * DAY);
        vm.warp(firstPeriodEnd);

        vm.stopPrank();
        vm.prank(vault1);
        uint256 vault1FirstClaim = stakerRewards.claimRewards();
        console.log("\n=== First Period Claims (t+30d) ===");
        console.log("Vault1 first claim: %s ETH", vault1FirstClaim);
        assertApproxEqRel(vault1FirstClaim, 0.3 ether, 1e16, "Vault1 first claim should be ~0.3 ETH");

        // ============ Register Vault2 at t+30d ============
        vm.prank(stakerRewards.owner());
        uint256 vault2Stake = VALIDATOR_SIZE * 3; // 96 ETH
        uint256 vault2Bid = 4.5 ether; // 4.5 ETH
        uint256 vault2Period = 150 * DAY; // 150 days

        stakerRewards.registerVault(vault2, vault2Stake, vault2Bid, vault2Period);

        (uint256 rateAfterV2, uint256 stakedAfterV2, uint256 indexAfterV2,) = stakerRewards.globalRewards();
        console.log("\n=== After Vault2 Registration ===");
        console.log("Rate: %s", rateAfterV2);
        console.log("Total staked: %s", stakedAfterV2);
        console.log("Index: %s", indexAfterV2);

        // ============ Second Period (30 to 60 days) - Both Vaults ============
        uint256 secondPeriodEnd = firstPeriodEnd + (30 * DAY);
        vm.warp(secondPeriodEnd);

        vm.prank(vault1);
        uint256 vault1SecondClaim = stakerRewards.claimRewards();
        console.log("\n=== Second Period Claims (t+60d) ===");
        console.log("Vault1 second claim: %s ETH", vault1SecondClaim);
        assertApproxEqRel(vault1SecondClaim, 0.3 ether, 1e16, "Vault1 second claim should be ~0.3 ETH");

        vm.prank(vault2);
        uint256 vault2FirstClaim = stakerRewards.claimRewards();
        console.log("Vault2 first claim: %s ETH", vault2FirstClaim);
        assertApproxEqRel(vault2FirstClaim, 0.9 ether, 1e16, "Vault2 first claim should be ~0.9 ETH");
        (uint256 rateAfterSecondClaim, uint256 stakedAfterSecondClaim, uint256 indexAfterSecondClaim,) =
            stakerRewards.globalRewards();
        console.log("Index: %s", indexAfterSecondClaim);
        // ============ Third Period (60 to 110 days) - Vault1 Ends ============
        vm.warp(9505000);

        vm.prank(vault1);
        uint256 vault1FinalClaim = stakerRewards.claimFinalRewards();
        console.log("\n=== Third Period Claims (t+110d) ===");
        console.log("Vault1 final claim: %s ETH", vault1FinalClaim);
        assertApproxEqRel(vault1FinalClaim, 0.4 ether, 1e16, "Vault1 final claim should be ~0.4 ETH");

        // Log state after Vault1's final claim
        (uint256 rateAfterV1End, uint256 stakedAfterV1End, uint256 indexAfterV1End,) = stakerRewards.globalRewards();
        console.log("\n=== State After Vault1 End ===");
        console.log("Rate: %s", rateAfterV1End);
        console.log("Total staked: %s", stakedAfterV1End);
        console.log("Index: %s", indexAfterV1End);
        console.log("Active vaults: %s", stakerRewards.numberOfActiveVaults());

        // Get Vault2's details before claim
        (
            uint256 v2Staked,
            uint256 v2Bid,
            uint256 v2Period,
            uint256 v2LastUpdate,
            ,
            ,
            uint256 v2Rate,
            uint256 v2Index,
            bool v2Active
        ) = stakerRewards.vaults(vault2);

        console.log("\n=== Vault2 State Before Second Claim ===");
        console.log("Staked: %s", v2Staked);
        console.log("Rate: %s", v2Rate);
        console.log("Last update: %s", v2LastUpdate);
        console.log("Index: %s", v2Index);
        console.log("Active: %s", v2Active);

        vm.prank(vault2);
        uint256 vault2SecondClaim = stakerRewards.claimRewards();
        console.log("Vault2 second claim: %s ETH", vault2SecondClaim);
        assertApproxEqRel(vault2SecondClaim, 1.5 ether, 1e16, "Vault2 second claim should be ~1.5 ETH");

        // Verify Vault1 total rewards
        uint256 vault1Total = vault1FirstClaim + vault1SecondClaim + vault1FinalClaim;
        console.log("\n=== Vault1 Total Rewards ===");
        console.log("Total: %s ETH", vault1Total);
        assertApproxEqRel(vault1Total, 1 ether, 1e16, "Vault1 total rewards incorrect");

        // ============ Fourth Period (110 to 180 days) - Only Vault2 ============
        vm.warp(15638400);

        vm.prank(vault2);
        uint256 vault2FinalClaim = stakerRewards.claimFinalRewards();
        console.log("\n=== Fourth Period Claims (t+180d) ===");
        console.log("Vault2 final claim: %s ETH", vault2FinalClaim);
        assertApproxEqRel(vault2FinalClaim, 2.1 ether, 1e16, "Vault2 final claim should be ~2.1 ETH");

        // Verify Vault2 total rewards
        uint256 vault2Total = vault2FirstClaim + vault2SecondClaim + vault2FinalClaim;
        console.log("\n=== Vault2 Total Rewards ===");
        console.log("Total: %s ETH", vault2Total);
        assertApproxEqRel(vault2Total, 4.5 ether, 1e16, "Vault2 total rewards incorrect");

        // ============ Final State Verification ============
        (,,,,,,,, bool vault1Active) = stakerRewards.vaults(vault1);
        (,,,,,,,, bool vault2Active) = stakerRewards.vaults(vault2);
        (uint256 finalRate, uint256 finalStaked,,) = stakerRewards.globalRewards();

        assertFalse(vault1Active, "Vault1 should be inactive");
        assertFalse(vault2Active, "Vault2 should be inactive");
        assertEq(finalStaked, 0, "Should have no ETH staked");
        assertEq(finalRate, 0, "Average rate should be zero");
        assertEq(stakerRewards.numberOfActiveVaults(), 0, "Should have no active vaults");
    }
}
