# Steps to Launch

- Run `sui client publish --gas <YOUR_GAS_OBJECT> --gas-budget <GAS_BUDGET>`

- Identify the Immutable Account that would be the `package address`

- Identify the Pool Ownership Address (Listed as Account Address). Note: Sometimes UpgradeCap is indistinguishable and that will throw error in such case try the other address.

- Run ` sui client call --package <PACKAGE_ADDRESS> --module "orderbook" --function "create_pool" --args <POOL_OWNERSHIP_ADDR> --type-args <CoinType_1> <CoinType2>  --gas-budget <GAS_BUDGET>`

e.g `sui client call --package 0xa06de9f1fb2aa81c6ff96e3315b4b529568476c462564e2707a64b32e5cbd6a8 --module "orderbook" --function "create_pool" --args 0x9344833ce66541f9652f69ce07f2dc8effb050923418782a0cc0c20a438c9c4a --type-args 0x2::sui::SUI 0x5019dffc2cda4c82a8b367d79338ffc3694084706919724a75f10c643ce2add8::managed::MANAGED  --gas-budget 10000000`

- This will give a `Shared Pool Address`, Save it.

To create Buy Order 
- Run `sui client call --package <PACKAGE_ADDRESS> --module "orderbook" --function "create_buy_order" --args <SHARED_ADDR>  <CoinType1 Object ID> <CoinType2 Object ID> <Total amount for which you want to buy> <Bid Price> --type-args   <CoinType_1> <CoinType2> --gas-budget <GAS_BUDGET>`

e.g: `sui client call --package 0xa06de9f1fb2aa81c6ff96e3315b4b529568476c462564e2707a64b32e5cbd6a8 --module "orderbook" --function "create_buy_order" --args 0x58a7cdb4a78aac7ec36d619299a2e57e30b2c64472cfc5c0bdf05218de35ce02  0x26f5fdfbfbf93e6d51b54097bbc4652fa8847b69375c284b80cba064cbc530ae 0xb2f3050e430e7a7a7b9e68cd0047d7a7328c313cbcee674586d8cb48ec657202 500000 100000 --type-args  0x2::sui::SUI 0x5019dffc2cda4c82a8b367d79338ffc3694084706919724a75f10c643ce2add8::managed::MANAGED --gas-budget 10000000`

To create Sell Order 
- Run `sui client call --package <PACKAGE_ADDRESS> --module "orderbook" --function "create_sell_order" --args <SHARED_ADDR>  <CoinType1 Object ID> <CoinType2 Object ID> <Total tokens you want to sell> <Ask Price> --type-args   <CoinType_1> <CoinType2> --gas-budget <GAS_BUDGET>`

e.g: `sui client call --package 0xa06de9f1fb2aa81c6ff96e3315b4b529568476c462564e2707a64b32e5cbd6a8 --module "orderbook" --function "create_sell_order" --args 0x58a7cdb4a78aac7ec36d619299a2e57e30b2c64472cfc5c0bdf05218de35ce02 0x1ce4037a5ddc1eb5048643a6426e64a9dff701c1816c4355b536fc5bb88391f2 0x37897b6ecd476d1af5c753d023670156409b6d396d1f276b79ef9a37af7a4b87 10 10000000 --type-args 0x2::sui::SUI 0x5019dffc2cda4c82a8b367d79338ffc3694084706919724a75f10c643ce2add8::managed::MANAGED --gas-budget 10000000`

- To see the current status of Pool
Run `sui client object <Shared_Addr> --json`

# Features
- Working Prototype of Orderbook.

- Supports multiple token pools of any 2 pair of coins, implemented via Generics.

- Completely decentralized exchange transfers without needing a trusted 3rd party

- Transaction are executed on Highest Buying Bid, and lowest Sell Ask.

- Auto Matching of Orders Supported

- Multiple Exeecutions to fill the complete order until breakpoint added

# Todo
- ~~Need a bugfix for recursive orders and updations~~

- Will add frontend function calls with basic buttons

- Currently uploaded code for progress view only
