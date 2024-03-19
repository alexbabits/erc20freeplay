// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {IEscrow} from "./IEscrow.sol";
import {EnumsEventsErrors} from "./EnumsEventsErrors.sol";

import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";

abstract contract ERC20FreePlay is ERC20, ERC20Burnable, Ownable2Step, EnumsEventsErrors, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    VRFCoordinatorV2Interface COORDINATOR; // VRF interface
    bytes32 public keyHash; // VRF gas lane option
    uint64 public subscriptionId; // VRF subscription ID
    uint32 public callbackGasLimit; // VRF gas limit for `fulfillRandomWords()` callback execution.
    uint16 public requestConfirmations; // VRF number of block confirmations to prevent re-orgs.

    address public escrow; // Escrow contract address
    address public loot; // Loot contract address
    address public transmuter; // transmuter contract address

    uint256 public positionId; // global position ID counter
    uint256 public keeperReward;
    uint256 public penaltyFee; 
    uint64 public maxTimelockPeriod;
    uint64 public maxExpirationPeriod;

    State public finishedDeploymentFlag;

    uint256 public immutable PCT_DENOMINATOR = 10000; // 100%
    uint64 public immutable STUCK_POSITION_TIME_THRESHOLD = 93600; // 26 hours

    mapping(address => UserInfo) public userInfo; // Users "global" info
    mapping(uint256 => FreePlayPosition) public freePlayPosition; // Position ID --> Free play position
    mapping(Tier => GlobalTierInfo) public globalTierInfo; // Tier Enum --> Global tier info

    mapping(address => State) public normalTransferFlag; // Flag to treat a transfer as normal, even if free play status is enabled
    mapping(uint256 => uint256) public requestIdToPositionId; // Uses requestID to smuggle position ID into VRF callback `fulfillRandomWords()`

    struct FreePlayPosition {
        uint256 credits; // free play credits. (This is also the amount of tokens re-directed to Escrow).
        uint256 requestId; // VRF requestId for the position
        address owner; // Owner of the position
        uint64 requestedAt; // When `requestRandomWords()` was called for the position via `initiateClaim()`.
        uint64 unlocksAt; // When position unlocks and can be claimed. (based on user's set timelock period)
        uint64 expiresAt; // When position expires and underlying tokens are lost. (based on user's set expiration period)
        uint16 customFailureThreshold; // Incase user needs to have a custom decreased success rate for a position.
        uint16 randomWord; // random word for the position after a VRF request
        State claimStatus; // whether there is a claim in progress for this particular position
        Tier claimTier; // Tier when the position was created.
    }

    struct UserInfo {
        uint256 totalFreePlayCredits; // total free play credits, matured, unmatured, and expired (until keeper bot cleans up position).
        uint256 amountDonated; // current total tokens donated from user
        uint64 timeLockPeriod; // timelock duration for all user's positions
        uint64 expirationPeriod; // expiration duration for all user's positions
        State freePlayStatus; // Enabled or disabled
        Tier tier; // Users current tier (One through Six).
    }

    struct GlobalTierInfo {
        uint256 requiredDonationAmount; // Required tokens donated for that tier.
        uint16 failureThreshold; // Chance of survival of underlying tokens during a claim of free play credits.
    }

    function constructorPartTwo(
        uint256 _keeperReward, 
        uint256 _penaltyFee, 
        uint64 _maxTimelockPeriod, 
        uint64 _maxExpirationPeriod,
        uint256[] memory requiredDonationAmounts,
        uint16[] memory failureThresholds
    ) external onlyOwner {
        if (finishedDeploymentFlag != State.UNINITIALIZED) revert MustBeZero();
        _setKeeperReward(_keeperReward);
        _setPenaltyFee(_penaltyFee);
        _setMaxTimelockPeriod(_maxTimelockPeriod);
        _setMaxExpirationPeriod(_maxExpirationPeriod);
        _setGlobalTierInfo(requiredDonationAmounts, failureThresholds);
        finishedDeploymentFlag = State.SUCCESS;
        emit ConstructionFinished(msg.sender);
    }

    function toggleFreePlayStatus() external {
        UserInfo storage info = userInfo[msg.sender];
        State oldStatus = info.freePlayStatus;
        State newStatus = (oldStatus == State.UNINITIALIZED) ? State.ON : ((oldStatus == State.ON) ? State.OFF : State.ON);
        info.freePlayStatus = newStatus;
        emit ToggledFreePlayStatus(msg.sender, oldStatus, newStatus);
    }

    // `extraArgs` needed for Chainlink VRF v2.5
    function initiateClaim(uint256 _positionId /*, bytes calldata extraArgs */) public {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo memory info = userInfo[position.owner];
        if (position.expiresAt < block.timestamp) {
            cleanUpExpiredPosition(_positionId, false);
            return;
        }
        if (position.claimStatus == State.CLAIM_IN_PROGRESS) revert ClaimInProgress();
        if (position.owner != msg.sender) revert NotOwnerOfPosition(msg.sender, position.owner);
        if (position.credits > info.totalFreePlayCredits) revert InsufficientFreePlayCredits(info.totalFreePlayCredits);
        if (position.unlocksAt > block.timestamp) revert UnmaturedPosition(block.timestamp, position.unlocksAt);

        uint256 _requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1 // numWords
            //`extraArgs` needed for v2.5
        );

        position.requestId = _requestId;
        position.claimStatus = State.CLAIM_IN_PROGRESS;
        position.requestedAt = uint64(block.timestamp);
        requestIdToPositionId[_requestId] = _positionId;

        emit ClaimRequestInitiated(position.owner, _positionId, position.requestId);
    }

    function initiateMultipleClaims(uint256[] calldata positionIds) external {
        for (uint256 i = 0; i < positionIds.length; i++) {
            initiateClaim(positionIds[i]);
        }
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint16 digestedWord = uint16((randomWords[0] % PCT_DENOMINATOR) + 1); // [1, 10000] inclusive
        uint256 _positionId = requestIdToPositionId[requestId];
        FreePlayPosition storage position = freePlayPosition[_positionId];
        position.randomWord = digestedWord;
        emit WordRetrieved(_positionId, requestId, position.randomWord);
    }

    function finalizeClaim(uint256 _positionId, bool isBatch) public {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage ownerInfo = userInfo[position.owner];

        if (position.claimStatus != State.CLAIM_IN_PROGRESS || position.randomWord == 0) revert InvalidPositionState(); 

        Tier userTier = position.claimTier;
        address positionOwner = position.owner;
        uint256 totalPositionCredits = position.credits;

        uint16 failureThreshold = (position.customFailureThreshold != 0) ? position.customFailureThreshold : globalTierInfo[userTier].failureThreshold;
        State result = (position.randomWord <= failureThreshold) ? State.SUCCESS : State.FAILURE;
        
        uint256 amountToKeeper = totalPositionCredits * keeperReward / PCT_DENOMINATOR;
        uint256 amountToLoot = totalPositionCredits - amountToKeeper;

        ownerInfo.totalFreePlayCredits -= totalPositionCredits;
        delete freePlayPosition[_positionId];

        result == State.SUCCESS 
            ? _distributeTokensToOwner(positionOwner, totalPositionCredits)
            : _distributeTokensToLootAndKeeper(isBatch, amountToLoot, amountToKeeper);

        emit FinalizeClaim(positionOwner, _positionId, result, totalPositionCredits, msg.sender);
    }

    function finalizeMultipleClaims(uint256[] calldata positionIds) external {
        UserInfo memory callerInfo = userInfo[msg.sender];
        if (callerInfo.freePlayStatus != State.ON) {
            for (uint256 i = 0; i < positionIds.length; i++) {
                finalizeClaim(positionIds[i], true);
            }
        } else {
            normalTransferFlag[msg.sender] = State.ON;
            for (uint256 i = 0; i < positionIds.length; i++) {
                finalizeClaim(positionIds[i], true);
            }
            normalTransferFlag[msg.sender] = State.OFF;
        }
    }

    function donate(uint256 amount) external {
        UserInfo storage callerInfo = userInfo[msg.sender];
        Tier oldTier = callerInfo.tier;
        if (oldTier == Tier.SIX) revert InvalidTier(); 
        Tier newTier = oldTier; 

        IERC20(address(this)).safeTransferFrom(msg.sender, loot, amount);
        uint256 newTotalAmount = callerInfo.amountDonated + amount; 

        if (newTotalAmount >= globalTierInfo[Tier.SIX].requiredDonationAmount) {
            newTier = Tier.SIX;
        } else if (newTotalAmount >= globalTierInfo[Tier.FIVE].requiredDonationAmount) {
            newTier = Tier.FIVE;
        } else if (newTotalAmount >= globalTierInfo[Tier.FOUR].requiredDonationAmount) {
            newTier = Tier.FOUR;
        } else if (newTotalAmount >= globalTierInfo[Tier.THREE].requiredDonationAmount) {
            newTier = Tier.THREE;
        } else if (newTotalAmount >= globalTierInfo[Tier.TWO].requiredDonationAmount) {
            newTier = Tier.TWO;
        }

        if (newTier != oldTier) callerInfo.tier = newTier;
        callerInfo.amountDonated = newTotalAmount;
        emit Donation(msg.sender, amount, newTier, oldTier);
    }

    function setTimelock(uint64 _timeLockPeriod) external {
        if (_timeLockPeriod > maxTimelockPeriod) revert InvalidTimePeriod();
        UserInfo storage info = userInfo[msg.sender];
        info.timeLockPeriod = _timeLockPeriod;
        emit TimeLockSet(msg.sender, info.timeLockPeriod);
    }

    function setExpiration(uint64 _expirationPeriod) external {
        if (_expirationPeriod > maxExpirationPeriod) revert InvalidTimePeriod();
        UserInfo storage info = userInfo[msg.sender];
        info.expirationPeriod = _expirationPeriod;
        emit ExpirationSet(msg.sender, info.expirationPeriod);
    }

    function decreaseFailureThreshold(uint256 _positionId, uint16 newFailureThreshold) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        if (position.owner != msg.sender) revert NotOwnerOfPosition(msg.sender, position.owner);
        if (position.claimStatus == State.CLAIM_IN_PROGRESS) revert ClaimInProgress();
        Tier userTier = position.claimTier;
        uint16 oldFailureThreshold = position.customFailureThreshold == 0 
            ? globalTierInfo[userTier].failureThreshold 
            : position.customFailureThreshold;
        if (newFailureThreshold == 0 || newFailureThreshold >= oldFailureThreshold) revert InvalidCustomFailureThreshold();
        position.customFailureThreshold = newFailureThreshold;
        emit CustomFailureThresholdChanged(position.owner, _positionId, newFailureThreshold, oldFailureThreshold);
    }

    function emergencyUnlock(uint256 _positionId) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage info = userInfo[position.owner];
        if (position.owner != msg.sender) revert NotOwnerOfPosition(msg.sender, position.owner);
        if (position.claimStatus == State.CLAIM_IN_PROGRESS) revert ClaimInProgress();
        if (position.unlocksAt <= block.timestamp) revert PositionAlreadyMatured(position.unlocksAt, block.timestamp);

        uint256 penaltyAmount = position.credits * penaltyFee / PCT_DENOMINATOR;
        position.unlocksAt = uint64(block.timestamp); 
        if (position.expiresAt != type(uint64).max) position.expiresAt = type(uint64).max;
        info.totalFreePlayCredits -= penaltyAmount;
        position.credits -= penaltyAmount;
        IEscrow(escrow).transferUnderlyingTokens(loot, penaltyAmount);
        emit EmergencyUnlock(position.owner, _positionId, penaltyAmount);
    }

    function fixFailedRequestPosition(uint256 _positionId) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        if (position.owner != msg.sender) revert NotOwnerOfPosition(msg.sender, position.owner);
        if (position.claimStatus != State.CLAIM_IN_PROGRESS || position.randomWord != 0) revert InvalidPositionState();
        if (position.requestedAt + STUCK_POSITION_TIME_THRESHOLD > block.timestamp ) revert InvalidPositionState();

        if (position.expiresAt != type(uint64).max) position.expiresAt += STUCK_POSITION_TIME_THRESHOLD;
        position.claimStatus = State.UNINITIALIZED;
        emit PositionFixed(msg.sender, _positionId);
    }

    function cleanUpExpiredPosition(uint256 _positionId, bool isBatch) public {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage ownerInfo = userInfo[position.owner];
        if (position.claimStatus == State.CLAIM_IN_PROGRESS) revert ClaimInProgress();
        if (position.expiresAt >= block.timestamp) revert PositionNotExpired(position.expiresAt, block.timestamp);
        address positionOwner = position.owner;
        uint256 totalPositionCredits = position.credits;
        uint256 amountToKeeper = totalPositionCredits * keeperReward / PCT_DENOMINATOR;
        uint256 amountToLoot = totalPositionCredits - amountToKeeper;

        ownerInfo.totalFreePlayCredits -= totalPositionCredits;
        delete freePlayPosition[_positionId];
        _distributeTokensToLootAndKeeper(isBatch, amountToLoot, amountToKeeper);
        emit CleanedUpExpiredPosition(_positionId, positionOwner, totalPositionCredits, msg.sender);
    }

    function cleanUpMultipleExpiredPositions(uint256[] calldata positionIds) external {
        UserInfo memory callerInfo = userInfo[msg.sender];
        if (callerInfo.freePlayStatus != State.ON) {
            for (uint256 i = 0; i < positionIds.length; i++) {
                cleanUpExpiredPosition(positionIds[i], true);
            }
        } else {
            normalTransferFlag[msg.sender] = State.ON;
            for (uint256 i = 0; i < positionIds.length; i++) {
                cleanUpExpiredPosition(positionIds[i], true);
            }
            normalTransferFlag[msg.sender] = State.OFF;
        }
    }

    function _distributeTokensToLootAndKeeper(bool isBatch, uint256 amountToLoot, uint256 amountToKeeper) internal {
        UserInfo memory callerInfo = userInfo[msg.sender];
        IEscrow(escrow).transferUnderlyingTokens(loot, amountToLoot);
        if (isBatch || callerInfo.freePlayStatus != State.ON) {
            IEscrow(escrow).transferUnderlyingTokens(msg.sender, amountToKeeper);
        } else {
            normalTransferFlag[msg.sender] = State.ON;
            IEscrow(escrow).transferUnderlyingTokens(msg.sender, amountToKeeper);
            normalTransferFlag[msg.sender] = State.OFF;
        }
    }

    function _distributeTokensToOwner(address owner, uint256 amount) internal {
        UserInfo memory ownerInfo = userInfo[owner];
        if (ownerInfo.freePlayStatus != State.ON) {
            IEscrow(escrow).transferUnderlyingTokens(owner, amount);
        } else {
            normalTransferFlag[owner] = State.ON;
            IEscrow(escrow).transferUnderlyingTokens(owner, amount);
            normalTransferFlag[owner] = State.OFF;
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        UserInfo memory recipientInfo = userInfo[to];

        State recipientFreePlayStatus = recipientInfo.freePlayStatus;
        State _normalTransferFlag = normalTransferFlag[to];

        if (recipientFreePlayStatus != State.ON || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        if (recipientFreePlayStatus == State.ON && _normalTransferFlag == State.ON) {
            super._update(from, to, value);
            return;
        }

        if (recipientFreePlayStatus == State.ON && _normalTransferFlag != State.ON) {
            super._update(from, escrow, value);
            _createFreePlayPosition(to, value);
        }
    }

    function _createFreePlayPosition(address to, uint256 value) internal {
        UserInfo storage info = userInfo[to];
        uint256 _positionId = ++positionId;
        info.totalFreePlayCredits += value;

        FreePlayPosition memory position = FreePlayPosition({
            credits: value, 
            requestId: 0,
            owner: to,
            requestedAt: 0,
            unlocksAt: uint64(block.timestamp) + info.timeLockPeriod,
            expiresAt: (info.expirationPeriod == 0) ? type(uint64).max : uint64(block.timestamp) + info.timeLockPeriod + info.expirationPeriod,
            customFailureThreshold: 0,
            randomWord: 0,
            claimStatus: State.UNINITIALIZED,
            claimTier: info.tier
        });

        freePlayPosition[_positionId] = position;

        emit FreePlayPositionCreated(position.owner, _positionId, position.credits, position.claimTier, position.unlocksAt, position.expiresAt);
    }

    function _setKeeperReward(uint256 _keeperReward) internal onlyOwner {
        if (keeperReward != 0) revert MustBeZero();
        if (_keeperReward >= PCT_DENOMINATOR) revert InvalidKeeperReward();
        keeperReward = _keeperReward;
        emit KeeperRewardSet(_keeperReward);
    }

    function _setPenaltyFee(uint256 _penaltyFee) internal onlyOwner {
        if (penaltyFee != 0) revert MustBeZero();
        if (_penaltyFee > PCT_DENOMINATOR) revert InvalidFee();
        penaltyFee = _penaltyFee;
        emit PenaltyFeeSet(_penaltyFee);
    }

    function _setMaxTimelockPeriod(uint64 _maxTimelockPeriod) internal onlyOwner {
        if (maxTimelockPeriod != 0) revert MustBeZero();
        maxTimelockPeriod = _maxTimelockPeriod;
        emit MaxTimeLockPeriodSet(_maxTimelockPeriod);
    }

    function _setMaxExpirationPeriod(uint64 _maxExpirationPeriod) internal onlyOwner {
        if (maxExpirationPeriod != 0) revert MustBeZero();
        maxExpirationPeriod = _maxExpirationPeriod;
        emit MaxExpirationPeriodSet(_maxExpirationPeriod);
    }  

    function _setGlobalTierInfo(uint256[] memory requiredDonationAmounts, uint16[] memory failureThresholds) internal onlyOwner {
        if (requiredDonationAmounts.length != failureThresholds.length) revert LengthProblem();
        if (requiredDonationAmounts.length != 6) revert LengthProblem();
        globalTierInfo[Tier.ONE] = GlobalTierInfo(requiredDonationAmounts[0], failureThresholds[0]);
        globalTierInfo[Tier.TWO] = GlobalTierInfo(requiredDonationAmounts[1], failureThresholds[1]);
        globalTierInfo[Tier.THREE] = GlobalTierInfo(requiredDonationAmounts[2], failureThresholds[2]);
        globalTierInfo[Tier.FOUR] = GlobalTierInfo(requiredDonationAmounts[3], failureThresholds[3]);
        globalTierInfo[Tier.FIVE] = GlobalTierInfo(requiredDonationAmounts[4], failureThresholds[4]);
        globalTierInfo[Tier.SIX] = GlobalTierInfo(requiredDonationAmounts[5], failureThresholds[5]);
        emit GlobalTierInfoSet(msg.sender);
    } 

    function setSubscriptionId(uint64 _subscriptionId) public onlyOwner {
        subscriptionId = _subscriptionId;
        emit SubscriptionIdChanged(_subscriptionId);
    }

    function setKeyHash(bytes32 _keyHash) public onlyOwner {
        if (_keyHash == bytes32(0)) revert ZeroKeyHash();
        keyHash = _keyHash;
        emit KeyHashSet(_keyHash);
    }

    function setCallbackGasLimit(uint32 _callbackGasLimit) public onlyOwner {
        if (_callbackGasLimit > 2_500_000 || _callbackGasLimit < 40000) revert InvalidGasLimit();
        callbackGasLimit = _callbackGasLimit;
        emit CallbackGasLimitChanged(_callbackGasLimit);
    }

    function setRequestConfirmations(uint16 _requestConfirmations) public onlyOwner {
        if (_requestConfirmations < 3 || _requestConfirmations > 200) revert InvalidRequestConfirmations();
        requestConfirmations = _requestConfirmations;
        emit RequestConfirmationsChanged(_requestConfirmations);
    }

    function _setEscrow(address _escrow) internal {
        if (escrow != address(0)) revert AddressAlreadySet(escrow);
        escrow = _escrow;
        emit EscrowSet(_escrow);
    }

    function _setLoot(address _loot) internal {
        if (loot != address(0)) revert AddressAlreadySet(loot);
        loot = _loot;
        emit LootSet(_loot);
    }

    function setTransmuterAddress(address _transmuter) external onlyOwner {
        if (transmuter != address(0)) revert AddressAlreadySet(transmuter);
        transmuter = _transmuter;
        emit TransmuterSet(_transmuter);
    }

    function getGlobalTierInfo(Tier tier) external view returns (uint256, uint16) {
        return (globalTierInfo[tier].requiredDonationAmount, globalTierInfo[tier].failureThreshold);
    }

    function getAmountToNextTier(address user) external view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.tier == Tier.SIX) return 0;
        Tier nextTier = Tier(uint256(info.tier) + 1);
        uint256 amountToNextTier = globalTierInfo[nextTier].requiredDonationAmount - info.amountDonated;
        return amountToNextTier;
    }

    function getAmountToSpecificTier(address user, Tier _tier) external view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.tier == Tier.SIX) return 0;
        if (info.tier >= _tier || _tier > Tier.SIX) revert InvalidTier();
        uint256 amountToSpecificTier = globalTierInfo[_tier].requiredDonationAmount - info.amountDonated;
        return amountToSpecificTier;
    }

    function getUserInfo(address user) external view returns (
        uint256 totalFreePlayCredits,
        uint256 amountDonated,
        uint64 timeLockPeriod,
        uint64 expirationPeriod,
        State freePlayStatus,
        Tier tier
    ) {
        UserInfo memory info = userInfo[user];
        return (
            info.totalFreePlayCredits, 
            info.amountDonated, 
            info.timeLockPeriod, 
            info.expirationPeriod, 
            info.freePlayStatus, 
            info.tier
        );
    }

    function getFreePlayPosition(uint256 _positionId) external view returns (
        uint256 credits,
        uint256 requestId,
        address owner,
        uint64 requestedAt,
        uint64 unlocksAt,
        uint64 expiresAt,
        uint16 customFailureThreshold,
        uint16 randomWord,
        State claimStatus,
        Tier claimTier
    ) {
        FreePlayPosition memory position = freePlayPosition[_positionId];
        return (
            position.credits,
            position.requestId,
            position.owner,
            position.requestedAt,
            position.unlocksAt,
            position.expiresAt,
            position.customFailureThreshold,
            position.randomWord,
            position.claimStatus,
            position.claimTier
        );
    }
}