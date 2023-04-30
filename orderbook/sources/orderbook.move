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

        // get balance reference
        let wallet_balance = coin::balance_mut(sui_wallet);

        // get money from balance
        let payment = balance::split(wallet_balance, sui_amount);
        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
        balance::join<T>(&mut pool.sui_balance, payment);


        if (vector::length<OrderObject<T>>(&pool.sell_orders_list) > 0 && vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price <= ask_price) {
            let availableCoins = pool_token_balance(pool);
            assert!(availableCoins > sui_amount/vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price, ENotEnoughMoney);

            let balance = coin::balance_mut(token_wallet);

            // split money from vault's balance.
            let payment = balance::split(&mut pool.token_balance, sui_amount/vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).ask_price);
            balance::join<U>(balance, payment);

            let sui_payment = balance::split(&mut pool.sui_balance, sui_amount);
            balance::join(&mut vector::borrow_mut<OrderObject<T>>(&mut pool.sell_orders_list, 0).receiver_balance, sui_payment);
            // execute the transaction
        } else {
            let order_object = create_order_object(ask_price, ctx);
            vector::push_back<OrderObject<U>>(&mut pool.buy_orders_list, order_object);
        }
    }

    public entry fun create_sell_order<T, U>(pool: &mut Pool<T, U>, sui_wallet: &mut Coin<T>, token_wallet: &mut Coin<U>, token_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value<U>(token_wallet) >= token_amount, ENotEnoughMoney);
        // get balance reference
        let wallet_balance = coin::balance_mut(token_wallet);

        // get money from balance
        let payment = balance::split(wallet_balance, token_amount);
        balance::join<U>(&mut pool.token_balance, payment);

        if (vector::length<OrderObject<U>>(&pool.buy_orders_list) > 0 && vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price >= ask_price) {
            let availableCoins = pool_sui_balance(pool);
            assert!(availableCoins > token_amount * vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price, ENotEnoughMoney);

            let balance = coin::balance_mut(sui_wallet);

            // split money from vault's balance.
            let payment = balance::split(&mut pool.sui_balance, token_amount * vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).ask_price);
            // execute the transaction
            balance::join(balance, payment);


            let token_payment = balance::split(&mut pool.token_balance, token_amount);
            balance::join(&mut vector::borrow_mut<OrderObject<U>>(&mut pool.buy_orders_list, 0).receiver_balance, token_payment);

        } else {
            let order_object = create_order_object(ask_price, ctx);
            vector::push_back<OrderObject<T>>(&mut pool.sell_orders_list, order_object);
        }


        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
    }


    /* A function for admins to deposit money to the pool so it can still function!  */
    // public entry fun depositToOrderObject(_:&PoolOwnership, pool :&mut OrderObject<T>, amount: u64, payment: &mut Coin<SUI>){

    //     let availableCoins = coin::value(payment);
    //     assert!(availableCoins > amount, ENotEnoughMoney);

    //     let balance = coin::balance_mut(payment);

    //     let payment = balance::split(balance, amount);
    //     balance::join(&mut pool.pool_balance, payment);
    // }

    /*
       A function for admins to get their profits.
    */
    // public entry fun withdraw(_:&PoolOwnership, pool: &mut OrderObject<T>, amount: u64, wallet: &mut Coin<SUI>){

    //     let availableCoins = pool_balance(pool);
    //     assert!(availableCoins > amount, ENotEnoughMoney);

    //     let balance = coin::balance_mut(wallet);

    //     // split money from pool's balance.
    //     let payment = balance::split(&mut pool.pool_balance, amount);

    //     // execute the transaction
    //     balance::join(balance, payment);
    // }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}