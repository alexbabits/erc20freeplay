## Setup
`forge install OpenZeppelin/openzeppelin-contracts`
`forge install smartcontractkit/chainlink`

## Local Deploy with Script
1. `anvil` (Starts local node)
2. Open another terminal and run `export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"` (It's associated address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`). This is the local nodes default (first) private-public key pair.
3. deploy contracts: `forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast`
4. Shows your deployed addresses:
    - Deployed `MockEscrow.sol` at address: `0x5FbDB2315678afecb367f032d93F642f64180aa3`
    - Deployed `MockFreePlayToken.sol` at address: `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`
    - Deployed `Loot.sol` at address: `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9`

## Local Interactions after Deployment
Good variables to have:
1. `export ADMIN="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"` // local node's default (first) private-public key pair.
2. `export TOKEN="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"` // token contract address that was deployed
3. `export ESCROW="0x5FbDB2315678afecb367f032d93F642f64180aa3"` // Escrow address that was deployed
3. `export ALICE="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"`
4. `export BOB="0x976EA74026E726554dB657fA54763abd0C3a0aa9"`


## Brief Testing
1. Check balance of Admin, should be 1e27: `cast call $TOKEN "balanceOf(address)(uint256)" $ADMIN`
2. Alice turns on manual claim: `cast send $TOKEN --unlocked --from $ALICE "toggleClaimStatus()"`
3. Transfer tokens from Admin to Alice (Either syntax works):
    - `cast send $TOKEN --unlocked --from $ADMIN "transfer(address,uint256)(bool)" $ALICE 1000000000000000000000000`
    - `cast send $TOKEN --from $ADMIN "transfer(address,uint256)(bool)" $ALICE 1000000000000000000000000 --private-key $PRIVATE_KEY`
4. free play credits increases: `cast call $TOKEN "freePlayCreditsOf(address)(uint256)" $ALICE`
5. Normal balance still 0: `cast call $TOKEN "balanceOf(address)(uint256)" $ALICE`
6. Claim pending tokens: `cast send $TOKEN --unlocked --from $ALICE "claimAll()"`
7. free play credits now 0: `cast call $TOKEN "freePlayCreditsOf(address)(uint256)" $ALICE`
8. Normal balance increases: `cast call $TOKEN "balanceOf(address)(uint256)" $ALICE`