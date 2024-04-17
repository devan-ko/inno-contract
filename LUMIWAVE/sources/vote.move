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

    // Create voting confirmation NFT
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
    // Check if voting is enabled
    public fun is_votestatus_enable(vote_status: &VoteStatus): bool {  
        vote_status.enable
    } 

    // Check voting participation
    public fun is_voted(participants: &VecMap<address, Participant>, participant: address): bool{
       vec_map::contains<address, Participant>(participants, &participant)
    }

    // Details of voters
    public fun participant(participant: &Participant): (address, u64, bool) {
        (participant.addr, participant.ts, participant.is_agree)
    }

    // Check voting period
    public fun votestatus_period_check(vote_status: &mut VoteStatus, clock_vote: &clock::Clock): bool {
        let cur_ts = clock::timestamp_ms(clock_vote);
        if (cur_ts >= vote_status.start_ts && cur_ts <= vote_status.end_ts ) {
            true
        }else{
            false
        }
    }

    // Check if voting is countable
    public fun votestatus_countable(vote_status: &mut VoteStatus, participants: &VecMap<address, Participant>, clock_vote: &clock::Clock): (bool, bool) {
        // Check if the voting end time has passed, and if the total number of voters is over 1,000
        ( vote_status.end_ts < clock::timestamp_ms(clock_vote), vec_map::size(participants) >= 1000 )
    }

    // Check voting results
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
        if ( agree_cnt * 2 < i ) { // Need more than 50% for agreement
            // Opposition passed
            result = false;
        }else{
            // Agreement passed
            result = true;
        };

        (agree_cnt, disagree_cnt, i, result)  // Number of agreements, number of disagreements, total number of voters, voting result
    }

    // === Public-Mutative Functions ===
    // Participate in voting
    public fun voting(participants: &mut VecMap<address, Participant>, participant: address, clock_vote: &clock::Clock, is_agree: bool) {
        let newParticipant = Participant{
            addr: participant,
            ts: clock::timestamp_ms(clock_vote),
            is_agree,
        };
        vec_map::insert<address, Participant>(participants, participant, newParticipant);
    }

    // Enable voting
    public fun votestatus_enable(vote_status: &mut VoteStatus, enable: bool, vote_start_ts: u64, vote_end_ts: u64) {  
        vote_status.enable = enable;
        vote_status.start_ts = vote_start_ts;
        vote_status.end_ts = vote_end_ts;
    } 
}