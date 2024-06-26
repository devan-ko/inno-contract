// Copyright (c) PDX, Inc.
// SPDX-License-Identifier: Apache-2.0

module lumiwave::lock_coin{
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self};   
    use sui::coin;

    friend lumiwave::LWA;
    struct LockedCoin<phantom T> has key {
        id: UID,
        lock_ts: u64,
        unlock_ts: u64,
        lock_blance: Balance<T>,
    }

    // === Public-View Functions ===
    public fun detail<T>(locked_coin: &LockedCoin<T>): (u64, u64, u64) {
        (locked_coin.lock_ts, locked_coin.unlock_ts, balance::value(&locked_coin.lock_blance))
    }

    // === Public-Mutative Functions ===
    // Lock coins and transfer
    public(friend) fun make_lock_coin<T>( recipient: address, lock_ts: u64, unlock_ts: u64, balance: Balance<T>, ctx: &mut TxContext ) {
        let lock_coin = LockedCoin{
            id: object::new(ctx),
            lock_ts,
            unlock_ts,
            lock_blance: balance,
        };

        transfer::transfer(lock_coin, recipient);
    }

    #[allow(lint(self_transfer), unused_variable)]
    public(friend) fun unlock_wrapper<T> ( locked_coin: LockedCoin<T>, cur_clock: &clock::Clock, ctx: &mut TxContext ){
        let LockedCoin { id, lock_ts, unlock_ts, lock_blance } = locked_coin;

        // Check time
        assert!(unlock_ts < clock::timestamp_ms(cur_clock), 111);

        object::delete(id);

        let coin = coin::from_balance(lock_blance, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }
}