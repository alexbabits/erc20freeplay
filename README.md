## Licensing 
https://creativecommons.org/licenses/by-nc-nd/4.0/

You are free to:
* Share — copy and redistribute the material in any medium or format. The licensor cannot revoke these freedoms as long as you follow the license terms.

Under the following terms:
* Attribution — You must give appropriate credit , provide a link to the license, and indicate if changes were made . You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
* NonCommercial — You may not use the material for commercial purposes .
* NoDerivatives — If you remix, transform, or build upon the material, you may not distribute the modified material.

## Dependencies
* `forge install OpenZeppelin/openzeppelin-contracts`
* `forge install smartcontractkit/chainlink` // remapping required in foundry.toml

## Documentation
All documentation will be pasted here in the future (lots).

## Local Deployment
1. `anvil`
2. `export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"` // anvil 1st private key
3. `forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast`

## Local Interactions
1. `export ESCROW="0x5FbDB2315678afecb367f032d93F642f64180aa3"`
2. `export LOOT="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"`
3. `export ERC20FREEPLAY="0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"`
4. `export OWNER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"`
5. `export ALICE="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"`
6. `export BOB="0x976EA74026E726554dB657fA54763abd0C3a0aa9"`

// `call` for view functions, `send` for state changing functions.

1. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $OWNER` // Owner has 1B tokens
2. `cast send $ERC20FREEPLAY --unlocked --from $OWNER "transfer(address,uint256)(bool)" $ALICE 100000000000000000000` // Send Alice 100 tokens
3. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $ALICE` // She has 100 tokens

4. `cast send $ERC20FREEPLAY --unlocked --from $ALICE "toggleFreePlayStatus()"` // Alice FP status now turned ON
5. `cast call $ERC20FREEPLAY "getUserInfo(address)(uint256,uint256,uint64,uint64,uint8,uint8)" $ALICE` // Her status is ON (integer 2)

6. `cast send $ERC20FREEPLAY --unlocked --from $OWNER "transfer(address,uint256)(bool)" $ALICE 69000000000000000000`// Send Alice 69 tokens
7. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $ALICE` // She STILL has only 100 tokens
8. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $ESCROW` // Escrow has the 69 tokens
9. `cast call $ERC20FREEPLAY "getUserInfo(address)(uint256,uint256,uint64,uint64,uint8,uint8)" $ALICE` // She has 69 totalFreePlayCredits
10. `cast call $ERC20FREEPLAY "getFreePlayPosition(uint256)(uint256,uint256,address,uint64,uint64,uint16,uint16,uint8,uint8)" 1` // FP credits = 69 PosID = 1


## Sepolia Deployment
1. `export SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY_HERE"`
2. `export PRIVATE_KEY="0xYOUR_PRIVATE_KEY"`
3. `forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast`
4. Add `ERC20FREEPLAY` address as a consumer in `vrf.chain.link/sepolia/SUBSCRIPTION_ID_HERE`

## Sepolia Interactions
1. `export OWNER="0xeC9e0FB9Ac1F0504Ca29C86f82Da98DB89579e54"` // Let Admin be the owner/deployer.
2. `export BOB="0x75acC90b46166cb87FB7Ba3217744bd8106697A4"` // Another real address
3. `export ERC20FREEPLAY="0x04c9b9D41a4C723fc541ADEF0383AB8213AFB749"` // real addy
4. `export ESCROW="0xAefCb90443D563D21321f869CdD14dB49B2f011A"` // real addy
5. `export LOOT="0x7A25641654335e54b15d26386d998E7B3EC99339"` // real addy

// `call` for view, `send` for state changing functions.

1. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $OWNER --rpc-url $SEPOLIA_RPC_URL` // Owner has 1B tokens
2. `cast send $ERC20FREEPLAY "transfer(address,uint256)(bool)" $BOB 100000000000000000000 --from $OWNER --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL` // Send Bob 100 tokens, can also be done through MM.
3. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $BOB --rpc-url $SEPOLIA_RPC_URL` // Bob has 100 tokens, also visible on MM.
4. `cast send $ERC20FREEPLAY "toggleFreePlayStatus()" --from $OWNER --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL` // Owner FP status now turned ON
5. `cast call $ERC20FREEPLAY "getUserInfo(address)(uint256,uint256,uint64,uint64,uint8,uint8)" $OWNER --rpc-url $SEPOLIA_RPC_URL` // Owner status is ON (integer 2)
6. in MM, Bob sends Owner 69 of his 100 tokens. (Cannot send from Bob --> Owner in code if Bob is just your 2nd MM address associated to same private key)
7. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $OWNER --rpc-url $SEPOLIA_RPC_URL` // Owner doesn't receive the 69 tokens (as seen on MM too).
8. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $ESCROW --rpc-url $SEPOLIA_RPC_URL` // Escrow has the 69 tokens
9. `cast call $ERC20FREEPLAY "getUserInfo(address)(uint256,uint256,uint64,uint64,uint8,uint8)" $OWNER --rpc-url $SEPOLIA_RPC_URL` // Owner has 69 totalFreePlayCredits
10. `cast call $ERC20FREEPLAY "getFreePlayPosition(uint256)(uint256,uint256,address,uint64,uint64,uint16,uint16,uint8,uint8)" 1 --rpc-url $SEPOLIA_RPC_URL` // FP credits = 69 PosID = 1

11. `cast send $ERC20FREEPLAY "initiateClaim(uint256)" 1 --from $OWNER --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL` // initiate claim with VRF

12. `cast call $ERC20FREEPLAY "getFreePlayPosition(uint256)(uint256,uint256,address,uint64,uint64,uint16,uint16,uint8,uint8)" 1 --rpc-url $SEPOLIA_RPC_URL`
13. `cast send $ERC20FREEPLAY "finalizeClaim(uint256,bool)" 1 false --from $OWNER --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL`

// check position was deleted, and totalFreePlayCredits from user, and balance (shows on MM too)
14. `cast call $ERC20FREEPLAY "getFreePlayPosition(uint256)(uint256,uint256,address,uint64,uint64,uint16,uint16,uint8,uint8)" 1 --rpc-url $SEPOLIA_RPC_URL`
15. `cast call $ERC20FREEPLAY "getUserInfo(address)(uint256,uint256,uint64,uint64,uint8,uint8)" $OWNER --rpc-url $SEPOLIA_RPC_URL`
16. `cast call $ERC20FREEPLAY "balanceOf(address)(uint256)" $OWNER --rpc-url $SEPOLIA_RPC_URL`