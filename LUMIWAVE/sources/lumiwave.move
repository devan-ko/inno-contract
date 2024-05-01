// Copyright (c) PDX, Inc.
// SPDX-License-Identifier: Apache-2.0

module lumiwave::LWA {
    use std::option;
    use sui::coin::{Self, Coin, TreasuryCap, DenyCap};
    use sui::transfer;
    use sui::url;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::deny_list::{DenyList};
    use sui::vec_map::{VecMap};
    use sui::clock::{Self};
    use sui::pay;

    use lumiwave::vote::{Self, VoteStatus, Participant};
    use lumiwave::lock_coin::{Self};

    // Shared object to be recorded as voting progress
    struct VoteBoard has key {
        id: UID,
        status: VoteStatus,
        participants: VecMap<address, Participant>,
        result: u64, // result of the vote => 0:no vote count, 1:agreement, 2:Opposition, 3:Voting invalid
    }
    /// ===== Move code consultation =====
    /// Readability를 위해 000세자리 수로 표기하는 것을 권장합니다.
    /// 예시 : 1000000000 => 1_000_000_000
    const MaxSupply: u64 = 1000000000000000000;  // 1 Billion

    // vote result
    const VOTE_NONE: u64 = 0;       // No vote count
    const VOTE_AGREE: u64 = 1;      // Agreement
    const VOTE_DISAGREE: u64 = 2;   // Opposition
    const VOTE_INVALIDITY: u64 = 3; // Voting invalid

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
    const ErrInvalidpassingThreshold: u64 = 11;     // Not a valid passing threshold information

    struct LWA has drop {}

    #[allow(lint(share_owned))]
    fun init(witness: LWA, ctx: &mut TxContext) {
        let (treasury_cap, deny_cap,  metadata) = coin::create_regulated_currency(
           witness,
           9, 
           b"LWA", 
           b"LUMIWAVE", 
           b"", 
           option::some(url::new_unsafe_from_bytes(b"https://onbufffile.blob.core.windows.net/inno/live/icon/LUMIWAVE_Primary_black.png")), 
           ctx);
        transfer::public_freeze_object(metadata);

        let owner = tx_context::sender(ctx);

        coin::mint_and_transfer<LWA>(&mut treasury_cap, 770075466000000000, owner, ctx);
        // ===== Move code consultation =====
        // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 Max supply 이상으로 발행 할 수 있습니다. 
        // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 treasury_cap을 보유한 account의 의도대로 코인을 burn 할 수 있습니다. 
        // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 MAX_SUPPLY를 우회 할 수 있습니다.  
        // treasury_cap 오브젝트를 소유한 account가 탈취되거나 treasury_cap 오브젝트가 Onbuff가 관리하는 account 외 다른 account로 이전되면 의도치 않은 coin이 Max supply 이상으로 발행 될 수 있습니다.
        // 아래 코드를 참조하시길 바랍니다. 
        // https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/coin.move#L268-L294
        // /// Create a coin worth `value` and increase the total supply
        // /// in `cap` accordingly.
        // public fun mint<T>(
        //     cap: &mut TreasuryCap<T>, value: u64, ctx: &mut TxContext,
        // ): Coin<T> {
        //     Coin {
        //         id: object::new(ctx),
        //         balance: cap.total_supply.increase_supply(value)
        //     }
        // }
        // /// Mint some amount of T as a `Balance` and increase the total
        // /// supply in `cap` accordingly.
        // /// Aborts if `value` + `cap.total_supply` >= U64_MAX
        // public fun mint_balance<T>(
        //     cap: &mut TreasuryCap<T>, value: u64
        // ): Balance<T> {
        //     cap.total_supply.increase_supply(value)
        // }
        // /// Destroy the coin `c` and decrease the total supply in `cap`
        // /// accordingly.
        // public entry fun burn<T>(cap: &mut TreasuryCap<T>, c: Coin<T>): u64 {
        //     let Coin { id, balance } = c;
        //     id.delete();
        //     cap.total_supply.decrease_supply(balance)
        // } 
        //     transfer::public_transfer(treasury_cap, owner);
        //     transfer::public_transfer(deny_cap, owner);
        //     let vote = make_voteboard(ctx);
        //     transfer::share_object(vote);
        // }
    
        transfer::public_transfer(treasury_cap, owner);
        transfer::public_transfer(deny_cap, owner);

        let vote = make_voteboard(ctx);
        transfer::share_object(vote);
    }

    // === Private Functions ===
    fun make_voteboard(ctx: &mut TxContext): VoteBoard {
        VoteBoard{
            id: object::new(ctx),
            status: vote::empty_status(),
            participants: vote::empty_participants(),
            result: VOTE_NONE,
        }
    }

    // === Public-View Functions ===
    public fun is_enable_vote(vote_board: &mut VoteBoard): bool {
        vote::is_votestatus_enable( &vote_board.status )
    }

    public fun is_voted(vote_board: &mut VoteBoard, participant: address): bool{
        vote::is_voted(&vote_board.participants, participant)
    }

    // ===== Move code consultation =====
    // 아래 코드는 VoteBoard 오브젝트의 status, participants, result를 반환합니다.
    // participants는 address를 key로 하는 Participant 오브젝트의 VecMap 입니다.
    // 구체적인 Participant 오브젝트의 구조를 구하기 위해 추가적인 View 함수가 필요할 수도 있습니다.
    public fun vote_detail(vote_board: &VoteBoard): ( VoteStatus, VecMap<address, Participant>, u64) {
        ( vote_board.status, vote_board.participants, vote_board.result )
    }

    // ===== Move code consultation =====
    // coin::deny_list_add 함수는 아래에서 직접 바로 호출 할 수 있습니다. 
    // https://suivision.xyz/package/0x0000000000000000000000000000000000000000000000000000000000000002?tab=Code
    // 0x02::coin::deny_list_add
    // 0x02::coin::deny_list_remove
    // 참고 링크 : https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/coin.move#L299-L333
    /*
    /// Adds the given address to the deny list, preventing it
    /// from interacting with the specified coin type as an input to a transaction.
    public fun deny_list_add<T>(
       deny_list: &mut DenyList,
       _deny_cap: &mut DenyCap<T>,
       addr: address,
       _ctx: &mut TxContext
    ) {
        let `type` =
            type_name::into_string(type_name::get_with_original_ids<T>()).into_bytes();
        deny_list::add(
            deny_list,
            DENY_LIST_COIN_INDEX,
            `type`,
            addr,
        )
    }

    /// Removes an address from the deny list.
    /// Aborts with `ENotFrozen` if the address is not already in the list.
    public fun deny_list_remove<T>(
       deny_list: &mut DenyList,
       _deny_cap: &mut DenyCap<T>,
       addr: address,
       _ctx: &mut TxContext
    ) {
        let `type` =
            type_name::into_string(type_name::get_with_original_ids<T>()).into_bytes();
        deny_list::remove(
            deny_list,
            DENY_LIST_COIN_INDEX,
            `type`,
            addr,
        )
    }
    */
        
    // === Public-Mutative Functions ===
    // Register wallets to deny
    public entry fun add_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext) {
        coin::deny_list_add<LWA>( denylist, deny_cap, recipient, ctx)
    }
    // Release denied wallets
    public entry fun remove_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext){
        coin::deny_list_remove<LWA>(denylist, deny_cap, recipient, ctx)
    }

    // ===== Move code consultation =====
    // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 Max supply 이상으로 발행 할 수 있습니다. 
    // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 treasury_cap을 보유한 account의 의도대로 코인을 burn 할 수 있습니다. 
    // treasury_cap 오브젝트를 burn/freeze 하지 않는다면 MAX_SUPPLY를 우회 할 수 있습니다.   
    // treasury_cap 오브젝트를 소유한 account가 탈취되거나 treasury_cap 오브젝트가 Onbuff가 관리하는 account 외 다른 account로 이전되면 의도치 않은 coin이 Max supply 이상으로 발행 될 수 있습니다.
    // 아래 코드를 참조하시길 바랍니다.
    // 참고 링크 : https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/coin.move#L268-L294
    /*    
    /// Create a coin worth `value` and increase the total supply
    /// in `cap` accordingly.
    public fun mint<T>(
        cap: &mut TreasuryCap<T>, value: u64, ctx: &mut TxContext,
    ): Coin<T> {
        Coin {
            id: object::new(ctx),
            balance: cap.total_supply.increase_supply(value)
        }
    }

    /// Mint some amount of T as a `Balance` and increase the total
    /// supply in `cap` accordingly.
    /// Aborts if `value` + `cap.total_supply` >= U64_MAX
    public fun mint_balance<T>(
        cap: &mut TreasuryCap<T>, value: u64
    ): Balance<T> {
        cap.total_supply.increase_supply(value)
    }

    /// Destroy the coin `c` and decrease the total supply in `cap`
    /// accordingly.
    public entry fun burn<T>(cap: &mut TreasuryCap<T>, c: Coin<T>): u64 {
        let Coin { id, balance } = c;
        id.delete();
        cap.total_supply.decrease_supply(balance)
    }
    */
    // Additional coin issuance
    public fun mint(treasury_cap: &mut TreasuryCap<LWA>, amount: u64, recipient: address, ctx: &mut TxContext) {
        let new_supply = coin::total_supply<LWA>(treasury_cap) + amount; // Calculate new supply in advance
        assert!(new_supply <= MaxSupply, ErrExceededMaxSupply); // Check if maximum supply is exceeded
        coin::mint_and_transfer(treasury_cap, amount, recipient, ctx);
    }
    

    // ===== Move code consultation =====
    // 1. treasury_cap와 같이 사용되지 않는 Param이 있다면 _를 사용하여 표기합니다.
    // 2. entry 키워드는 필요 없는것으로 보입니다. 
    
    // Locking coins & transfer
    #[allow(unused_variable)]
    public entry fun lock_coin_transfer( treasury_cap: &mut TreasuryCap<LWA>, my_coin: Coin<LWA>, 
                                   recipient: address, amount: u64, unlock_ts: u64, clock: &clock::Clock, ctx: &mut TxContext) {
        let new_coin = coin::split(&mut my_coin, amount, ctx);
        pay::keep(my_coin, ctx);

        lock_coin::make_lock_coin<LWA>(  recipient, clock::timestamp_ms(clock), unlock_ts, coin::into_balance(new_coin), ctx);
    }

    // ===== Move code consultation =====
    // entry 키워드는 필요 없는것으로 보입니다. 
    // Unlocking coins
    public entry fun unlock_coin( locked_coin: lock_coin::LockedCoin<LWA>, clock: &clock::Clock, ctx: &mut TxContext) {
        lock_coin::unlock_wrapper<LWA>( locked_coin, clock, ctx);
    }

    // Deleting coins
    public entry fun burn(treasury_cap: &mut TreasuryCap<LWA>, coin: Coin<LWA>) {
        coin::burn(treasury_cap, coin);
    }

    
    // ===== Move code consultation =====
    // treasury_cap와 같이 사용되지 않는 Param이 있다면 _를 사용하여 표기합니다.

    // Activating/Deactivating voting
    #[allow(unused_variable)]
    public entry fun enable_vote(treasury_cap: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, is_enable: bool, vote_start_ts: u64, vote_end_ts: u64, 
                                min_voting_count: u64, passing_threshold: u64, _ctx: &mut TxContext) {
        // If already activated, cannot change the status.
        assert!(vote::is_votestatus_enable(&vote_board.status)==false, ErrAlreadyVotingEnable);
        // Check max value for passing_threshold 
        assert!(passing_threshold <= 100, ErrInvalidpassingThreshold);
        // Validate start and end time
        assert!(vote_start_ts < vote_end_ts, ErrInvalidStartEndTimestamp);
        vote::votestatus_enable( &mut vote_board.status, is_enable, vote_start_ts, vote_end_ts, min_voting_count, passing_threshold);
    }

    /// ===== Move code consultation =====
    /// entry 키워드는 필요 없는것으로 보입니다. 

    // Voting
    public entry fun vote(vote_board: &mut VoteBoard, coin: &Coin<LWA>, clock_vote: &clock::Clock, is_agree: bool, ctx: &mut TxContext) {
        // Check if voting is enabled
        assert!(vote::is_votestatus_enable(&vote_board.status)==true, ErrNotVotingEnable);

        // Check if it's voting period
        assert!(vote::votestatus_period_check(&vote_board.status, clock_vote) == true, ErrNotVotePeriod);

        // Check if the sender has already voted
        assert!(!vote::is_voted(&vote_board.participants, tx_context::sender(ctx)), ErrAlreadyVoters);

        // Check if the sender is a LWA holder
        assert!(coin::value<LWA>(coin) != 0, ErrNotHolder );

        // Vote
        // Later, the voting evidence will be counted by the vote counters' wallets to confirm the voting result.
        vote::voting(&mut vote_board.participants,tx_context::sender(ctx), clock_vote, is_agree );

        // Record the user's vote and issue an NFT to indicate the vote.
        let voting_evidence = vote::make_VotingEvidence(ctx, is_agree);
        transfer::public_transfer(voting_evidence, tx_context::sender(ctx));
    }

    /// ===== Move code consultation =====
    /// entry 키워드는 필요 없는것으로 보입니다. 

    // Vote counting
    public entry fun vote_counting(treasury_cap: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, clock_vote: &clock::Clock, amount: u64,  ctx: &mut TxContext) {
        // Check if vote counting is possible
        assert!(vote_board.result == VOTE_NONE, ErrVotingAlreadyClosed );
        // Check if it's the counting period and if the minimum voters requirement is met
        let (is_valid_period, is_valid_total_cnt) = vote::votestatus_countable(&vote_board.status, &vote_board.participants, clock_vote);
        assert!(is_valid_period==true, ErrNotVoteCountingPeriod);

        if (is_valid_total_cnt == true){
            // If more than 50% of total voters, pass the vote (minting), otherwise fail
            let (_agree_cnt, _disagree_cnt, _total_cnt, result) = vote::vote_counting(&vote_board.participants, &vote_board.status);

            if ( result == true ) {
                // Minting after agreement
                vote_board.result = VOTE_AGREE;
                mint(treasury_cap, amount, tx_context::sender(ctx), ctx);
            }else{
                // Opposition passed    
                vote_board.result = VOTE_DISAGREE;
            }
        }else{
            // Fail due to insufficient voters    
            vote_board.result = VOTE_INVALIDITY;
        }
    }

    /// ===== Move code consultation =====
    /// entry 키워드는 필요 없는것으로 보입니다. 

    // Resetting the completed vote counting so that it can be voted again next time
    public entry fun vote_reset(_treasury_cap: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, _ctx: &mut TxContext) {
        // Check if voting is enabled
        assert!(vote::is_votestatus_enable(&vote_board.status)==true, ErrNotVotingEnable);
        // Check if it's a vote that has been counted
        assert!(vote_board.result != VOTE_NONE, ErrAlreayReset );
        // Reset voting data
        vote_board.status = vote::empty_status();
        vote_board.participants = vote::empty_participants();
        vote_board.result = VOTE_NONE;
    }

    // public entry fun test_transfer(my_coin: Coin<LWA>, amount: u64, ctx: &mut TxContext) {
    //     let splitcoin = coin::split(&mut my_coin, 1, ctx);

    //     transfer::public_transfer(splitcoin, tx_context::sender(ctx));
    //     pay::keep(my_coin, ctx);
    // }
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(LWA {}, ctx)
    }
}