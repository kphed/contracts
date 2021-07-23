pragma solidity ^0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/SafeERC20.sol";
import "synthetix-2.43.1/contracts/SafeDecimalMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "synthetix-2.43.1/contracts/Pausable.sol";

import "./interfaces/IEscrowThales.sol";

contract StakingThales is IERC20, IEscrowThales, Owned, ReentrancyGuard, Pausable {
    /* ========== LIBRARIES ========== */

    using SafeMath for uint;
    using SafeDecimalMath for uint;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IEscrowThales public escrowToken;
    IERC20 public stakingToken;
    IERC20 public feeToken;

    uint public weeksOfStaking = 0;
    uint public lastPeriod = 0;
    uint public durationPeriod = 7 days;
    uint public startTime = 0;
    uint public rewardsForLastWeek = 0;
    uint public rewardFeesForLastWeek = 0;

    mapping(address => uint) public stakerRewardsClaimed;
    mapping(address => uint) public stakerFeesClaimed;

    uint private _totalStakedAmount;
    uint private _totalUnclaimedRewards;
    uint private _totalUnlcaimedFees;
    uint private _totalRewardsClaimed;
    uint private _totalRewardFeesClaimed;
    mapping(address => uint) private _stakedBalances;
    mapping(address => uint) private _lastStakingWeek;
    mapping(address => uint) private _lastRewardsClaimedWeek;
    mapping(address => uint) private _lastUnstakeTime;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        address _escrowToken, //THALES
        address _stakingToken, //THALES
        address _feeToken //sUSD
    ) public Owned(_owner) {
        escrowToken = IEscrowThales(_escrowToken);
        stakingToken = IERC20(_stakingToken);
        feeToken = IERC20(_feeToken);
    }

    /* ========== VIEWS ========== */

    function totalStakedAmount() external view returns (uint) {
        return _totalStakedAmount;
    }

    function stakedBalanceOf(address account) external view returns (uint) {
        return _stakedBalances[account];
    }

    function getRewardsAvailable(address account) external view returns (uint) {
        return calculateUnclaimedRewards(account);
    }

    function getRewardFeesAvailable(address account) external view returns (uint) {
        return calculateUnclaimedFees(account);
    }

    function getAlreadyClaimedRewards(address account) external view returns (uint) {
        return stakerRewardsClaimed[account];
    }

    function getAlreadyClaimedFees(address account) external view returns (uint) {
        return stakerFeesClaimed[account];
    }

    /* ========== PUBLIC ========== */

    function startStakingPeriod() external onlyOwner {
        require(startTime == 0, "Staking has already started");
        startTime = block.timestamp;
        weeksOfStaking = 0;
        lastPeriod = startTime;
        _totalUnclaimedRewards = 0;
        _totalUnlcaimedFees = 0;
        _totalRewardsClaimed = 0;
        _totalRewardFeesClaimed = 0;
        _totalStakedAmount = 0;
        durationPeriod = 7 days;
    }

    function closePeriod() external nonReentrant notPaused {
        require(startTime > 0, "Staking period has not started");
        require(block.timestamp >= lastPeriod.add(durationPeriod), "7 days has not passed since the last closed period");

        require(escrowToken.updateCurrentWeek(weeksOfStaking.add(1)), "Error in EscrowToken: check address of StakingToken");
                
        lastPeriod = block.timestamp;
        weeksOfStaking = weeksOfStaking.add(1);
        //Actions taken on every closed period
        rewardsForLastWeek = calculateRewardsForWeek(weeksOfStaking);
        rewardFeesForLastWeek = calculateFeesForWeek(weeksOfStaking);

        _totalUnclaimedRewards = _totalUnclaimedRewards.add(rewardsForLastWeek);
        _totalUnlcaimedFees = _totalUnlcaimedFees.add(rewardFeesForLastWeek);

        emit ClosedPeriod(weeksOfStaking, lastPeriod);
    }

    function stake(uint amount) external nonReentrant notPaused {
        require(startTime > 0, "Staking period has not started");
        require(amount > 0, "Cannot stake 0");
        require(
            _lastUnstakeTime[msg.sender] < block.timestamp.sub(7 days),
            "Cannot stake, the staker is paused from staking due to unstaking"
        );
        // Check if there are not claimable rewards from last week.
        // Claim them, and add new stake
        if (_lastRewardsClaimedWeek[msg.sender] < weeksOfStaking) {
            claimReward();
        }
        _totalStakedAmount = _totalStakedAmount.add(amount);
        _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(amount);
        _lastStakingWeek[msg.sender] = weeksOfStaking;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function startUnstake() external {
        require(msg.sender != address(0), "Invalid address");
        require(_lastUnstakeTime[msg.sender] < block.timestamp.sub(7 days), "Already initiated unstaking cooldown");
        _lastUnstakeTime[msg.sender] = block.timestamp;
        emit UnstakeCooldown(msg.sender, _lastUnstakeTime[msg.sender].add(7 days));
    }

    function unstake() external {
        require(msg.sender != address(0), "Invalid address");
        require(
            _lastUnstakeTime[msg.sender] < block.timestamp.sub(7 days),
            "Cannot stake, the staker is paused from staking due to unstaking"
        );

        _lastUnstakeTime[msg.sender] = block.timestamp;
        claimReward();
        _totalStakedAmount = _totalStakedAmount.sub(_stakedBalances[msg.sender]);
        uint unstakeAmount = _stakedBalances[msg.sender];
        _stakedBalances[msg.sender] = 0;
        stakingToken.transfer(msg.sender, unstakeAmount);
        emit Unstaked(msg.sender, unstakeAmount);
    }

    function claimReward() public nonReentrant notPaused {
        require(startTime > 0, "Staking period has not started");

        //Calculate rewards
        uint unclaimedReward = calculateUnclaimedRewards(msg.sender);
        uint unclaimedFees = calculateUnclaimedFees(msg.sender);

        if (unclaimedFees > 0) {
            feeToken.transferFrom(address(this), msg.sender, unclaimedFees);
            stakerFeesClaimed[msg.sender] = stakerFeesClaimed[msg.sender].add(unclaimedFees);
            _totalRewardFeesClaimed = _totalRewardFeesClaimed.add(unclaimedFees);
            _totalUnlcaimedFees = _totalUnlcaimedFees.sub(unclaimedFees);
            emit FeeRewardsClaimed(msg.sender, unclaimedFees);
        }
        if (unclaimedReward > 0) {
            // Stake the newly claimed reward:
            _totalStakedAmount = _totalStakedAmount.add(unclaimedReward).add(unclaimedFees);
            // Both the rewards and the fees are staked => new_stake(reward + fees)
            _stakedBalances[msg.sender] = _stakedBalances[msg.sender].add(unclaimedReward).add(unclaimedFees);
            _lastStakingWeek[msg.sender] = weeksOfStaking;
            // Transfer to Escrow contract
            escrowToken.addToEscrow(msg.sender, unclaimedReward);
            // Record the total claimed rewards
            stakerRewardsClaimed[msg.sender] = stakerRewardsClaimed[msg.sender].add(unclaimedReward);
            _totalRewardsClaimed = _totalRewardsClaimed.add(unclaimedReward);
            _totalUnclaimedRewards = _totalUnclaimedRewards.sub(unclaimedReward);
            emit RewardsClaimed(msg.sender, unclaimedReward);
        }
        // Update last claiming week
        _lastRewardsClaimedWeek[msg.sender] = weeksOfStaking;
    }

    function selfDestruct(address payable account) external onlyOwner {
        selfdestruct(account);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function calculateUnclaimedRewards(address account) internal view returns (uint) {
        require(account != address(0), "Invalid account address used");
        require(_stakedBalances[account] > 0, "Account is not a staker");
        require(_lastRewardsClaimedWeek[account] < weeksOfStaking, "Rewards already claimed for last week");

        // return _stakedBalances[account].div(1e18).div(_totalStakedAmount).mul(rewardsForLastWeek);
        return _stakedBalances[account].div(_totalStakedAmount).mul(rewardsForLastWeek);
    }

    function calculateUnclaimedFees(address account) internal view returns (uint) {
        require(account != address(0), "Invalid account address used");
        require(_stakedBalances[account] > 0, "Account is not a staker");
        require(_lastRewardsClaimedWeek[account] < weeksOfStaking, "Rewards already claimed for last week");

        // return _stakedBalances[account].div(1e18).div(_totalStakedAmount).mul(rewardFeesForLastWeek);
        return _stakedBalances[account].div(_totalStakedAmount).mul(rewardFeesForLastWeek);
    }

    function calculateRewardsForWeek(uint week) internal pure returns (uint) {
        //ADD formula
        require(week > 0, "Invalid number for week");
        if(week == 1) {
            return 70000;
        }
        if(week > 1 && week < 48) {
            return week.sub(1).mul(2000).add(70000);
        }
        else {
            return 140000;
        }
        
    }

    function calculateFeesForWeek(uint week) internal pure returns (uint) {
        //ADD formula
        return 0;
    }


    /* ========== EVENTS ========== */

    event RewardAdded(uint reward);
    event Staked(address user, uint amount);
    event ClosedPeriod(uint WeekOfStaking, uint lastPeriod);
    event RewardsClaimed(address account, uint unclaimedReward);
    event FeeRewardsClaimed(address account, uint unclaimedFees);
    event UnstakeCooldown(address account, uint cooldownTime);
    event Unstaked(address account, uint unstakeAmount);
}
