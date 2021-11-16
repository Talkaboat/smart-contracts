# smart-contracts
## Aboat Token
Transaction-Fees on outgoing transactions are secured by adding the router on whitelist as sender.

The MasterEntertainer is also excluded from fees so staking and unstaking are not subject of extra fees.

On every Transaction a update check is sent to the MasterEntertainer to update the price feed.

Every taxable transaction is subject of variable tax (x - xx) based on the amount of aboat token the sender owns.

The tax are divided into:
- Reward System (40 %) [Reward System is our semi-burn system to make sure we always have enough rewards]
- Liquidity (30 %)
- Aboat Entertainment (20 %) - Direct swap to bnb to have as less impact on price as possible
- Donation (10 %) - Direct swap to bnb to have as less impact on price as possible

Every swap to bnb from tax is done when a certain amount of Aboat Token is stored as tax.

Maintainer:
As we drop the ownership to our MasterEntertainer and won't be able to reclaim it, we introduced an maintainer.
The maintainer is eligible to make changes to:
- fee structure
- white- & blacklist
- activate & deactivate high fees ( to prevent sniper bots)
- activate contract (contract can't be disabled afterwards)
- set gas cost for whitelist request
- change max account balance and max transaction size
- change max distribution (the new distribution won't be minted and is only available to and from the MasterEntertainer)
- claim exceeding eth/bnb
- update Router for Liquification/Swapping
- include/exclude from fees
- set reward, donation and dev wallet
- change tax distribution
- change min amount to liquify
- activate/deactivate liquification

Anti-Bot Systems:
- Inactive Smart Contract on deployment (only owner and maintainer are eligible to do anything)
- Active High Fees when adding liquidity

Timelock:
- 24h Lock
- Required to send an change request 24h ahead
- Change can be made after 24h for 24h (once the method is called or the 24h timeframe is over the lock is re-enabled)
