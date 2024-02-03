## Setup
`forge install OpenZeppelin/openzeppelin-contracts`

## Local Deploy with Script
1. `anvil` (Starts local node)
2. Open another terminal and run `export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"` (It's associated address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`). This is the local nodes default (first) private-public key pair.
3. deploy: `forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast`
4. Console displays deployed address for `DeferredTokenExample`: `0x5FbDB2315678afecb367f032d93F642f64180aa3`


## Local Interactions after Deployment
Good variables to have:
1. `export ADMIN="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"`
2. `export TOKEN="0x5FbDB2315678afecb367f032d93F642f64180aa3"` // token contract address.
3. `export ALICE="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"`
4. `export BOB="0x976EA74026E726554dB657fA54763abd0C3a0aa9"`


## Brief Testing
1. Check balance of Admin, should be 1e27: `cast call $TOKEN "balanceOf(address)(uint256)" $ADMIN`
2. Alice turns on manual claim: `cast send $TOKEN --unlocked --from $ALICE "toggleClaimStatus()"`
3. Transfer tokens from Admin to Alice (Either syntax works):
    - `cast send $TOKEN --unlocked --from $ADMIN "transfer(address,uint256)(bool)" $ALICE 1000000000000000000000000`
    - `cast send $TOKEN --from $ADMIN "transfer(address,uint256)(bool)" $ALICE 1000000000000000000000000 --private-key $PRIVATE_KEY`
4. Pending balance increases: `cast call $TOKEN "pendingBalanceOf(address)(uint256)" $ALICE`
5. Normal balance still 0: `cast call $TOKEN "balanceOf(address)(uint256)" $ALICE`
6. Claim pending tokens: `cast send $TOKEN --unlocked --from $ALICE "claimAll()"`
7. Pending balance now 0: `cast call $TOKEN "pendingBalanceOf(address)(uint256)" $ALICE`
8. Normal balance increases: `cast call $TOKEN "balanceOf(address)(uint256)" $ALICE`