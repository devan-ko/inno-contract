#[test_only]
module lumiwave::LWA_coin_tests {
    use sui::test_scenario;
    use sui::coin::{Self, Coin, TreasuryCap, DenyCap};
    use sui::deny_list;
    use sui::clock;
    use lumiwave::lock_coin::{Self};
    use lumiwave::LWA::{Self, LWA};

    // Additional minting test after initial minting
    #[test]
    public fun test_mint() {
        let user = @0xA;
        let amount = 770075466000000000;
        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            LWA::init_for_testing(ctx);
        };
        test_scenario::next_tx(scenario, user);
        {
            let coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
            assert!(coin::value(&coin) == amount, 1);

            let treasury_cap = test_scenario::take_from_sender<TreasuryCap<LWA>>(scenario);
            assert!(coin::total_supply<LWA>(&treasury_cap) == amount, 1);

            let deny_cap = test_scenario::take_from_sender<DenyCap<LWA>>(scenario);

            // minting
            LWA::mint(&mut treasury_cap, 1000, user, test_scenario::ctx(scenario));
            amount = amount + 1000;
            assert!(coin::total_supply<LWA>(&treasury_cap) == amount, 1);
            // Create Forced Error
            // LWA::mint(&mut treasury_cap, amount, user, test_scenario::ctx(scenario)); 

            test_scenario::return_to_sender(scenario, coin);
            test_scenario::return_to_sender(scenario, treasury_cap);
            test_scenario::return_to_sender(scenario, deny_cap);
        };
        test_scenario::end(scenario_val);
    }

    // lock transfer test
    #[test]
    public fun test_lock_transfer() {
        let user = @0xA;
        let receive_user = @0xB;
        let amount = 770075466000000000;
        let scenario_val = test_scenario::begin(user);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            LWA::init_for_testing(ctx);
        };
        test_scenario::next_tx(scenario, user);
        {
            let coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
            assert!(coin::value(&coin) == amount, 1);
            let treasury_cap = test_scenario::take_from_sender<TreasuryCap<LWA>>(scenario);
            assert!(coin::total_supply<LWA>(&treasury_cap) == amount, 1);

            let clock = clock::create_for_testing(test_scenario::ctx(scenario));
            // lock transfer
            LWA::lock_coin_transfer( &mut treasury_cap, coin, receive_user, 1000, 1713524421000, &clock, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, treasury_cap);
            clock::destroy_for_testing(clock);
            // unlock 
            test_scenario::next_tx(scenario, receive_user);
            let lock_object = test_scenario::take_from_sender<lock_coin::LockedCoin<LWA>>(scenario);
            let ( _lock_ts, unlock_ts, lock_blance ) = lock_coin::detail(&lock_object);
            assert!(lock_blance == 1000, 1);
            assert!(unlock_ts == 1713524421000, 1);

            let end_clock = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut end_clock, 1713524421000 + 10);
            LWA::unlock_coin(lock_object, &end_clock, test_scenario::ctx(scenario));
            test_scenario::next_tx(scenario, receive_user);
            let unlock_coin = test_scenario::take_from_sender<Coin<LWA>>(scenario);
            assert!(coin::value<LWA>(&unlock_coin) == 1000, 1); // Check the quantity after unlocking
            test_scenario::return_to_sender(scenario, unlock_coin);
            clock::destroy_for_testing(end_clock);
        };
        test_scenario::end(scenario_val);
    }

    // Add specific wallet deny, remove test
    #[test]
    public fun test_deny_wallet() {
        let user = @0xA;
        let scenario_val = test_scenario::begin(@0);
        let scenario = &mut scenario_val;
        deny_list::create_for_test(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, user);
        {
            let ctx = test_scenario::ctx(scenario);
            LWA::init_for_testing(ctx);
        };
        test_scenario::next_tx(scenario, user);
        {
            let deny_list: deny_list::DenyList = test_scenario::take_shared(scenario);
            let deny_cap = test_scenario::take_from_sender<DenyCap<LWA>>(scenario);
            // add test
            assert!(!coin::deny_list_contains<LWA>(&deny_list, @0xB), 0);
            LWA::add_deny(&mut deny_list, &mut deny_cap, @0xB, test_scenario::ctx(scenario));
            assert!(coin::deny_list_contains<LWA>(&deny_list, @0xB), 0);
            // remove test
            LWA::remove_deny(&mut deny_list, &mut deny_cap, @0xB, test_scenario::ctx(scenario));
            assert!(!coin::deny_list_contains<LWA>(&deny_list, @0xB), 0);

            test_scenario::return_to_sender(scenario, deny_cap);
            test_scenario::return_shared(deny_list);
        };
        test_scenario::end(scenario_val);
    }
}