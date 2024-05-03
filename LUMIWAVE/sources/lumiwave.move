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
           option::some(url::new_unsafe_from_bytes(b"https://innofile.blob.core.windows.net/inno/live/icon/LUMIWAVE_Primary_black.png")), 
           ctx);
        transfer::public_freeze_object(metadata);

        let owner = tx_context::sender(ctx);

        coin::mint_and_transfer<LWA>(&mut treasury_cap, 770075466000000000, owner, ctx);
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

    public fun vote_detail(vote_board: &VoteBoard): ( VoteStatus, VecMap<address, Participant>, u64) {
        ( vote_board.status, vote_board.participants, vote_board.result )
    }

    // === Public-Mutative Functions ===
    // Register wallets to deny
    public entry fun add_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext) {
        coin::deny_list_add<LWA>( denylist, deny_cap, recipient, ctx)
    }
    // Release denied wallets
    public entry fun remove_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext){
        coin::deny_list_remove<LWA>(denylist, deny_cap, recipient, ctx)
    }

    // Additional coin issuance
    public fun mint(treasury_cap: &mut TreasuryCap<LWA>, amount: u64, recipient: address, ctx: &mut TxContext) {
        let new_supply = coin::total_supply<LWA>(treasury_cap) + amount; // Calculate new supply in advance
        assert!(new_supply <= MaxSupply, ErrExceededMaxSupply); // Check if maximum supply is exceeded
        coin::mint_and_transfer(treasury_cap, amount, recipient, ctx);
    }

    // Locking coins & transfer
    #[allow(unused_variable)]
    public entry fun lock_coin_transfer( treasury_cap: &mut TreasuryCap<LWA>, my_coin: Coin<LWA>, 
                                   recipient: address, amount: u64, unlock_ts: u64, clock: &clock::Clock, ctx: &mut TxContext) {
        let new_coin = coin::split(&mut my_coin, amount, ctx);
        pay::keep(my_coin, ctx);

        lock_coin::make_lock_coin<LWA>(  recipient, clock::timestamp_ms(clock), unlock_ts, coin::into_balance(new_coin), ctx);
    }

    // Unlocking coins
    public entry fun unlock_coin( locked_coin: lock_coin::LockedCoin<LWA>, clock: &clock::Clock, ctx: &mut TxContext) {
        lock_coin::unlock_wrapper<LWA>( locked_coin, clock, ctx);
    }

    // Deleting coins
    public entry fun burn(treasury_cap: &mut TreasuryCap<LWA>, coin: Coin<LWA>) {
        coin::burn(treasury_cap, coin);
    }


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