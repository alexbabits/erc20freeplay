// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/ERC20Deferred.sol)
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
//⚠️For OpenZeppelin integration, switch location to "../ERC20.sol";⚠️ 

/**
 * @dev Extension of {ERC20} with an opt-in deferred mechanism for all received tokens.
 */
abstract contract ERC20Deferred is ERC20 {

    uint8 private immutable UNINITIALIZED = 0;
    uint8 private immutable OFF = 1;
    uint8 private immutable ON = 2;

    /**
     * @dev (account --> pending balance)
     * User's pending balance is completely inert and unusable with zero value whatsoever unless they claim the tokens.
     * User cannot transfer or burn these pending tokens unless they claim them to their real balance
     * A more accurate description is `_inertBalanceUntilClaimed`, but `_pendingBalances` was chosen for brevity.
     */
    mapping(address => uint256) private _pendingBalances;

    /**
     * @dev (account --> manual claim status)
     * Users status can be UNINITIALIZED, OFF, or ON.
     * As long as their status is not ON, all tokens received are handled identically to normal ERC20 standard.
     * When the user chooses to set their manual claim status to ON, all tokens recieved through mints and transfers
     * are sent to their `_pendingBalances` instead of `_balances`, where they can be claimed whenever they want.
     */
    mapping(address => uint8) private _manualClaim;

    /**
     * @dev (account --> location of where the minting call originates)
     * This flag is set to true when a `_mint()` occurs from `claimAll()` or `claimSpecificAmount()`.
     * The flag is immediately reset back to false after the "real" `_mint()` occurs.
     * This ensures a "real" `_mint()` happens so user can claim their pending tokens.
     * All "regular" mints outside of claiming functions are directed to 
     * increase the users `_pendingBalances` and NOT increase total supply.
     * (Assuming the user has opted in to manual claim)
     */
    mapping(address => bool) private _mintingFromClaim;

    error NoPendingFunds();
    error ZeroClaimAmount();
    error ManualClaimNotOn();
    error InsufficientPendingFunds(uint256 requestedClaimAmount, uint256 pendingBalance);

    event Claim(address indexed claimer, uint256 indexed amountClaimed);
    event ToggledClaimStatus(address indexed user, uint8 indexed claimStatus);
    event PendingBalanceUpdated(address indexed from, address indexed to, uint256 value);

    /**
    * @dev Allows user to toggle their claim status.
    * @dev `manualClaim[user] != ON`: Tokens received are credited directly to their normal `_balances` mapping.
    * @dev `manualClaim[user] == ON`: Tokens received are credited to their `_pendingBalances` mapping, and
    * @dev they must claim them via `claimAll()` or `claimSpecificAmount()` to credit their `_balances` mapping.
    */
    function toggleClaimStatus() external {
        uint8 userStatus = _manualClaim[msg.sender];

        if (userStatus == UNINITIALIZED) {
            _manualClaim[msg.sender] = ON;
        } else {
            _manualClaim[msg.sender] = userStatus == ON ? OFF : ON;
        }

        emit ToggledClaimStatus(msg.sender, userStatus);
    }

    /**
    * @dev Allows user to claim their entire pending balance.
    * @dev `_mint()` is being used because when the recipient received tokens,
    * @dev the senders tokens were redirected to address(0) to avoid crediting the users `_balances` mapping.
    * @dev Therefore we mint those tokens back into existence during a claim.
    */
    function claimAll() external {
        uint256 entirePendingAmount = _pendingBalances[msg.sender];

        if (_manualClaim[msg.sender] != ON) revert ManualClaimNotOn();
        if (entirePendingAmount == 0) revert NoPendingFunds();

        _mintingFromClaim[msg.sender] = true;
        _pendingBalances[msg.sender] = 0;
        _mint(msg.sender, entirePendingAmount);
        _mintingFromClaim[msg.sender] = false;

        emit Claim(msg.sender, entirePendingAmount);
    }

    /**
    * @dev Allows user to claim a specific amount of tokens from their pending balance.
    * @dev `_mint()` is being used because when the recipient received tokens,
    * @dev the senders tokens were redirected to address(0) to avoid crediting the users `_balances` mapping.
    * @dev Therefore we mint those tokens back into existence during a claim.
    */
    function claimSpecificAmount(uint256 amount) external {
        if (_manualClaim[msg.sender] != ON) revert ManualClaimNotOn();
        if (_pendingBalances[msg.sender] == 0) revert NoPendingFunds();
        if (amount == 0) revert ZeroClaimAmount();
        if (amount > _pendingBalances[msg.sender]) revert InsufficientPendingFunds(amount, _pendingBalances[msg.sender]);

        _mintingFromClaim[msg.sender] = true;
        _pendingBalances[msg.sender] -= amount;
        _mint(msg.sender, amount);
        _mintingFromClaim[msg.sender] = false;

        emit Claim(msg.sender, amount);
    }

    /**
     * @dev See {ERC20._update}
     * There appears to be no easy way to directly modify the private `_balances` mapping of a user from ERC20.sol❓
     * To circumvent this problem, whenever the recipients manual claim is enabled, 
     * transfers decrement the senders `_balances` by redirecting them to the burn address via `_burn()`.
     * The drawback is this ⚠️DECREASES⚠️ the total supply until the recipient claims their pending balance.
     * "transfers" in this paragraph refers to tokens coming from non-zero address accounts (NOT MINTS).
     *
     * Anytime the recipient's manual claim status is not ON, all types of transfers remain uneffected.
     * All burns remain uneffected because the burn address never has manual claim enabled.
     * 
     * For "regular" mints where the recipient has enabled manual claim status and is NOT minting from a claim function,
     * the  users `_pendingBalances` is increased and the token total supply is ⚠️NOT⚠️ increased.
     * The total supply will not increase until the recipient claims their pending balance through a claim function,
     * which executes a real `_mint()` and increases the total supply.
     * 
     * For "special" mints coming from `claimAll()` or `claimSpecificAmount()` when recipient is claiming their pending balance,
     * their real `_balances` and token total supply must increase like normal.
     */
    function _update(address from, address to, uint256 value) internal virtual override {

        /*
        💡💡💡
        One potential solution to keep a constant total supply at all times during transfers, 
        is to redirect the senders tokens to an intermediary inert vault instead of burning them.
        When user claims their pending balance, the amount would be then be burned from the vault and minted to user. 
        This would also further distance (if that's even possible) the pending funds apart from the user.
        There's probably some way to do this, but may be overkill for an ERC20 extension, or it may be a superior option❓
        */

        uint8 recipientStatus = _manualClaim[to];
        bool mintFromClaim = _mintingFromClaim[to];

        // Any time the recipients manual claim is not enabled or the transfer is a burn, execute `_update()` as normal.
        if (recipientStatus != ON || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Transfers should redirect the sent tokens to burn address and credit `_pendingBalances` instead of `_balances`.
        // Importantly, the burn is used to properly decrement the senders tokens, so all accounting remains intact.
        if (recipientStatus == ON && from != address(0)) {
            _burn(from, value);
            _pendingBalances[to] += value;
            emit PendingBalanceUpdated(from, to, value);
        }

        // "regular" mints should credit users `_pendingBalances` and does NOT update
        // the token total supply until the user claims their pending balance.
        if (recipientStatus == ON && from == address(0) && mintFromClaim != true) {
            _pendingBalances[to] += value;
            emit PendingBalanceUpdated(from, to, value);
        } 

        // "special" mints coming from a "claim" function should credit users `_balances` and update total supply as normal.
        if (recipientStatus == ON && from == address(0) && mintFromClaim == true) {
            super._update(from, to, value);
            return;
        }
    }

    /**
     * @dev See {ERC20.balanceOf}. Identical except it replaces `_balances` with `_pendingBalances`.
     */
    function pendingBalanceOf(address account) public view returns (uint256) {
        return _pendingBalances[account];
    }

    /**
     * @dev View function to see a users manual claim status.
     */
    function manualClaimStatus(address account) public view returns (uint8) {
        return _manualClaim[account];
    }
}