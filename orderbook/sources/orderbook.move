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

    struct OrderObject<phantom T> has store {
        id: UID,
        order_owner: address,
        receiver_balance: Balance<T>,
        ask_price: u64,
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

    public fun create_order_object<T>(ask_price: u64, ctx: &mut TxContext):OrderObject<T>{
        OrderObject{
            id: object::new(ctx),
            order_owner: tx_context::sender(ctx),
            receiver_balance: balance::zero(),
            ask_price,
        }
    }

    // public fun min_deposit<T>(self: &OrderObject<T>): u64 {
    //     self.min_deposit
    // }

    public fun pool_token_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<U>(&self.token_balance)
    }

    public fun pool_sui_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<T>(&self.sui_balance)
    }

    public entry fun create_buy_order<T, U>(pool: &mut Pool<T, U>, sui_wallet: &mut Coin<T>, token_wallet: &mut Coin<U>,sui_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value<T>(sui_wallet) >= sui_amount, ENotEnoughMoney);

        let vec_len = vector::length<OrderObject<T>>(&pool.sell_orders_list);

        if (vec_len > 0 && vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price <= ask_price) {
            let availableCoins = pool_token_balance(pool);
            assert!(availableCoins > sui_amount/vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price, ENotEnoughMoney);

            let wallet_balance = coin::split(sui_wallet, sui_amount, ctx);
            transfer::public_transfer(wallet_balance, vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).order_owner);

            // split money from vault's token balance.
            let token_balance = coin::balance_mut(token_wallet);
            let token_payment = balance::split(&mut pool.token_balance, sui_amount/vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price);
            balance::join<U>(token_balance, token_payment);
        } else {
            // get balance reference
            let wallet_balance = coin::balance_mut(sui_wallet);

            // get money from balance
            let payment = balance::split(wallet_balance, sui_amount);

            // add to pool's balance.
            balance::join<T>(&mut pool.sui_balance, payment);
            let vec_len = vector::length<OrderObject<U>>(&pool.buy_orders_list);
            insert_buy_order_object(pool, ask_price, vec_len, ctx);
        }
    }

    public entry fun create_sell_order<T, U>(pool: &mut Pool<T, U>, sui_wallet: &mut Coin<T>, token_wallet: &mut Coin<U>, token_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value<U>(token_wallet) >= token_amount, ENotEnoughMoney);
        // get balance reference

        let vec_len = vector::length<OrderObject<U>>(&pool.buy_orders_list);
        if (vec_len > 0 && vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price >= ask_price) {
            let availableCoins = pool_sui_balance(pool);
            assert!(availableCoins >= token_amount * vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price, ENotEnoughMoney);

            let wallet_balance = coin::balance_mut(sui_wallet);
            let payment = balance::split(&mut pool.sui_balance, token_amount * vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price);
            balance::join(wallet_balance, payment);

            let coin_object = coin::split(token_wallet, token_amount, ctx);
            transfer::public_transfer(coin_object, vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).order_owner);

            let token_payment = balance::split(&mut pool.token_balance, token_amount);
            balance::join(&mut vector::borrow_mut<OrderObject<U>>(&mut pool.buy_orders_list, 0).receiver_balance, token_payment);

        } else {
            let token_balance = coin::balance_mut(token_wallet);
            // get money from balance
            let token_payment = balance::split(token_balance, token_amount);
            balance::join<U>(&mut pool.token_balance, token_payment);

            let vec_len = vector::length<OrderObject<T>>(&pool.sell_orders_list);
            insert_sell_order_object(pool, ask_price, vec_len, ctx);
        }


        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
    }

    fun insert_buy_order_object<T, U>(pool: &mut Pool<T, U>, ask_price: u64, vec_len:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(ask_price, ctx);
        vector::push_back<OrderObject<U>>(&mut pool.buy_orders_list, order_object);

        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<U>>(&pool.buy_orders_list, last).ask_price > vector::borrow<OrderObject<U>>(&pool.buy_orders_list, second_last).ask_price) {
                    vector::swap<OrderObject<U>>(&mut pool.buy_orders_list, last, second_last);
                    
                    last = second_last;
                    second_last = second_last - 1;
                }else{break}
            }
        }
    } 

    fun insert_sell_order_object<T, U>(pool: &mut Pool<T, U>, ask_price: u64, vec_len:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(ask_price, ctx);
        vector::push_back<OrderObject<T>>(&mut pool.sell_orders_list, order_object);

        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<T>>(&pool.sell_orders_list, last).ask_price < vector::borrow<OrderObject<T>>(&pool.sell_orders_list, second_last).ask_price) {
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