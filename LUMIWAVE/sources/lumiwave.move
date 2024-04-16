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
    // use sui::bag::{Self, Bag};
    use sui::vec_map::VecMap;
    use sui::clock::Self;
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
    const VOTE_NONE: u64 = 0;       // 미개표, no vote count
    const VOTE_AGREE: u64 = 1;      // 찬성 개표, agreement
    const VOTE_DISAGREE: u64 = 2;   // 반대 개표, Opposition
    const VOTE_INVALIDITY: u64 = 3; // 투표 무효, Voting invalid

    // err code
    const ErrNotVotingEnable: u64 = 1; // 투표 가능한 상태가 아님. Not in a voting state
    const ErrAlreadyVoters: u64 = 2; // 이미 투표 했음. You've already voted
    const ErrNotHolder: u64 = 3; // 코인 홀더 아님. It's not a coin holder.
    const ErrExceededMaxSupply: u64 = 4; // 최대 공급량 초과. Maximum supply exceeded
    const ErrNotVotePeriod: u64 = 5; // 투표 기간이 아님. It's not a voting period
    const ErrVotingAlreadyClosed: u64 = 6;  // 이미 개표가 완료되었습니다. The counting of votes has already been completed.
    const ErrAlreayReset: u64 = 7;  // 이미 reset되어 있다. It is already reset.
    // const ErrAlreadyVotingEnable: u64 = 8; // 이미 투표가 활성화 되어 있다. Voting is already active.
    const ErrNotVoteCountingPeriod: u64 = 9; // 개표 가능한 기간이 아니다. It is not a countable period.
    const ErrInvalidStartEndTimestamp: u64 = 10; // 투표 시작 끝시간 유효성 검사 실패, Vote start end time validation failed
    // const ErrNotMinVoters: u64 = 11; // 최소 투표자 미달

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

        coin::mint_and_transfer<LWA>(&mut treasury_cap, 770075466000000000, tx_context::sender(ctx), ctx);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_transfer(deny_cap, tx_context::sender(ctx));

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

    // === Public-Mutative Functions ===
    // deny할 지갑 등록
    public entry fun add_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext) {
        coin::deny_list_add<LWA>( denylist, deny_cap, recipient, ctx)
    }
    // deny 지갑 해제
    public entry fun remove_deny(denylist: &mut DenyList, deny_cap: &mut DenyCap<LWA>, recipient: address, ctx: &mut TxContext){
        coin::deny_list_remove<LWA>(denylist, deny_cap, recipient, ctx)
    }


    // 코인 추가 발행
    public fun mint(treasury_cap: &mut TreasuryCap<LWA>, amount: u64, recipient: address, ctx: &mut TxContext) {
        let new_supply = coin::total_supply<LWA>(treasury_cap) + amount;         // 새로운 공급량 미리 계산
        assert!(new_supply <= MaxSupply, ErrExceededMaxSupply); // 최대 공급량이 초과되는지 체크
        coin::mint_and_transfer(treasury_cap, amount, recipient, ctx);
    }
    // 코인 lock & 전송
    public entry fun lock_coin_transfer(_: &mut TreasuryCap<LWA>, my_coin: Coin<LWA>, 
                                    recipient: address, amount: u64, unlock_ts: u64, clock: &clock::Clock, ctx: &mut TxContext) {
        let new_coin = coin::split(&mut my_coin, amount, ctx);
        pay::keep(my_coin, ctx);

        lock_coin::make_lock_coin<LWA>(  recipient, clock::timestamp_ms(clock), unlock_ts, coin::into_balance(new_coin), ctx);
    }
    // 코인 unlock
    public entry fun unlock_coin( locked_coin: lock_coin::LockedCoin<LWA>, clock: &clock::Clock, ctx: &mut TxContext) {
        lock_coin::unlock_wrapper<LWA>( locked_coin, clock, ctx);
    }
    // 코인 삭제
    public entry fun burn(treasury_cap: &mut TreasuryCap<LWA>, coin: Coin<LWA>) {
        coin::burn(treasury_cap, coin);
    }


    // 투표 활성화, 비활성화
    public entry fun enable_vote(_: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, is_enable: bool, vote_start_ts: u64, vote_end_ts: u64) {
        // 이미 활성화 되어 있다면 상태 변경을 할수 없다.
        assert!(vote::is_votestatus_enable(&vote_board.status)==false, ErrNotVotingEnable);
        // 시작, 끝 시간 유효성 검사
        assert!(vote_start_ts < vote_end_ts, ErrInvalidStartEndTimestamp);
        vote::votestatus_enable( &mut vote_board.status, is_enable, vote_start_ts, vote_end_ts);
    }
    // 투표 하기
    public entry fun vote(vote_board: &mut VoteBoard, coin: &Coin<LWA>, clock_vote: &clock::Clock, is_agree: bool, ctx: &mut TxContext) {
        // 투표 활상화 상태 체크
        assert!(vote::is_votestatus_enable(&vote_board.status)==true, ErrNotVotingEnable);

        // 투표 기간인지 체크
        assert!(vote::votestatus_period_check(&mut vote_board.status, clock_vote) == true, ErrNotVotePeriod);

        // 이미 투표한 사람인지 체크
        assert!(!vote::is_voted(&vote_board.participants, tx_context::sender(ctx)), ErrAlreadyVoters);

        // LWA 보유자 인지 체크
        assert!(coin::value<LWA>(coin) != 0, ErrNotHolder );

        // 투표 
        // 추후 개표자 지갑에 보유중인 투표지를 개표하여 투표 결과를 확인한다.
        vote::voting(&mut vote_board.participants,tx_context::sender(ctx), clock_vote, is_agree );

        // 유져의 투표를 기록하고 유져에게 투표했음을 NFT로 발행하여 준다.
        let voting_evidence = vote::make_VotingEvidence(ctx, is_agree);
        transfer::public_transfer(voting_evidence, tx_context::sender(ctx));
    }
    // 개표
    public entry fun vote_counting(treasury_cap: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, clock_vote: &clock::Clock, amount: u64,  ctx: &mut TxContext) {
        // 개표 가능성 체크
        assert!(vote_board.result == VOTE_NONE, ErrVotingAlreadyClosed );
        // 개표 가능한 시간인지 체크, 최소 투표자 체크
        let (is_valid_period, is_valid_total_cnt) = vote::votestatus_countable(&mut vote_board.status, &vote_board.participants, clock_vote);
        assert!(is_valid_period==true, ErrNotVoteCountingPeriod);

        if (is_valid_total_cnt == true){
            // 전체 투표자 중에 50% 이상이면 찬성 처리(minting), 이하면 반대 처리
            let (_agree_cnt, _disagree_cnt, _total_cnt, result) = vote::vote_counting(&vote_board.participants);

            if ( result == true ) {
                // 찬성 통과 후 추가 발행
                vote_board.result = VOTE_AGREE;
                mint(treasury_cap, amount, tx_context::sender(ctx), ctx);
            }else{
                // 반대 통과    
                vote_board.result = VOTE_DISAGREE;
            }
        }else{
            // 최소 투표인원 부족으로 반대 통과    
            vote_board.result = VOTE_INVALIDITY;
        }
    }

    // 완료된 개표 정보를 reset 해서 다음에 다시 투표 할수있도록 초기화
    public entry fun vote_reset(_treasury_cap: &mut TreasuryCap<LWA>, vote_board: &mut VoteBoard, _ctx: &mut TxContext) {
        // 투표 활상화 상태 체크
        assert!(vote::is_votestatus_enable(&vote_board.status)==true, ErrNotVotingEnable);
        // 개표가 이루어진 투표 인지 확인
        assert!(vote_board.result != VOTE_NONE, ErrAlreayReset );
        // 투표 데이터 초기화
        vote_board.status = vote::empty_status();
        vote_board.participants = vote::empty_participants();
        vote_board.result = VOTE_NONE;
    }

    // public entry fun test_transfer(my_coin: Coin<LWA>, amount: u64, ctx: &mut TxContext) {
    //     let splitcoin = coin::split(&mut my_coin, 1, ctx);

    //     transfer::public_transfer(splitcoin, tx_context::sender(ctx));
    //     pay::keep(my_coin, ctx);
    // }
}