module x2::orderbook {
    // Part 1: imports
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
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
    // Test Coin
    struct MANAGED has drop {}

    #[test]
    fun test_orderbook() {
        use sui::test_scenario::{Self};
        use sui::sui::SUI;
        use std::debug;

        // Dummy account addresses
        let admin = @0xBABE;
        let buyer = @0xFACE;
        let seller = @0xCAFE;

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };

        //Create Pool
        test_scenario::next_tx(scenario, admin);
        {
            let pool_ownership = test_scenario::take_from_sender<PoolOwnership>(scenario);
            create_pool<SUI, MANAGED>(&pool_ownership, test_scenario::ctx(scenario));

            //Since we cannot drop pool_ownership just like that
            test_scenario::return_to_sender(scenario, pool_ownership);
        };
        //Add a Buy in orderbook
        test_scenario::next_tx(scenario, buyer);
        {
            //Get the current latest shared pool in the scenario
            let pool = test_scenario::take_shared<Pool<SUI, MANAGED>>(scenario);
            debug::print(&pool);

            //Mint some test coin wallets
            let wallet = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            let wallet2 = coin::mint_for_testing<MANAGED>(0, test_scenario::ctx(scenario));

            // Sui amount -> 10, Bid Price -> 2
            create_buy_order(&mut pool, &mut wallet, &mut wallet2, 10, 2, test_scenario::ctx(scenario));

            assert!(vector::borrow<OrderObject<MANAGED>>(&pool.buy_orders_list, 0).price == 2 &&
               vector::length<OrderObject<MANAGED>>(&pool.buy_orders_list) == 1 , 1);
            
            //Drop the wallets
            let dummy_address = @0xCAFE;
            transfer::public_transfer(wallet, dummy_address);
            transfer::public_transfer(wallet2, dummy_address);

            //Return the shared object
            test_scenario::return_shared(pool);
        };
        // Add sell for the previous buy and create multiple sells on top of that
        test_scenario::next_tx(scenario, seller);
        {
            //Get the current latest shared pool in the scenario
            let pool = test_scenario::take_shared<Pool<SUI, MANAGED>>(scenario);
            debug::print(&pool);

            //Mint some test coin wallets
            let wallet = coin::mint_for_testing<SUI>(0, test_scenario::ctx(scenario));
            let wallet2 = coin::mint_for_testing<MANAGED>(30, test_scenario::ctx(scenario));

            //Sell 5 `MANAGED` tokens for Ask_price -> 2
            create_sell_order(&mut pool, &mut wallet, &mut wallet2, 5, 2, test_scenario::ctx(scenario));

            //Since the sell will be matched no orders will be left
            assert!(vector::length<OrderObject<SUI>>(&pool.sell_orders_list) == 0 &&
             vector::length<OrderObject<MANAGED>>(&pool.buy_orders_list) == 0 , 1);
            
            //Create another sell order
            create_sell_order(&mut pool, &mut wallet, &mut wallet2, 15, 3, test_scenario::ctx(scenario));
            create_sell_order(&mut pool, &mut wallet, &mut wallet2, 10, 5, test_scenario::ctx(scenario));

            //Drop the wallets
            let dummy_address = @0xCAFE;
            transfer::public_transfer(wallet, dummy_address);
            transfer::public_transfer(wallet2, dummy_address);

            //Return the shared object
            debug::print(&pool);
            test_scenario::return_shared(pool);
        };
        //Match the buy with higher BidPrice than AskPrice and initate Buy of more than total Sell Value
        test_scenario::next_tx(scenario, buyer);
        {
            //Get the current latest shared pool in the scenario
            let pool = test_scenario::take_shared<Pool<SUI, MANAGED>>(scenario);
            debug::print(&pool);

            //Mint some test coin wallets
            let wallet = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
            let wallet2 = coin::mint_for_testing<MANAGED>(0, test_scenario::ctx(scenario));

            //Buy for 100 SUI at Bid Price of 5
            create_buy_order(&mut pool, &mut wallet, &mut wallet2, 100, 5, test_scenario::ctx(scenario));

            //amount_escrowed will be 5 as 2 sell orders will be executed and take 45, 50 sui respectively 
            // and a buy order of sui amount 5 will be left at bid price of 5s
            assert!(vector::borrow<OrderObject<MANAGED>>(&pool.buy_orders_list, 0).amount_escrowed == 5 &&
               vector::length<OrderObject<SUI>>(&pool.sell_orders_list) == 0 , 1);
            
            //Drop the wallets
            let dummy_address = @0xCAFE;
            transfer::public_transfer(wallet, dummy_address);
            transfer::public_transfer(wallet2, dummy_address);

            //Return the shared object
            test_scenario::return_shared(pool);
        };
        // Match the only open buy with sell
        test_scenario::next_tx(scenario, seller);
        {
            //Get the current latest shared pool in the scenario
            let pool = test_scenario::take_shared<Pool<SUI, MANAGED>>(scenario);
            debug::print(&pool);

            //Mint some test coin wallets
            let wallet = coin::mint_for_testing<SUI>(0, test_scenario::ctx(scenario));
            let wallet2 = coin::mint_for_testing<MANAGED>(1, test_scenario::ctx(scenario));

            // Sell 1 token for 5 SUI
            create_sell_order(&mut pool, &mut wallet, &mut wallet2, 1, 5, test_scenario::ctx(scenario));

            //Since the sell will be matched no orders will be left
            assert!(vector::length<OrderObject<SUI>>(&pool.sell_orders_list) == 0 &&
             vector::length<OrderObject<MANAGED>>(&pool.buy_orders_list) == 0 , 1);

            //Drop the wallets
            let dummy_address = @0xCAFE;
            transfer::public_transfer(wallet, dummy_address);
            transfer::public_transfer(wallet2, dummy_address);

            //Return the shared object
            debug::print(&pool);
            test_scenario::return_shared(pool);
        };
        test_scenario::end(scenario_val);
    }
}