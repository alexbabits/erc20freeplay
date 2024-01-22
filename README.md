## Notes

This is kind of like if someone pays you, but it goes directly into your 401K or whatever so it doesn't count as your income? Kind of in that sphere of idea? Thoughts? I'll of course talk with people knowledgeable in tax law, but perhaps it is promising to think that this is properly deferring funds.

Because for example, say Alice sends bob 100 tokens. Alice now has 0 tokens, and Bob has 100 in his pending balance, and 0 in his real spendable balance. This means those 100 tokens are inert and he cannot be used. He may pseudo-own them, but they aren't "activated". It's like someone giving you a pre-paid visa giftcard, but if you don't activate it, do you own the funds yet? I suppose it depends, or if there are any tax precedents for things like that? 

1. Set time for how long you want your pending coins to be locked, default to 0 seconds.
2. Set boolean if you want to auto claim or not (Defaults to auto claim).

If you have any pending tokens, you cannot change your time lock amount or boolean perhaps?
Or at least any future funds that come in, will be subject to the new time?

ERC20Deferred: May need a 712 signature pattern for Bob to call the functions? How does that work?


mapping from address --> uint256 claimTime

Contribute here as an ERC20 extension: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/token/ERC20/extensions


### Deploy
`forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>`







1. Write Deploy Script
2. Write Tests
3. Include set time? Max time? Minimum time?