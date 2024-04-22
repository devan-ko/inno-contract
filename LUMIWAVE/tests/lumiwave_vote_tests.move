#[test_only]
module lumiwave::LWA_vote_tests {
    use sui::test_scenario;
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock;
    use sui::transfer;
    use sui::vec_map::{Self};
    //use sui::pay;
    //use std::string::{String};

    use lumiwave::LWA::{Self, LWA};
    use lumiwave::vote::{Self, VotingEvidence};

    #[test]
    public fun test_vote() {
        let user = @0xA;
        let user2 = @0xB;
        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            LWA::init_for_testing(ctx);
        };
        test_scenario::next_tx(scenario, user);
        let coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
        let treasury_cap = test_scenario::take_from_sender<TreasuryCap<LWA>>(scenario);
        let vote_board = test_scenario::take_shared<LWA::VoteBoard>(scenario);
        let vote_start_ts = 1713760742000;
        let vote_end_ts = vote_start_ts + 1800000;
        // vote enabel test
        {
            LWA::enable_vote(&mut treasury_cap, &mut vote_board, true, vote_start_ts, vote_end_ts /* 30 min*/, test_scenario::ctx(scenario) );
            assert!(LWA::is_enable_vote(&mut vote_board) == true, 1);
        };

        //voting #1 test
        {
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut clock, vote_start_ts + 1);
            LWA::vote(&mut vote_board, &coin, &clock, true, test_scenario::ctx(scenario) );
            test_scenario::next_tx(scenario, user);
            {
                // voting #1 evidence
                let voting1_evidence = test_scenario::take_from_sender<VotingEvidence>(scenario);
                let(_, _, _, _, _, is_agree) = vote::voting_evidence_detail(&voting1_evidence);
                assert!(is_agree == true, 1);
                assert!(LWA::is_voted(&mut vote_board, user) == true, 1);
                test_scenario::return_to_sender( scenario, voting1_evidence);
            };
            clock::destroy_for_testing(clock);
        };

        //voting #2 test
        {
            let splitcoin = coin::split(&mut coin, 1, test_scenario::ctx(scenario));
            transfer::public_transfer(splitcoin, user2);
            test_scenario::next_tx(scenario, user2);
            {
                let clock = clock::create_for_testing(test_scenario::ctx(scenario));
                clock::increment_for_testing(&mut clock, vote_start_ts + 1);

                let user2_coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
                LWA::vote(&mut vote_board, &user2_coin, &clock, true, test_scenario::ctx(scenario) );

                // voting #2 evidence
                test_scenario::next_tx(scenario, user2);
                {
                    let voting2_evidence = test_scenario::take_from_sender<VotingEvidence>(scenario);
                    let(_, _, _, _, _, is_agree) = vote::voting_evidence_detail(&voting2_evidence);
                    assert!(is_agree == true, 1);
                    assert!(LWA::is_voted(&mut vote_board, user2) == true, 1);
                    test_scenario::return_to_sender( scenario, voting2_evidence);
                };
                clock::destroy_for_testing(clock);
                test_scenario::return_to_sender(scenario, user2_coin);  
            };
        };

        test_scenario::next_tx(scenario, user);
        // vote counting
        {
            let ( _, participants, _) = LWA::vote_detail(&vote_board);
            assert!( vec_map::size(&participants) == 2, 1); // Check the total number of voting participants

            let new_minting_amount = 10;
            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut clock, vote_end_ts + 1);
            LWA::vote_counting(&mut treasury_cap, &mut vote_board, &clock, new_minting_amount, test_scenario::ctx(scenario));
            let ( _, _, _result) = LWA::vote_detail(&vote_board);
            //End with invalid votes due to insufficient number of participants
            {
                assert!( _result == 3 /* LWAP::VOTE_INVALIDITY */, 1); 
            };
            // Test and validate additional meetings when voting ends in favor
            {
                // test_scenario::next_tx(scenario, user);
                // let minted_coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
                // assert!(coin::value<LWA>(&minted_coin) == new_minting_amount, 1);
                // test_scenario::return_to_sender(scenario, minted_coin);
            };

            clock::destroy_for_testing(clock);
        };

        // vote reset
        {
            LWA::vote_reset(&mut treasury_cap, &mut vote_board, test_scenario::ctx(scenario));
        };

        test_scenario::return_to_sender(scenario, coin);
        test_scenario::return_to_sender(scenario, treasury_cap);
        test_scenario::return_shared(vote_board);
        test_scenario::end(scenario_val);
    }
}