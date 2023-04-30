module vault::deposit_core {
    // Part 1: imports
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    // Use this dependency to get a type wrapper for UTF-8 strings
    use std::string::{Self, String};
    use sui::coin::{Self, Coin};
    use std::vector;
    use std::debug;

    /// User doesn't have enough coins
    const ENotEnoughMoney: u64 = 1;
    const EOutOfService: u64 = 2;

    struct Pool<phantom T, phantom U> has key, store {
        id: UID,
        sui_balance: Balance<T>,
        token_balance: Balance<U>,
        buy_orders_list: vector<OrderObject<U>>,
        sell_orders_list: vector<OrderObject<T>>,
    }

    struct OrderObject<phantom T> has store, drop {
        order_owner: address,
        price: u64,
        amount_escrowed: u64,
    }

    struct PoolOwnership has key, store{
        id: UID
    }

    // initialize
    fun init(ctx: &mut TxContext) {
        transfer::transfer(PoolOwnership{id: object::new(ctx)}, tx_context::sender(ctx));
    }

    public entry fun create_pool<T, U>(_:&PoolOwnership, ctx: &mut TxContext){
        transfer::share_object(Pool<T, U>{
            id: object::new(ctx),
            token_balance: balance::zero(),
            sui_balance: balance::zero(),
            buy_orders_list: vector::empty<OrderObject<U>>(),
            sell_orders_list: vector::empty<OrderObject<T>>()
        });
    }

    public fun create_order_object<T>(price: u64,amount:u64, ctx: &mut TxContext):OrderObject<T>{
        OrderObject{
            order_owner: tx_context::sender(ctx),
            price,
            amount_escrowed: amount
        }
    }

    public fun pool_token_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<U>(&self.token_balance)
    }

    public fun pool_sui_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<T>(&self.sui_balance)
    }

    fun min(a:u64, b:u64):u64{
        if (a <= b) {
           return  a
        };
        return b
    }

    public entry fun create_buy_order<T, U>(pool: &mut Pool<T, U>, sui_wallet: &mut Coin<T>, token_wallet: &mut Coin<U>,sui_amount: u64, bid_price: u64, ctx: &mut TxContext){
        // make sure we have enough money to deposit!
        assert!(coin::value<T>(sui_wallet) >= sui_amount, ENotEnoughMoney);
        let vec_len = vector::length<OrderObject<T>>(&pool.sell_orders_list);

        if (vec_len > 0 && vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).price <= bid_price) {
            let availableCoins = pool_token_balance(pool);

            let order_object = vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0);
            let transaction_asset_value = min(sui_amount/order_object.price, order_object.amount_escrowed);
            let transaction_token_value = min(sui_amount,order_object.price*order_object.amount_escrowed);
            debug::print(&transaction_asset_value);
            debug::print(&transaction_token_value);
            assert!(availableCoins >= transaction_asset_value, ENotEnoughMoney);

            let wallet_balance = coin::split(sui_wallet, transaction_token_value, ctx);
            transfer::public_transfer(wallet_balance, order_object.order_owner);

            // split money from vault's token balance.
            let token_balance = coin::balance_mut(token_wallet);
            let token_payment = balance::split(&mut pool.token_balance, transaction_asset_value);
            balance::join<U>(token_balance, token_payment);

            let remainder_buy_balance = sui_amount - transaction_token_value;
            let remainder_token_balance = order_object.amount_escrowed - transaction_asset_value;
            debug::print(&remainder_buy_balance);
            debug::print(&remainder_token_balance);
            if (remainder_buy_balance > 0) {
                create_buy_order(pool, sui_wallet, token_wallet, remainder_buy_balance, bid_price, ctx);
            };
            if (remainder_token_balance > 0) {
                vector::borrow_mut<OrderObject<T>>(&mut pool.sell_orders_list, 0).amount_escrowed = remainder_token_balance;
            } else {
                vector::remove<OrderObject<T>>(&mut pool.sell_orders_list, 0);
            }
        } else {
            // get balance reference
            let wallet_balance = coin::balance_mut(sui_wallet);

            // get money from balance
            let payment = balance::split(wallet_balance, sui_amount);

            // add to pool's balance.
            balance::join<T>(&mut pool.sui_balance, payment);
            let vec_len = vector::length<OrderObject<U>>(&pool.buy_orders_list);
            insert_buy_order_object(pool, bid_price, sui_amount,vec_len, ctx);
        }
    }

    public entry fun create_sell_order<T, U>(pool: &mut Pool<T, U>, sui_wallet: &mut Coin<T>, token_wallet: &mut Coin<U>, token_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value<U>(token_wallet) >= token_amount, ENotEnoughMoney);
        // get balance reference

        let vec_len = vector::length<OrderObject<U>>(&pool.buy_orders_list);
        if (vec_len > 0 && vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).price >= ask_price) {
            let availableCoins = pool_sui_balance(pool);

            let order_object = vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0);

            let transaction_asset_value = min(token_amount, order_object.amount_escrowed/order_object.price);
            let transaction_token_value = min(token_amount * order_object.price, order_object.amount_escrowed);

            assert!(availableCoins >= transaction_token_value, ENotEnoughMoney);

            let wallet_balance = coin::balance_mut(sui_wallet);
            let payment = balance::split(&mut pool.sui_balance, transaction_token_value);
            balance::join(wallet_balance, payment);

            let coin_object = coin::split(token_wallet, transaction_asset_value, ctx);
            transfer::public_transfer(coin_object, order_object.order_owner);

            let remainder_buy_balance = order_object.amount_escrowed - transaction_token_value;
            let remainder_token_balance = token_amount - transaction_asset_value;

            if (remainder_token_balance > 0) {
                create_sell_order(pool, sui_wallet, token_wallet, remainder_token_balance, ask_price, ctx);
            };
            if (remainder_buy_balance > 0) {
                vector::borrow_mut<OrderObject<U>>(&mut pool.buy_orders_list, 0).amount_escrowed = remainder_buy_balance;
            } else {
               vector::remove<OrderObject<U>>(&mut pool.buy_orders_list, 0);
            }
        } else {
            let token_balance = coin::balance_mut(token_wallet);
            // get money from balance
            let token_payment = balance::split(token_balance, token_amount);
            balance::join<U>(&mut pool.token_balance, token_payment);

            let vec_len = vector::length<OrderObject<T>>(&pool.sell_orders_list);
            insert_sell_order_object(pool, ask_price, token_amount, vec_len, ctx);
        }


        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
    }

    fun insert_buy_order_object<T, U>(pool: &mut Pool<T, U>, bid_price: u64, amount:u64, vec_len:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(bid_price, amount, ctx);
        vector::push_back<OrderObject<U>>(&mut pool.buy_orders_list, order_object);

        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<U>>(&pool.buy_orders_list, last).price > vector::borrow<OrderObject<U>>(&pool.buy_orders_list, second_last).price) {
                    vector::swap<OrderObject<U>>(&mut pool.buy_orders_list, last, second_last);
                    
                    last = second_last;
                    second_last = second_last - 1;
                }else{break}
            }
        }
    } 

    fun insert_sell_order_object<T, U>(pool: &mut Pool<T, U>, ask_price: u64, amount:u64, vec_len:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(ask_price, amount, ctx);
        vector::push_back<OrderObject<T>>(&mut pool.sell_orders_list, order_object);

        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<T>>(&pool.sell_orders_list, last).price < vector::borrow<OrderObject<T>>(&pool.sell_orders_list, second_last).price) {
                    vector::swap<OrderObject<T>>(&mut pool.sell_orders_list, last, second_last);
                    
                    last = second_last;
                    second_last = second_last - 1;
                }else{break}
            }
        }
    } 

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}