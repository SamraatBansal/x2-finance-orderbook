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

    struct Pool<phantom T> has key, store {
        id: UID,
        token_balance: Balance<T>,
        sui_balance: Balance<T>,
        buy_orders_list: vector<OrderObject>,
        sell_orders_list: vector<OrderObject>,
    }

    struct OrderObject has store {
        id: UID,
        order_owner: address,
        ask_price: u64,
    }

    struct PoolOwnership has key, store{
        id: UID
    }

    // initialize
    fun init(ctx: &mut TxContext) {
        transfer::transfer(PoolOwnership{id: object::new(ctx)}, tx_context::sender(ctx));
    }

    public entry fun create_pool<T>(_:&PoolOwnership, ctx: &mut TxContext){
        transfer::share_object(Pool<T>{
            id: object::new(ctx),
            token_balance: balance::zero(),
            sui_balance: balance::zero(),
            buy_orders_list: vector::empty<OrderObject>(),
            sell_orders_list: vector::empty<OrderObject>()
        });
    }

    public fun create_order_object(ask_price: u64, ctx: &mut TxContext):OrderObject{
        OrderObject{
            id: object::new(ctx),
            order_owner: tx_context::sender(ctx),
            ask_price,
        }
    }

    // public fun min_deposit<T>(self: &OrderObject<T>): u64 {
    //     self.min_deposit
    // }

    // public fun pool_balance<T>(self:  &OrderObject<T>): u64{
    //    balance::value<T>(&self.pool_balance)
    // }

    public entry fun create_buy_order<T>(pool: &mut Pool<T>, wallet: &mut Coin<T>, sui_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value(wallet) >= sui_amount, ENotEnoughMoney);
        let order_object = create_order_object(ask_price, ctx);
        // get balance reference
        let wallet_balance = coin::balance_mut(wallet);

        // get money from balance
        let payment = balance::split(wallet_balance, sui_amount);
        vector::push_back<OrderObject>(&mut pool.buy_orders_list, order_object);

        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
        balance::join<T>(&mut pool.sui_balance, payment);
    }

    public entry fun create_sell_order<T>(pool: &mut Pool<T>, wallet: &mut Coin<T>, token_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough money to deposit!
        assert!(coin::value(wallet) >= token_amount, ENotEnoughMoney);
        let order_object = create_order_object(ask_price, ctx);
        // get balance reference
        let wallet_balance = coin::balance_mut(wallet);

        // get money from balance
        let payment = balance::split(wallet_balance, token_amount);
        vector::push_back<OrderObject>(&mut pool.sell_orders_list, order_object);

        // let pool_buy_orders_list = vector::borrow_mut(&mut pool.) 
        // add to pool's balance.
        balance::join<T>(&mut pool.token_balance, payment);
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