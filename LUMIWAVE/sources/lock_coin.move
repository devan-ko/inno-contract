// Copyright (c) PDX, Inc.
// SPDX-License-Identifier: Apache-2.0

module lumiwave::lock_coin{
    use sui::object::{Self, UID};
    use sui::balance::Balance;
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self};   
    use sui::coin;

    struct LockedCoin<phantom T> has key, store {
        id: UID,
        lock_ts: u64,
        unlock_ts: u64,
        lock_blance: Balance<T>,
    }

    // === Public-View Functions ===

    // === Public-Mutative Functions ===
    // coin lock을 걸고 전송
    public fun make_lock_coin<T>(recipient: address, lock_ts: u64, unlock_ts: u64, balance: Balance<T>, ctx: &mut TxContext ) {
        let lock_coin = LockedCoin{
            id: object::new(ctx),
            lock_ts,
            unlock_ts,
            lock_blance: balance,
        };

        transfer::transfer(lock_coin, recipient);
    }

    #[allow(unused_variable, lint(self_transfer))]
    public fun unlock_wrapper<T> (locked_coin: LockedCoin<T>, cur_clock: &clock::Clock, ctx: &mut TxContext ){
        let LockedCoin {id, lock_ts, unlock_ts, lock_blance} = locked_coin;

        // 시간 확인
        assert!(unlock_ts < clock::timestamp_ms(cur_clock), 111);

        object::delete(id);

        let coin = coin::from_balance(lock_blance, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }
}