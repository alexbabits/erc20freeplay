// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {IEscrow} from "./IEscrow.sol";
import {ErrorsEventsEnum} from "./ErrorsEventsEnum.sol";

abstract contract ERC20FreePlay is ERC20, ErrorsEventsEnum {

    using SafeERC20 for IERC20;

    // @audit make these 0-4 enum instead (ask if more or less gas efficient, immutable variables vs enum?)
    uint8 private immutable UNINITIALIZED = 0;
    uint8 private immutable OFF = 1;
    uint8 private immutable ON = 2;

    uint8 private immutable SUCCESS = 3;
    uint8 private immutable FAILURE = 4;

    address private _escrow; // Escrow contract address 
    address private _loot; // Loot contract address
    uint256 private positionId; // global position ID

    mapping(address => UserInfo) private _userInfo;
    mapping(uint256 => FreePlayPosition) private _freePlayPosition; // ID --> Free play position
    mapping(Tier => GlobalTierInfo) public globalTierInfo; // Tier Enum --> Tier Info

    struct FreePlayPosition {
        address user; // Owner of the position
        uint256 credits; // free play credits. (This is also the amount of tokens re-directed to Escrow).
        uint256 unlocksAt; // When position unlocks and can be claimed. (based on user's set timelock period)
        uint256 expiresAt; // When position expires and underlying tokens are lost. (based on user's set expiration period)
        uint256 customFailureThreshold; // Incase user needs to have a custom decreased success rate for a position.
    }

    struct UserInfo {
        uint256 totalFreePlayCredits; // total free play credits, matured and unmatured.
        uint8 freePlayStatus; // Enabled or disabled
        uint256 timeLockPeriod; // timelock duration for all user's positions
        uint256 expirationPeriod; // expiration duration for all user's positions
        uint8 normalTransferFlag; // special flag to treat transfer as normal
        Tier tier; // Users current tier (One through Six).
        uint256 amountDonated; // current total tokens donated from user
    }

    struct GlobalTierInfo {
        uint256 failureThreshold; // Chance of survival of underlying tokens during a claim of free play credits.
        uint256 requiredDonationAmount; // Required tokens donated for that tier.
    }

    function toggleFreePlayStatus() external {
        UserInfo storage userInfo = _userInfo[msg.sender];

        uint8 oldStatus = userInfo.freePlayStatus;
        uint8 newStatus;

        if (oldStatus == UNINITIALIZED) {
            newStatus = ON;
        } else {
            newStatus = oldStatus == ON ? OFF : ON;
        }

        userInfo.freePlayStatus = newStatus;
        emit ToggledFreePlayStatus(msg.sender, oldStatus, newStatus);
    }

    function claimSpecificPosition(uint256 id) public {
        
        FreePlayPosition storage position = _freePlayPosition[id];
        if (msg.sender != position.user) revert NotOwnerOfPosition();
        if (position.credits == 0) revert NoPosition();
        if (block.timestamp < position.unlocksAt) revert UnmaturedPosition();
        if (block.timestamp > position.expiresAt) revert PositionExpired(); // may want to forward this to cleanup to remove position immediately.

        UserInfo storage userInfo = _userInfo[position.user];
        if (userInfo.totalFreePlayCredits == 0) revert NoFreePlayCredits();

        Tier userTier = userInfo.tier;
        userInfo.totalFreePlayCredits -= position.credits;

        // RNG check. Real RNG number will be random from [1, 10,000] inclusive using chainlink VRF or similar.
        uint256 failureThreshold = (position.customFailureThreshold != 0) ? position.customFailureThreshold : globalTierInfo[userTier].failureThreshold;
        uint256 rng = 4200; 
        uint8 result = (rng < failureThreshold) ? SUCCESS : FAILURE;

        // Escrow always transfers funds regardless of RNG outcome. Therefore, we can always delete the position.
        delete _freePlayPosition[id];

        userInfo.normalTransferFlag = ON;
        IEscrow(_escrow).transferUnderlyingTokensBasedOnResult(position.user, position.credits, result);
        userInfo.normalTransferFlag = OFF;
        emit Claim(position.user, position.credits, result, rng);
    }

    function claimMultiplePositions(uint256[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            claimSpecificPosition(ids[i]);
        }
    }

    function donate(uint256 amount) external {

        UserInfo storage userInfo = _userInfo[msg.sender];
        Tier oldTier = userInfo.tier;
        // If user already at max tier, no need to donate.
        // Note: This doesn't stop user's from over-donating beyond the max tier if they are currently not at the max tier.
        if (oldTier == Tier.Six) revert InvalidTier(); 

        Tier newTier = oldTier; // newTier will be oldTier unless a higher tier is reached through the donation.

        IERC20(address(this)).safeTransferFrom(msg.sender, _loot, amount);
        
        uint256 newTotalAmount = userInfo.amountDonated + amount; 

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
        if (newTier != oldTier) userInfo.tier = newTier;
        userInfo.amountDonated = newTotalAmount;
        emit Donation(msg.sender, amount, oldTier, newTier);
    }

    function setTimelock(uint256 _timeLockPeriod) external {
        if (_timeLockPeriod > 3650 days) revert InvalidTimePeriod();
        UserInfo storage userInfo = _userInfo[msg.sender];
        userInfo.timeLockPeriod = _timeLockPeriod;
        emit TimeLockSet(msg.sender, userInfo.timeLockPeriod);
    }

    function setExpiration(uint256 _expirationPeriod) external {
        if (_expirationPeriod != 0 && (_expirationPeriod < 1 days || _expirationPeriod > 3650 days)) revert InvalidTimePeriod();
        UserInfo storage userInfo = _userInfo[msg.sender];
        userInfo.expirationPeriod = _expirationPeriod == 0 ? type(uint256).max : _expirationPeriod;
        emit ExpirationSet(msg.sender, userInfo.expirationPeriod);
    }

    function decreaseFailureThreshold(uint256 id, uint256 newFailureThreshold) external {
        FreePlayPosition storage position = _freePlayPosition[id];
        UserInfo memory userInfo = _userInfo[position.user];
        Tier userTier = userInfo.tier;
        uint256 oldFailureThreshold = position.customFailureThreshold != 0 ? position.customFailureThreshold : globalTierInfo[userTier].failureThreshold;
        if (msg.sender != position.user) revert NotOwnerOfPosition();
        if (newFailureThreshold == 0 || newFailureThreshold >= oldFailureThreshold) revert InvalidCustomFailureThreshold();
        position.customFailureThreshold = newFailureThreshold;
        emit CustomFailureThresholdChanged(position.user, oldFailureThreshold, newFailureThreshold);
    }

    function emergencyUnlock(uint256 id) external {
        FreePlayPosition storage position = _freePlayPosition[id];
        UserInfo storage userInfo = _userInfo[position.user];
        if (msg.sender != position.user) revert NotOwnerOfPosition();
        uint256 penaltyAmount = position.credits / 2;
        position.unlocksAt = block.timestamp;
        userInfo.totalFreePlayCredits -= penaltyAmount;
        position.credits -= penaltyAmount;

        IEscrow(_escrow).transferUnderlyingTokens(_loot, penaltyAmount);

        emit EmergencyUnlock(position.user, id, penaltyAmount);
    }

    // Allows keepers to clean up expired positions earning a cleanup fee in the process.
    function cleanUpExpiredPosition(uint256 id) public {
        FreePlayPosition storage position = _freePlayPosition[id];
        UserInfo storage userInfo = _userInfo[position.user];

        userInfo.totalFreePlayCredits -= position.credits;

        uint256 amountToKeeper = position.credits * 100 / 10000; // 1%
        uint256 amountToLoot = position.credits - amountToKeeper;

        if (block.timestamp > position.expiresAt) {
            IEscrow(_escrow).transferUnderlyingTokens(_loot, amountToLoot);
            userInfo.normalTransferFlag = ON;
            IEscrow(_escrow).transferUnderlyingTokens(msg.sender, amountToKeeper);
            userInfo.normalTransferFlag = OFF;
            delete _freePlayPosition[id];
        }
        emit CleanedUpExpiredPosition(id, position.user, position.credits);
    }

    function cleanUpMultipleExpiredPositions(uint256[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            cleanUpExpiredPosition(ids[i]);
        }
    }

    /**
     * @dev See {ERC20._update}
     * When the recipients free play status is ON, tokens sent through transfers and mints
     * get re-directed to the escrow contract. This address holds the underlying tokens. It has the ability
     * to send the underlying tokens back to the user's when they claim their free play credits. 
     *
     * When the recipient's free play status is not ON, all types of transfers remain unaffected.
     * Also, all burns remain uneffected because the burn address never has free play status ON.
     */
    function _update(address from, address to, uint256 value) internal override {
        UserInfo storage userInfo = _userInfo[to];

        uint8 recipientStatus = userInfo.freePlayStatus;
        uint8 normalTransferFlag = userInfo.normalTransferFlag;

        // Any time the recipients free play status is not enabled or the transfer is a burn, execute `_update()` as normal.
        if (recipientStatus != ON || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Transfers originating from Escrow functions must always be treated as a normal transfer.
        if (recipientStatus == ON && normalTransferFlag == ON) {
            super._update(from, to, value);
            return;
        }

        /**
            Transfer and mints for when user has their status ON, and the call is not flagged as a normal transfer
            Sent tokens are redirected to escrow address and credit users `_freePlayCredits` instead of `_balances`.
            Note: Two events are emitted, one from the `super._update()` for the real underlying transfer, and one for the free play credits update.
         */ 
        if (recipientStatus == ON && normalTransferFlag != ON) {
            super._update(from, _escrow, value);
            _createFreePlayPosition(to, value);
        }
    }

    function _createFreePlayPosition(address to, uint256 value) internal {

        UserInfo storage userInfo = _userInfo[to];
        uint256 id = positionId++;
        userInfo.totalFreePlayCredits += value;

        FreePlayPosition memory position = FreePlayPosition({
            user: to,
            credits: value, 
            unlocksAt: block.timestamp + userInfo.timeLockPeriod,
            expiresAt: (userInfo.expirationPeriod == type(uint256).max) 
                ? type(uint256).max 
                : block.timestamp + userInfo.timeLockPeriod + userInfo.expirationPeriod,
            customFailureThreshold: 0 // Always 0 for FP positions unless user changes
        });

        _freePlayPosition[id] = position;

        emit FreePlayPositionCreated(position.user, id, position.credits, position.unlocksAt, position.expiresAt);
    }

    function _setEscrow(address escrow) internal {
        if (_escrow != address(0)) revert AddressAlreadySet();
        _escrow = escrow;
    }

    function _setLoot(address loot) internal {
        if (_loot != address(0)) revert AddressAlreadySet();
        _loot = loot;
    }

    function calculateAmountToNextTier(address user) public view returns (uint256) {
        UserInfo memory userInfo = _userInfo[user];
        if (userInfo.tier == Tier.Six) return 0;
        Tier nextTier = Tier(uint256(userInfo.tier) + 1);
        return globalTierInfo[nextTier].requiredDonationAmount - userInfo.amountDonated;
    }

    function calculateAmountToSpecificTier(address user, Tier tier) public view returns (uint256) {
        UserInfo memory userInfo = _userInfo[user];
        if (userInfo.tier >= tier || tier > Tier.Six) revert InvalidTier();
        if (userInfo.tier == Tier.Six) return 0;
        return globalTierInfo[tier].requiredDonationAmount - userInfo.amountDonated;
    }

    function getGlobalTierInfo(Tier tier) public view returns (uint256, uint256) {
        return (globalTierInfo[tier].failureThreshold, globalTierInfo[tier].requiredDonationAmount);
    }

    function getUserInfo(address user) public view returns (
        uint256 totalFreePlayCredits,
        uint8 freePlayStatus,
        uint256 timeLockPeriod,
        uint256 expirationPeriod,
        uint8 normalTransferFlag,
        Tier tier,
        uint256 amountDonated
    ) {
        UserInfo memory userInfo = _userInfo[user];
        return (
            userInfo.totalFreePlayCredits,
            userInfo.freePlayStatus,
            userInfo.timeLockPeriod,
            userInfo.expirationPeriod,
            userInfo.normalTransferFlag,
            userInfo.tier,
            userInfo.amountDonated
        );
    }
}