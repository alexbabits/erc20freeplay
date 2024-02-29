// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 

import {IEscrow} from "./IEscrow.sol";
import {ErrorsEventsEnums} from "./ErrorsEventsEnums.sol";


import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract ERC20FreePlay is ERC20, Ownable2Step, ErrorsEventsEnums, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    VRFCoordinatorV2Interface COORDINATOR;
    address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625; // Sepolia coordinator address
    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // gas lane, sepolia only has this one
    uint64 subscriptionId;
    
    // We could make this an enum, but makes event emissions harder on client-end? uint8(Status) and then front-end must typecast back to enum/integer?
    // Escrow also needs access to `SUCCESS` variable technically.
    // I think I will do this in the future. (Had some issues with == and != stuff?) @audit
    uint8 private immutable UNINITIALIZED = 0;
    uint8 private immutable OFF = 1;
    uint8 private immutable ON = 2;
    uint8 private immutable SUCCESS = 3;
    uint8 private immutable FAILURE = 4;
    uint8 private immutable CLAIM_IN_PROGRESS = 5; 

    uint256 private keeperFee;
    uint256 private penaltyFee;
    uint256 private immutable PCT_DENOMINATOR = 10000;

    address private escrow; // Escrow contract address 
    address private loot; // Loot contract address

    uint256 private positionId; // global position ID

    mapping(address => UserInfo) private userInfo;
    mapping(uint256 => FreePlayPosition) private freePlayPosition; // Position ID --> Free play position
    mapping(Tier => GlobalTierInfo) public globalTierInfo; // Tier Enum --> Tier Info

    mapping(address => uint8) private normalTransferFlag; // special flag to treat a transfer as normal, even if free play status is enabled
    mapping(address => bool) private claimsInProgress; // If user has any claims in progress
    mapping(uint256 => uint256) private requestIdToPositionId; // required to smuggle in position ID into VRF callback `fulfillRandomWords()`

    struct FreePlayPosition {
        address user; // Owner of the position
        uint256 credits; // free play credits. (This is also the amount of tokens re-directed to Escrow).
        uint256 unlocksAt; // When position unlocks and can be claimed. (based on user's set timelock period)
        uint256 expiresAt; // When position expires and underlying tokens are lost. (based on user's set expiration period)
        uint256 customFailureThreshold; // Incase user needs to have a custom decreased success rate for a position.
        uint256 requestId; // VRF requestId for the position
        uint256 randomWord; // random word for the position
        uint8 claimStatus; // whether there is a claim in progress or not
    }

    struct UserInfo {
        uint256 totalFreePlayCredits; // total free play credits, matured and unmatured.
        uint8 freePlayStatus; // Enabled or disabled
        uint256 timeLockPeriod; // timelock duration for all user's positions
        uint256 expirationPeriod; // expiration duration for all user's positions
        Tier tier; // Users current tier (One through Six).
        uint256 amountDonated; // current total tokens donated from user
    }

    struct GlobalTierInfo {
        uint256 failureThreshold; // Chance of survival of underlying tokens during a claim of free play credits.
        uint256 requiredDonationAmount; // Required tokens donated for that tier.
    }

    constructor(address owner, uint64 _subscriptionId, uint256 initialSupply, address _escrow, address _loot, uint256 _penaltyFee, uint256 _keeperFee) 
        ERC20("FreePlayToken", "FPERC20")
        VRFConsumerBaseV2(vrfCoordinator)
        Ownable(owner)
    {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        subscriptionId = _subscriptionId;
        _mint(owner, initialSupply);
        _setEscrow(_escrow);
        _setLoot(_loot);
        keeperFee = _keeperFee;
        penaltyFee = _penaltyFee;
        globalTierInfo[Tier.One] = GlobalTierInfo(9500, 0);
        globalTierInfo[Tier.Two] = GlobalTierInfo(9800, 50e18);
        globalTierInfo[Tier.Three] = GlobalTierInfo(9900, 200e18);
        globalTierInfo[Tier.Four] = GlobalTierInfo(9950, 500e18);
        globalTierInfo[Tier.Five] = GlobalTierInfo(9980, 1000e18);
        globalTierInfo[Tier.Six] = GlobalTierInfo(9990, 5000e18);
    }

    function toggleFreePlayStatus() external {
        UserInfo storage info = userInfo[msg.sender];

        uint8 oldStatus = info.freePlayStatus;
        uint8 newStatus;

        if (oldStatus == UNINITIALIZED) {
            newStatus = ON;
        } else {
            newStatus = oldStatus == ON ? OFF : ON;
        }

        info.freePlayStatus = newStatus;
        emit ToggledFreePlayStatus(msg.sender, oldStatus, newStatus);
    }

    function initiateClaim(uint256 _positionId) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo memory info = userInfo[position.user];

        if (position.claimStatus == CLAIM_IN_PROGRESS) revert ClaimInProgress();
        if (position.user != msg.sender) revert NotOwnerOfPosition();
        if (position.credits > info.totalFreePlayCredits) revert InsufficientFreePlayCredits();
        if (position.unlocksAt > block.timestamp) revert UnmaturedPosition();

        if (position.expiresAt < block.timestamp) {
            cleanUpExpiredPosition(_positionId);
            return;
        }

        uint256 _requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            3, // requestConfirmations
            40000, // callbackGasLimit
            1 // numWords
        );

        position.requestId = _requestId;
        position.claimStatus = CLAIM_IN_PROGRESS;
        if (claimsInProgress[msg.sender] == false) claimsInProgress[msg.sender] = true;
        requestIdToPositionId[_requestId] = _positionId;

        emit ClaimRequestInitiated(position.user, position.requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 digestedWord = (randomWords[0] % PCT_DENOMINATOR) + 1; // [1, 10000] inclusive
        uint256 _positionId = requestIdToPositionId[requestId];
        FreePlayPosition storage position = freePlayPosition[_positionId];
        position.randomWord = digestedWord;
        emit WordRetrieved(_positionId, requestId, position.randomWord);
    }

    function finalizeClaim(uint256 _positionId) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage info = userInfo[position.user];

        if (position.claimStatus != CLAIM_IN_PROGRESS || position.randomWord == 0) revert InvalidPosition(); 

        Tier userTier = info.tier;

        uint256 failureThreshold = (position.customFailureThreshold != 0) ? position.customFailureThreshold : globalTierInfo[userTier].failureThreshold;
        uint8 result = (position.randomWord < failureThreshold) ? SUCCESS : FAILURE;
        
        // Funds always sent to either `loot` or the user, so we can always delete the position and deduct from user info total balance.
        delete freePlayPosition[_positionId];
        info.totalFreePlayCredits -= position.credits;

        uint256 amountToKeeper = position.credits * keeperFee / PCT_DENOMINATOR;
        uint256 amountToLoot = position.credits - amountToKeeper;

        if (result == SUCCESS) {
            normalTransferFlag[position.user] = ON;
            IEscrow(escrow).transferUnderlyingTokens(position.user, position.credits);
            normalTransferFlag[position.user] = OFF;
        } else {
            IEscrow(escrow).transferUnderlyingTokens(loot, amountToLoot);
            normalTransferFlag[msg.sender] = ON;
            IEscrow(escrow).transferUnderlyingTokens(msg.sender, amountToKeeper);
            normalTransferFlag[msg.sender] = OFF;
        }

        emit Claim(position.user, position.credits, result, position.randomWord, msg.sender);
    }

    /*
    //@audit will add multiple after I get single working with VRF
    function claimMultiplePositions(uint256[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            claimSpecificPosition(ids[i]);
        }
    }
    */

    function donate(uint256 amount) external {
        if (claimsInProgress[msg.sender] == true) revert ClaimInProgress();

        UserInfo storage info = userInfo[msg.sender];

        Tier oldTier = info.tier;
        // If user already at max tier, no need to donate.
        // Note: This doesn't stop user's from over-donating beyond the max tier if they are currently not at the max tier.
        if (oldTier == Tier.Six) revert InvalidTier(); 

        Tier newTier = oldTier; // newTier will be oldTier unless a higher tier is reached through the donation.

        IERC20(address(this)).safeTransferFrom(msg.sender, loot, amount);
        
        uint256 newTotalAmount = info.amountDonated + amount; 

        // Modify tier if necessary
        if (newTotalAmount >= globalTierInfo[Tier.Six].requiredDonationAmount) {
            newTier = Tier.Six;
        } else if (newTotalAmount >= globalTierInfo[Tier.Five].requiredDonationAmount) {
            newTier = Tier.Five;
        } else if (newTotalAmount >= globalTierInfo[Tier.Four].requiredDonationAmount) {
            newTier = Tier.Four;
        } else if (newTotalAmount >= globalTierInfo[Tier.Three].requiredDonationAmount) {
            newTier = Tier.Three;
        } else if (newTotalAmount >= globalTierInfo[Tier.Two].requiredDonationAmount) {
            newTier = Tier.Two;
        }

        // Update user's tier only when necessary (it changes), and always update new donation total.
        if (newTier != oldTier) info.tier = newTier;
        info.amountDonated = newTotalAmount;
        emit Donation(msg.sender, amount, oldTier, newTier);
    }

    function setTimelock(uint256 _timeLockPeriod) external {
        if (_timeLockPeriod > 3650 days) revert InvalidTimePeriod();
        UserInfo storage info = userInfo[msg.sender];
        info.timeLockPeriod = _timeLockPeriod;
        emit TimeLockSet(msg.sender, info.timeLockPeriod);
    }

    function setExpiration(uint256 _expirationPeriod) external {
        if (_expirationPeriod != 0 && (_expirationPeriod < 1 days || _expirationPeriod > 3650 days)) revert InvalidTimePeriod();
        UserInfo storage info = userInfo[msg.sender];
        info.expirationPeriod = _expirationPeriod == 0 ? type(uint256).max : _expirationPeriod;
        emit ExpirationSet(msg.sender, info.expirationPeriod);
    }

    function decreaseFailureThreshold(uint256 id, uint256 newFailureThreshold) external {
        FreePlayPosition storage position = freePlayPosition[id];
        UserInfo memory info = userInfo[position.user];
        if (msg.sender != position.user) revert NotOwnerOfPosition();
        if (position.claimStatus == CLAIM_IN_PROGRESS) revert ClaimInProgress();
        Tier userTier = info.tier;
        uint256 oldFailureThreshold = position.customFailureThreshold != 0 ? position.customFailureThreshold : globalTierInfo[userTier].failureThreshold;
        if (newFailureThreshold == 0 || newFailureThreshold >= oldFailureThreshold) revert InvalidCustomFailureThreshold();
        position.customFailureThreshold = newFailureThreshold;
        emit CustomFailureThresholdChanged(position.user, oldFailureThreshold, newFailureThreshold);
    }

    function emergencyUnlock(uint256 _positionId) external {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage info = userInfo[position.user];
        if (position.user != msg.sender) revert NotOwnerOfPosition();
        if (position.claimStatus == CLAIM_IN_PROGRESS) revert ClaimInProgress();
        uint256 penaltyAmount = position.credits * penaltyFee / PCT_DENOMINATOR;
        position.unlocksAt = block.timestamp;
        info.totalFreePlayCredits -= penaltyAmount;
        position.credits -= penaltyAmount;

        IEscrow(escrow).transferUnderlyingTokens(loot, penaltyAmount);

        emit EmergencyUnlock(position.user, _positionId, penaltyAmount);
    }

    // Allows keepers to clean up expired positions earning a cleanup fee in the process.
    function cleanUpExpiredPosition(uint256 _positionId) public {
        FreePlayPosition storage position = freePlayPosition[_positionId];
        UserInfo storage info = userInfo[position.user];
        if (position.claimStatus == CLAIM_IN_PROGRESS) revert ClaimInProgress();

        uint256 amountToKeeper = position.credits * keeperFee / PCT_DENOMINATOR;
        uint256 amountToLoot = position.credits - amountToKeeper;

        if (block.timestamp > position.expiresAt) {
            info.totalFreePlayCredits -= position.credits;
            IEscrow(escrow).transferUnderlyingTokens(loot, amountToLoot);
            normalTransferFlag[msg.sender] = ON;
            IEscrow(escrow).transferUnderlyingTokens(msg.sender, amountToKeeper);
            normalTransferFlag[msg.sender] = OFF;
            delete freePlayPosition[_positionId];
        }
        emit CleanedUpExpiredPosition(_positionId, position.user, position.credits, msg.sender);
    }

    function cleanUpMultipleExpiredPositions(uint256[] calldata positionIds) external {
        for (uint256 i = 0; i < positionIds.length; i++) {
            cleanUpExpiredPosition(positionIds[i]);
            // There is a more efficient way, we can only toggle the flag once in the beginning, 
            // then once at the end, instead of every time.
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        UserInfo memory info = userInfo[to];

        uint8 recipientStatus = info.freePlayStatus;
        uint8 _normalTransferFlag = normalTransferFlag[to];

        if (recipientStatus != ON || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        if (recipientStatus == ON && _normalTransferFlag == ON) {
            super._update(from, to, value);
            return;
        }

        if (recipientStatus == ON && _normalTransferFlag != ON) {
            super._update(from, escrow, value);
            _createFreePlayPosition(to, value);
        }
    }

    function _createFreePlayPosition(address to, uint256 value) internal {

        UserInfo storage info = userInfo[to];
        uint256 _positionId = positionId++;
        info.totalFreePlayCredits += value;

        FreePlayPosition memory position = FreePlayPosition({
            user: to,
            credits: value, 
            unlocksAt: block.timestamp + info.timeLockPeriod,
            expiresAt: (info.expirationPeriod == type(uint256).max) 
                ? type(uint256).max 
                : block.timestamp + info.timeLockPeriod + info.expirationPeriod,
            customFailureThreshold: 0, // Always 0 for FP positions unless user changes
            requestId: 0,
            randomWord: 0,
            claimStatus: 0
        });

        freePlayPosition[_positionId] = position;

        emit FreePlayPositionCreated(position.user, _positionId, position.credits, position.unlocksAt, position.expiresAt);
    }

    function _setEscrow(address _escrow) internal {
        if (escrow != address(0)) revert AddressAlreadySet();
        escrow = _escrow;
    }

    function _setLoot(address _loot) internal {
        if (loot != address(0)) revert AddressAlreadySet();
        loot = _loot;
    }

    function setKeeperFee(uint256 _keeperFee) external onlyOwner {
        if (_keeperFee >= 10000) revert InvalidFee();
        keeperFee = _keeperFee;
    }

    function setPenaltyFee(uint256 _penaltyFee) external onlyOwner {
        if (_penaltyFee > 10000) revert InvalidFee();
        penaltyFee = _penaltyFee;
    }

    function calculateAmountToNextTier(address user) public view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.tier == Tier.Six) return 0;
        Tier nextTier = Tier(uint256(info.tier) + 1);
        return globalTierInfo[nextTier].requiredDonationAmount - info.amountDonated;
    }

    function calculateAmountToSpecificTier(address user, Tier tier) public view returns (uint256) {
        UserInfo memory info = userInfo[user];
        if (info.tier >= tier || tier > Tier.Six) revert InvalidTier();
        if (info.tier == Tier.Six) return 0;
        return globalTierInfo[tier].requiredDonationAmount - info.amountDonated;
    }

    function getGlobalTierInfo(Tier tier) public view returns (uint256, uint256) {
        return (globalTierInfo[tier].failureThreshold, globalTierInfo[tier].requiredDonationAmount);
    }

    function getUserInfo(address user) public view returns (
        uint256 totalFreePlayCredits,
        uint8 freePlayStatus,
        uint256 timeLockPeriod,
        uint256 expirationPeriod,
        Tier tier,
        uint256 amountDonated
    ) {
        UserInfo memory info = userInfo[user];
        return (
            info.totalFreePlayCredits,
            info.freePlayStatus,
            info.timeLockPeriod,
            info.expirationPeriod,
            info.tier,
            info.amountDonated
        );
    }
}