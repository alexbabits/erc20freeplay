// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract erc20Deferred {

    string public name = "Deferred ERC20";
    string public symbol = "DERC20";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public pendingBalanceOf;

    mapping(address => bool) public manualClaimEnabled; // defaults to false

    event Transfer(address indexed from, address indexed to, uint256 value);
    event claimAll(address indexed claimer, uint256 indexed fullAmount);
    event claimPartial(address indexed claimer, uint256 indexed amount);
    event toggledClaimMode(address indexed user);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 _initialSupply) {
        balanceOf[msg.sender] = _initialSupply;
        totalSupply = _initialSupply;
    }

    function toggleClaimMode() public {
        manualClaimEnabled[msg.sender] = !manualClaimEnabled[msg.sender];
        emit toggledClaimMode(msg.sender);
    }

    function claimAll() public returns (uint256 fullAmount) {
        require(pendingBalanceOf[msg.sender] > 0, "no pending funds");
        uint256 fullAmount = pendingBalanceOf[msg.sender];
        pendingBalanceOf[msg.sender] = 0;
        balanceOf[msg.sender] += fullAmount;
        emit claimAll(msg.sender, fullAmount);
    }

    function claimPartial(uint256 amount) public returns (uint256 amount) {
        require(pendingBalanceOf[msg.sender] > 0, "no pending funds");
        require(amount > pendingBalanceOf[msg.sender], "claimed too much");
        balanceOf[msg.sender] += amount;
        pendingBalanceOf[msg.sender] -= amount;
        emit claimPartial(msg.sender, amount);
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance for transfer");

        if (manualClaimEnabled[_to]) {
            balanceOf[msg.sender] -= _value;
            pendingBalanceOf[_to] += _value;
        } else {
            balanceOf[msg.sender] -= _value;
            BalanceOf[_to] += _value;
        }

        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= balanceOf[_from], "Insufficient balance");
        require(_value <= allowance[_from][msg.sender], "Allowance exceeded");

        if (manualClaimEnabled[_to]) {
            balanceOf[_from] -= _value;
            pendingBalanceOf[_to] += _value;
        } else {
            balanceOf[_from] -= _value;
            balanceOf[_to] += _value;
        }

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value, "Insufficient balance for approval");
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
}