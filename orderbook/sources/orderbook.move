module pool::deposit_core {
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


    struct Pool<phantom T> has key, store{
        id: UID,
        min_deposit: u64,
        pool_balance: Balance<T>
    }

    struct PoolOwnership has key, store{
        id: UID
    }

    // initialize
    fun init(ctx: &mut TxContext) {
        transfer::transfer(PoolOwnership{id: object::new(ctx)}, tx_context::sender(ctx));
    }

    public entry fun create_pool<T>(_:&PoolOwnership, min_deposit: u64, payment: &mut Coin<T>, ctx: &mut TxContext){
        transfer::share_object(Pool<T>{
            id: object::new(ctx),
            min_deposit,
            pool_balance: balance::zero()
        });
    }

    public fun min_deposit<T>(self: &Pool<T>): u64 {
        self.min_deposit
    }

    public fun pool_balance<T>(self:  &Pool<T>): u64{
       balance::value<T>(&self.pool_balance)
    }

    public entry fun deposit<T>(pool: &mut Pool<T>, wallet: &mut Coin<T>, amount: u64){

        // make sure we have enough money to deposit!
        assert!(coin::value(wallet) >= pool.min_deposit, ENotEnoughMoney);

        // get balance reference
        let wallet_balance = coin::balance_mut(wallet);

        // get money from balance
        let payment = balance::split(wallet_balance, amount);

        // add to pool's balance.
        balance::join<T>(&mut pool.pool_balance, payment);
    }


    /* A function for admins to deposit money to the pool so it can still function!  */
    // public entry fun depositToPool(_:&PoolOwnership, pool :&mut Pool<T>, amount: u64, payment: &mut Coin<SUI>){

    //     let availableCoins = coin::value(payment);
    //     assert!(availableCoins > amount, ENotEnoughMoney);

    //     let balance = coin::balance_mut(payment);

    //     let payment = balance::split(balance, amount);
    //     balance::join(&mut pool.pool_balance, payment);
    // }

    /*
       A function for admins to get their profits.
    */
    // public entry fun withdraw(_:&PoolOwnership, pool: &mut Pool<T>, amount: u64, wallet: &mut Coin<SUI>){

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