// Copyright (c) PDX, Inc.
// SPDX-License-Identifier: Apache-2.0

module lumiwave::vote {
    use std::vector;
    use sui::vec_map::{Self, VecMap};
    use std::string::{utf8, String};
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::clock::{Self};
    use sui::url::{Self, Url};

    // 투표 상태 정보
    struct VoteStatus has store, copy, drop {
        enable: bool, // 투표 활성화 여부
        start_ts: u64, // 투표 시작 시간 (ms)
        end_ts: u64, // 투표 종료 시간 (ms)
    }

    // 투표 참가자 정보
    struct Participant has store, copy, drop {
        addr: address, // 투표자 지갑 주소
        ts: u64, // 투표 참여 시간
        is_agree: bool, // 창성, 반대
    }

    // 투표 참가자 확인용 NFT
    struct VotingEvidence has key, store {
        id: UID,
        name: String,
        description: String,
        project_url: Url,
        image_url: Url,
        creator: String,
        is_agree: bool,
    }

    public fun empty_status(): VoteStatus{
        VoteStatus{
            enable: false, 
            start_ts: 0,
            end_ts: 0,
        }
    }

    public fun empty_participants() :VecMap<address, Participant> {
        vec_map::empty<address, Participant>()
    } 

    // 투표 확인 NFT 생성
    public fun make_VotingEvidence(ctx: &mut TxContext, is_agree: bool): VotingEvidence {
        VotingEvidence{
            id: object::new(ctx),
            name: utf8(b"minting vote"),
            description: utf8(b""),
            project_url: url::new_unsafe_from_bytes(b"https://inno.onbuff.com"),
            image_url: url::new_unsafe_from_bytes( b"https://onbufffile.blob.core.windows.net/inno/live/icon/LUMIWAVE_Primary_black.png"),
            creator: utf8(b""),
            is_agree,
        }
    }

    // === Public-View Functions ===
    // 투표 가능한 상태인지
    public fun is_votestatus_enable(vote_status: &VoteStatus): bool {  
        vote_status.enable
    } 

    // 투표 참여 여부
    public fun is_voted(participants: &VecMap<address, Participant>, participant: address): bool{
       vec_map::contains<address, Participant>(participants, &participant)
    }

    // 투표자 세부 정보
    public fun participant(participant: &Participant): (address, u64, bool) {
        (participant.addr, participant.ts, participant.is_agree)
    }

    // 투표 기간 체크
    public fun votestatus_period_check(vote_status: &mut VoteStatus, clock_vote: &clock::Clock): bool {
        let cur_ts = clock::timestamp_ms(clock_vote);
        if (cur_ts >= vote_status.start_ts && cur_ts <= vote_status.end_ts ) {
            true
        }else{
            false
        }
    }

    // 개표 가능 여부 체크
    public fun votestatus_countable(vote_status: &mut VoteStatus, participants: &VecMap<address, Participant>, clock_vote: &clock::Clock): (bool, bool) {
        // 투표 종료시간이 지났는지 체크, 전체 투표자수가 1천명 이상인지 체크
        ( vote_status.end_ts < clock::timestamp_ms(clock_vote), vec_map::size(participants) >= 1000 )
    }

    // 투표 결과 확인
    public fun vote_counting(participants: &VecMap<address, Participant>): (u64, u64, u64, bool) {
        let (_, participants) = vec_map::into_keys_values(*participants);
        let i: u64 = 0;
        let agree_cnt : u64 = 0;
        let disagree_cnt: u64 = 0;
        while( i < vector::length(&participants)) {
            let participant = vector::borrow(&participants, i);
            if ( participant.is_agree == true ) {
                agree_cnt = agree_cnt + 1;
            }else{
                disagree_cnt = disagree_cnt + 1;
            };
            i = i + 1;
        };

        let result: bool = false;
        if ( agree_cnt * 2 < i ) { // 50 % 넘어야 찬성 통과
            // 반대 통과
            result = false;
        }else{
            // 찬성 통과
            result = true;
        };

        (agree_cnt, disagree_cnt, i, result)  // 찬성 수, 반대 수, 전체 투표자 수, 투표 결과
    }

    // === Public-Mutative Functions ===
    // 투표 참여
    public fun voting(participants: &mut VecMap<address, Participant>, participant: address, clock_vote: &clock::Clock, is_agree: bool) {
        let newParticipant = Participant{
            addr: participant,
            ts: clock::timestamp_ms(clock_vote),
            is_agree,
        };
        vec_map::insert<address, Participant>(participants, participant, newParticipant);
    }

    // 투표 활성화
    public fun votestatus_enable(vote_status: &mut VoteStatus, enable: bool, vote_start_ts: u64, vote_end_ts: u64) {  
        vote_status.enable = enable;
        vote_status.start_ts = vote_start_ts;
        vote_status.end_ts = vote_end_ts;
    } 
}