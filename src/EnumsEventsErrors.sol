// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract EnumsEventsErrors {

    enum Tier {ONE, TWO, THREE, FOUR, FIVE, SIX}
    enum State {UNINITIALIZED, OFF, ON, CLAIM_IN_PROGRESS, SUCCESS, FAILURE}

    event ConstructionFinished(address indexed owner);
    event ToggledFreePlayStatus(address indexed user, State indexed oldStatus, State indexed newStatus);
    event ClaimRequestInitiated(address indexed user, uint256 indexed _positionId, uint256 indexed requestId);
    event WordRetrieved(uint256 indexed positionId, uint256 indexed requestId, uint16 indexed randomWord);
    event FinalizeClaim(address indexed owner, uint256 indexed _positionId, State indexed result, uint256 amountClaimed, address caller);
    event Donation(address indexed user, uint256 indexed amount, Tier indexed newTier, Tier oldTier);
    event TimeLockSet(address indexed user, uint64 indexed timeLockPeriod);
    event ExpirationSet(address indexed user, uint64 indexed expirationPeriod);
    event CustomFailureThresholdChanged(address indexed owner, uint256 indexed positionId, uint16 indexed newThreshold, uint16 oldThreshold);
    event EmergencyUnlock(address indexed owner, uint256 indexed id, uint256 indexed penaltyAmount);
    event PositionFixed(address indexed owner, uint256 indexed id);
    event CleanedUpExpiredPosition(uint256 indexed id, address indexed owner, uint256 indexed amount, address caller);
    event FreePlayPositionCreated(address indexed owner, uint256 indexed id, uint256 indexed amount, Tier claimTier, uint64 unlocksAt, uint64 expiresAt);
    event KeeperRewardSet(uint256 indexed keeperReward);
    event PenaltyFeeSet(uint256 indexed penaltyFee);
    event MaxTimeLockPeriodSet(uint64 indexed maxTimelockPeriod);
    event MaxExpirationPeriodSet(uint64 indexed maxExpirationPeriod);
    event GlobalTierInfoSet(address indexed owner);
    event CallbackGasLimitChanged(uint32 indexed newCallbackGasLimit);
    event RequestConfirmationsChanged(uint16 indexed newRequestConfirmations);
    event SubscriptionIdChanged(uint64 indexed newSubscriptionId);
    event EscrowSet(address indexed escrowAddress);
    event LootSet(address indexed lootAddress);
    event TransmuterSet(address indexed transmuterAddress);
    event KeyHashSet(bytes32 indexed keyHash);
    event AddressSet(address indexed _address);
    event LootWithdrawal(uint256 indexed amount, address indexed to);

    error ClaimInProgress();
    error NotOwnerOfPosition(address caller, address owner);
    error InsufficientFreePlayCredits(uint256 amount);
    error UnmaturedPosition(uint256 currentTime, uint64 unlocksAt);
    error InvalidPositionState();
    error InvalidTier();
    error InvalidTimePeriod();
    error InvalidCustomFailureThreshold();
    error PositionAlreadyMatured(uint64 unlocksAt, uint256 currentTime);
    error PositionNotExpired(uint64 expiredAt, uint256 currentTime);
    error InvalidKeeperReward();
    error InvalidFee();
    error InvalidGasLimit();
    error InvalidRequestConfirmations();
    error LengthProblem();
    error AddressAlreadySet(address _address);
    error NotWhitelistedCaller(address caller);
    error ZeroAddress();
    error ZeroKeyHash();
    error MustBeZero();
}