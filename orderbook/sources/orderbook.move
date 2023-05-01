module vault::deposit_core {
    // Part 1: imports
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    // Use this dependency to get a type wrapper for UTF-8 strings
    use sui::coin::{Self, Coin};
    use std::vector;

    /// User doesn't have enough coins
    const ENotEnoughMoney: u64 = 1;
    const EOutOfService: u64 = 2;

    struct Pool<phantom T, phantom U> has key, store {
        id: UID,
        // In a Pair like BTC/SUI -> Base is BTC
        base_balance: Balance<U>,
        // In a Pair like BTC/SUI -> Quote is SUI
        quote_balance: Balance<T>,
        buy_orders_list: vector<OrderObject<U>>,
        sell_orders_list: vector<OrderObject<T>>,
    }

    struct OrderObject<phantom T> has store, drop {
        order_owner: address,
        // In case of Buy, this represents Bid Price
        // In case of Sell, this represents Ask Price
        price: u64,
        // In case of Buy, this is the amount of 'Quote' that is escrowed
        // In case of Sell, this is the amount of 'Base' that is escrowed
        amount_escrowed: u64,
    }

    // This represents the ownership, only via which new Pools can be created,  
    // similar to admin Capabilities
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
            base_balance: balance::zero(),
            quote_balance: balance::zero(),
            buy_orders_list: vector::empty<OrderObject<U>>(),
            sell_orders_list: vector::empty<OrderObject<T>>()
        });
    }

    public fun create_order_object<T>(price: u64, amount:u64, ctx: &mut TxContext):OrderObject<T>{
        OrderObject{
            order_owner: tx_context::sender(ctx),
            price,
            amount_escrowed: amount
        }
    }

    public fun pool_base_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<U>(&self.base_balance)
    }

    public fun pool_quote_balance<T, U>(self:  &Pool<T, U>): u64{
       balance::value<T>(&self.quote_balance)
    }

    fun min(a:u64, b:u64):u64{
        if (a <= b) {
           return  a
        };
        return b
    }

    public entry fun create_buy_order<T, U>(pool: &mut Pool<T, U>, quote_wallet: &mut Coin<T>, base_wallet: &mut Coin<U>, quote_amount: u64, bid_price: u64, ctx: &mut TxContext){
        
        // make sure we have enough money to deposit!
        assert!(coin::value<T>(quote_wallet) >= quote_amount, ENotEnoughMoney);

        if (!vector::is_empty<OrderObject<T>>(&pool.sell_orders_list)  && vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0).price <= bid_price) {
            
            let availableCoins = pool_base_balance(pool);

            let order_object = vector::borrow<OrderObject<T>>(&pool.sell_orders_list, 0);

            //Decide the number of `Base` value that needs to be transacted
            let transaction_base_value = min(quote_amount/order_object.price, order_object.amount_escrowed);
            //Decide the number of `Quotes` Value that needs to be transacted
            let transaction_quote_value = min(quote_amount, order_object.price * order_object.amount_escrowed);

            //The Base value should be available in escrow to proceed
            assert!(availableCoins >= transaction_base_value, ENotEnoughMoney);

            let wallet_balance = coin::split(quote_wallet, transaction_quote_value, ctx);
            transfer::public_transfer(wallet_balance, order_object.order_owner);

            // split money from vault's Base balance.
            let token_balance = coin::balance_mut(base_wallet);
            let token_payment = balance::split(&mut pool.base_balance, transaction_base_value);
            balance::join<U>(token_balance, token_payment);

            let remainder_buy_balance = quote_amount - transaction_quote_value;
            let remainder_token_balance = order_object.amount_escrowed - transaction_base_value;

            // If from a particular Sell order, not all the Base tokens were sold, reduce the number accordingly
            if (remainder_token_balance > 0) {
                vector::borrow_mut<OrderObject<T>>(&mut pool.sell_orders_list, 0).amount_escrowed = remainder_token_balance;
            } else {
                vector::remove<OrderObject<T>>(&mut pool.sell_orders_list, 0);
            };
            // If the sell order was not able to fulfil the complete buy order, look for next
            if (remainder_buy_balance > 0) {
                create_buy_order(pool, quote_wallet, base_wallet, remainder_buy_balance, bid_price, ctx);
            }
        } else {
            // get balance reference
            let wallet_balance = coin::balance_mut(quote_wallet);

            // get money from balance
            let payment = balance::split(wallet_balance, quote_amount);

            // add to pool's balance.
            balance::join<T>(&mut pool.quote_balance, payment);

            insert_buy_order_object(pool, bid_price, quote_amount, ctx);
        }
    }

    public entry fun create_sell_order<T, U>(pool: &mut Pool<T, U>, quote_wallet: &mut Coin<T>, base_wallet: &mut Coin<U>, base_amount: u64, ask_price: u64, ctx: &mut TxContext){

        // make sure we have enough tokens to sell!
        assert!(coin::value<U>(base_wallet) >= base_amount, ENotEnoughMoney);

        if (!vector::is_empty<OrderObject<U>>(&pool.buy_orders_list) && vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0).price >= ask_price) {
            
            let availableCoins = pool_quote_balance(pool);

            let order_object = vector::borrow<OrderObject<U>>(&pool.buy_orders_list, 0);

            // Decide the number of `Base` tokens to transact
            let transaction_base_value = min(base_amount, order_object.amount_escrowed/order_object.price);
            // Decide the number of `Base` Value to transact
            let transaction_quote_value = min(base_amount * order_object.price, order_object.amount_escrowed);

            //The `Quote` Value should be available in escrow to proceed
            assert!(availableCoins >= transaction_quote_value, ENotEnoughMoney);

            let wallet_balance = coin::balance_mut(quote_wallet);
            let payment = balance::split(&mut pool.quote_balance, transaction_quote_value);
            balance::join(wallet_balance, payment);

            let coin_object = coin::split(base_wallet, transaction_base_value, ctx);
            transfer::public_transfer(coin_object, order_object.order_owner);

            let remainder_buy_balance = order_object.amount_escrowed - transaction_quote_value;
            let remainder_token_balance = base_amount - transaction_base_value;

            // If this Sell order was not able to completely reduce the buy order, reduce the number accordingly
            if (remainder_buy_balance > 0) {
                vector::borrow_mut<OrderObject<U>>(&mut pool.buy_orders_list, 0).amount_escrowed = remainder_buy_balance;
            } else {
               vector::remove<OrderObject<U>>(&mut pool.buy_orders_list, 0);
            };
            // If the sell order is yet to be fulfilled, look for next
            if (remainder_token_balance > 0) {
                create_sell_order(pool, quote_wallet, base_wallet, remainder_token_balance, ask_price, ctx);
            }
        } else {
            // get balance reference
            let token_balance = coin::balance_mut(base_wallet);

            // get token from balance
            let token_payment = balance::split(token_balance, base_amount);
            
            // add to pool's balance.
            balance::join<U>(&mut pool.base_balance, token_payment);

            insert_sell_order_object(pool, ask_price, base_amount, ctx);
        }
    }

    fun insert_buy_order_object<T, U>(pool: &mut Pool<T, U>, bid_price: u64, amount:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(bid_price, amount, ctx);
        let vec_len = vector::length<OrderObject<U>>(&pool.buy_orders_list);

        vector::push_back<OrderObject<U>>(&mut pool.buy_orders_list, order_object);

        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<U>>(&pool.buy_orders_list, last).price > vector::borrow<OrderObject<U>>(&pool.buy_orders_list, second_last).price) {
                    vector::swap<OrderObject<U>>(&mut pool.buy_orders_list, last, second_last);
                    if (second_last == 0) {
                        break
                    };
                    last = second_last;
                    second_last = second_last - 1;
                }else{break}
            }
        }
    } 

    fun insert_sell_order_object<T, U>(pool: &mut Pool<T, U>, ask_price: u64, amount:u64, ctx: &mut TxContext) {

        let order_object = create_order_object(ask_price, amount, ctx);
        let vec_len = vector::length<OrderObject<T>>(&pool.sell_orders_list);
        vector::push_back<OrderObject<T>>(&mut pool.sell_orders_list, order_object);
        if (vec_len>0){
            let last = vec_len;
            let second_last = vec_len -1 ;
            while (second_last >= 0) {
                if (vector::borrow<OrderObject<T>>(&pool.sell_orders_list, last).price < vector::borrow<OrderObject<T>>(&pool.sell_orders_list, second_last).price) {
                    vector::swap<OrderObject<T>>(&mut pool.sell_orders_list, last, second_last);

                    if(second_last == 0 ){
                        break
                    };
                    
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