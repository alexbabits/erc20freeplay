// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract ErrorsEventsEnums {

    error NoFreePlayCredits();
    error InvalidTimePeriod();
    error AddressAlreadySet();
    error InvalidTier();
    error UnmaturedPosition();
    error PositionExpired();
    error NotOwnerOfPosition();
    error InvalidCustomFailureThreshold();
    error NotFreePlayToken();
    error ZeroAddress();
    error ClaimInProgress();
    error InvalidUserStatus();
    error InsufficientFreePlayCredits();
    error InvalidPosition();
    error InvalidFee();

    event Claim(address indexed claimer, uint256 indexed amountClaimed, uint8 indexed result, uint256 rng, address caller);
    event ToggledFreePlayStatus(address indexed user, uint8 indexed oldStatus, uint8 indexed newStatus);
    event FreePlayPositionCreated(address indexed user, uint256 indexed id, uint256 indexed amount, uint256 unlocksAt, uint256 expiresAt);
    event Donation(address indexed user, uint256 indexed amount, Tier oldTier, Tier newTier);
    event TimeLockSet(address indexed user, uint256 indexed timeLockPeriod);
    event ExpirationSet(address indexed user, uint256 indexed expirationPeriod);
    event CustomFailureThresholdChanged(address indexed user, uint256 indexed oldFailureThreshold, uint256 indexed newFailureThreshold);
    event EmergencyUnlock(address indexed user, uint256 indexed id, uint256 indexed penaltyAmount);
    event CleanedUpExpiredPosition(uint256 indexed id, address indexed user, uint256 indexed amount, address caller);
    event ClaimRequestInitiated(address indexed user, uint256 indexed requestId);
    event WordRetrieved(uint256 indexed positionId, uint256 indexed requestId, uint256 indexed randomWord);

    enum Tier {One, Two, Three, Four, Five, Six}
}