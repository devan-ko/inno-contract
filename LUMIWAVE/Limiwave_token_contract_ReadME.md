# LUMIWAVE contract introductory document. 
## Repo
- [Repo is here](https://github.com/ONBUFF-IP-TOKEN/inno-contract) 

## High leve requirement
- Lumiwave is the token which is migrated from Ethereum to Sui, Previously called [ONIT](https://etherscan.io/token/0x410e731c2970Dce3AdD351064AcF5cE9E33FDBf0). 
- This token contract is following regulated token from mentioned in [example in here](https://docs.sui.io/guides/developer/sui-101/create-coin/regulated). 
  - Token deploy entity will owned `TreasuryCap` & `DenyCap` for control issuing token, which is the Lumiwave. 
  - Token contract has to be including below features below;
    - Token should be controlled by `TreasuryCap` & `DenyCap` owned account. 
    - Token contract can mint lumiwave token.
    - Token contract can burn lumiwave token.
    - `DenyCap` owner possibly add account to deny list.
    - `DenyCap` owner possibly remove account from deny list.
    - Contract possibly to create locked coin through wrapper object functionality. 
      - This feature has time which will be restricted release token based on the already set time for release. 
      - Lockig token possible to transfer.
    - Token contract has functionality which possibly issued additional token through the vote.
      - Based on that token contract has to including vote functionality
      - Token contract has to be including functionality which shows vote status through vote dashboard. 
      - Token contract has to be including functionality which enable to vote for the token issuance through the vote result.
      - Voter has to be owend vote evidence after vote.
      - Vote dashboard will be reusable after vote finished through vote reset funtionality.
      - Each vote has to be binding with specific time-window from vote start to vote end


## Smart contract modules

### lumiwave.move
-  Working as primary contract module
-  It includes creat vote dashboard.
-  It contains vote enabling functionality.
-  It contains to make user vote. 
-  It cointains vote dashboard reset functionality.
-  It includes add/remove account to deny list
-  It contains mint & burn token functionality
-  It contains transfer locking token to account. 
-  It contains unlock token functionality.

### vote.move
- Module contains resetting vote dashboard functionalities. 
- Module includes create Voting evidence object. 
- Module contains vote feature.
-  Module contains to change vote status feature. 

### lock_coin.move
- Module contains make locking token based on the time stamp.
- Module contains unlock wrapper functionality which unlock token. 

## Structs

### lumiwave.move:struct

```Move
 // Shared object to be recorded as voting progress
    struct VoteBoard has key {
        id: UID,
        status: VoteStatus,
        participants: VecMap<address, Participant>,
        result: u64, // result of the vote => 0:no vote count, 1:agreement, 2:Opposition, 3:Voting invalid
    }
```

### vote.move:struct

```Move
// Vote status information
struct VoteStatus has store, copy, drop {
    enable: bool,   // Whether voting is enabled
    start_ts: u64,  // Start time of voting (ms)
    end_ts: u64,    // End time of voting (ms)
}

// Participant information for voting
struct Participant has store, copy, drop {
    addr: address,  // Voter's wallet address
    ts: u64,        // Timestamp of voting participation
    is_agree: bool, // Agreement, disagreement
}

// NFT for confirming voting participation
struct VotingEvidence has key, store {
    id: UID,
    name: String,
    description: String,
    project_url: Url,
    image_url: Url,
    creator: String,
    is_agree: bool,
}
```

### lock_coin.move:struct

```Move
    struct LockedCoin<phantom T> has key {
        id: UID,
        lock_ts: u64, // Timestamp of token lock
        unlock_ts: u64, // Timestamp of token un-lock
        lock_blance: Balance<T>,
    }
```
## Functions ( public view functions will not include)

### lumiwave.move:function
- make_voteboard : create voting dashboard
- add_deny/remove_deny : relevant to deny list funtion
- mint/burn : token mint & burn.
- locking token relevant function
  - lock_coin_transfer
  - unlock_coin
- Voting relevant function
  - enable_vote : Activating/Deactivating voting
  - vote
  - vote_counting : Vote counting
  - vote_reset : Resetting the completed vote counting so that it can be voted again next time

### vote.move:function
- Functions under the this module is friend to lumiwave module.
- voting
- votestatus_enable: Enable voting with timestmap condition.

### lock_coin.move:function
- Functions under the this module is friend to lumiwave module.
- make_coin_lock :  Lock coins and transfer
- unlock_wrapper : unlock token. 

## Miscellaneous

### Max supply

```Move
const MaxSupply: u64 = 1000000000000000000;  // 1 Billion
```

### Vote result codes

```Move
 // vote result
    const VOTE_NONE: u64 = 0;       // No vote count
    const VOTE_AGREE: u64 = 1;      // Agreement
    const VOTE_DISAGREE: u64 = 2;   // Opposition
    const VOTE_INVALIDITY: u64 = 3; // Voting invalid
```

### Error codes

```Move
    // err code
    const ErrNotVotingEnable: u64 = 1;              // Not in a voting state
    const ErrAlreadyVoters: u64 = 2;                // You've already voted
    const ErrNotHolder: u64 = 3;                    // It's not a coin holder.
    const ErrExceededMaxSupply: u64 = 4;            // Maximum supply exceeded
    const ErrNotVotePeriod: u64 = 5;                // It's not a voting period
    const ErrVotingAlreadyClosed: u64 = 6;          // The counting of votes has already been completed.
    const ErrAlreayReset: u64 = 7;                  // It is already reset.
    const ErrAlreadyVotingEnable: u64 = 8;          // Voting is already active.
    const ErrNotVoteCountingPeriod: u64 = 9;        // It is not a countable period.
    const ErrInvalidStartEndTimestamp: u64 = 10;    // Vote start end time validation failed
    const ErrNotMinVoters: u64 = 11;                // Not enough minimum voters
```

# EOD