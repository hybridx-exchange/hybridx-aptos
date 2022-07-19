module Sender::TokenSwap {
    use AptosFramework::Coin;
    use Std::Event;
    use Sender::Config;
    use AptosFramework::TypeInfo::TypeInfo;
    use AptosFramework::TypeInfo::type_of;
    use AptosFramework::Comparator;
    use Std::ASCII;
    use Std::Signer;
    use AptosFramework::Comparator::Result;
    use Std::Option;
    use Sender::Math;
    use AptosFramework::Timestamp;
    use Sender::FixedPoint64;

    struct LiquidityCoin<phantom coin_x, phantom coin_y> has key, store, copy, drop {}

    struct LiquidityCoinCapability<phantom coin_x, phantom coin_y> has key, store {
        mint: Coin::MintCapability<LiquidityCoin<coin_x, coin_y>>,
        burn: Coin::BurnCapability<LiquidityCoin<coin_x, coin_y>>
    }

    struct PairRegisterEvent has drop, store {
        coin_x_type: TypeInfo,
        coin_y_type: TypeInfo,
        signer: address
    }

    struct AddLiquidityEvent has drop, store {
        liquidity: u64,
        coin_x_type: TypeInfo,
        coin_y_type: TypeInfo,
        signer: address,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64
    }

    struct RemoveLiquidityEvent has drop, store {
        liquidity: u64,
        coin_x_type: TypeInfo,
        coin_y_type: TypeInfo,
        signer: address,
        amount_x_min: u64,
        amount_y_min: u64
    }

    struct SwapEvent has drop, store {
        coin_x_type: TypeInfo,
        coin_y_type: TypeInfo,
        signer: address,
        x_in: u64,
        y_out: u64
    }

    struct Pair<phantom coin_0, phantom coin_1> has key, store {
        coin_0_reserve: Coin::Coin<coin_0>,
        coin_1_reserve: Coin::Coin<coin_1>,
        last_block_timestamp: u64,
        last_price_0_cumulative: u128,
        last_price_1_cumulative: u128,
        last_k: u128
    }

    struct LiquidityEventHandle has key, store {
        register_pair_event: Event::EventHandle<PairRegisterEvent>,
        add_liquidity_event: Event::EventHandle<AddLiquidityEvent>,
        remove_liquidity_event: Event::EventHandle<RemoveLiquidityEvent>,
        swap_event: Event::EventHandle<SwapEvent>
    }

    const ERROR_SWAP_INVALID_TOKEN_PAIR: u64 = 2000;
    const ERROR_SWAP_INVALID_PARAMETER: u64 = 2001;
    const ERROR_SWAP_TOKEN_INSUFFICIENT: u64 = 2002;
    const ERROR_SWAP_DUPLICATE_TOKEN: u64 = 2003;
    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_SWAPOUT_CALC_INVALID: u64 = 2005;
    const ERROR_SWAP_PRIVILEGE_INSUFFICIENT: u64 = 2006;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;
    const ERROR_SWAP_TOKEN_NOT_EXISTS: u64 = 2008;
    const ERROR_SWAP_TOKEN_FEE_INVALID: u64 = 2009;

    const LIQUIDITY_COIN_SCALE: u64 = 9;
    const LIQUIDITY_COIN_NAME: vector<u8> = b"hybridx liquidity coin";
    const LIQUIDITY_COIN_SYMBOL: vector<u8> = b"LPC";

    public fun init_event_handle(signer: &signer) {
        let admin = Config::admin_address();
        if (!exists<LiquidityEventHandle>(admin)) {
            Config::assert_admin(signer);
            move_to(signer, LiquidityEventHandle {
                add_liquidity_event: Event::new_event_handle<AddLiquidityEvent>(signer),
                remove_liquidity_event: Event::new_event_handle<RemoveLiquidityEvent>(signer),
                swap_event: Event::new_event_handle<SwapEvent>(signer),
                register_pair_event: Event::new_event_handle<PairRegisterEvent>(signer),
            });
        };
    }

    public fun assert_is_coin<TypeInfo: store>(): bool {
        assert!(Coin::is_coin_initialized<TypeInfo>(), ERROR_SWAP_TOKEN_NOT_EXISTS);
        true
    }

    public fun compare_coin<X: copy + drop + store, Y: copy + drop + store>(): Result {
        let x_type = type_of<X>();
        let y_type = type_of<Y>();

        Comparator::compare<TypeInfo>(&x_type, &y_type)
    }

    public fun create_pair<X: copy + drop + store, Y: copy + drop + store>(): Pair<X, Y> {
        Pair<X, Y> {
            coin_0_reserve: Coin::zero<X>(),
            coin_1_reserve: Coin::zero<Y>(),
            last_block_timestamp: 0u64,
            last_price_0_cumulative: 0u128,
            last_price_1_cumulative: 0u128,
            last_k: 0u128
        }
    }

    fun register_liquidity_coin<X: copy + drop + store, Y: copy + drop + store>(signer: &signer) {
        let (mint_capability, burn_capability) =
            Coin::initialize<LiquidityCoin<X, Y>>(
                signer,
                ASCII::string(LIQUIDITY_COIN_NAME),
                ASCII::string(LIQUIDITY_COIN_SYMBOL),
                LIQUIDITY_COIN_SCALE,
                true
            );

        move_to(signer, LiquidityCoinCapability<X, Y>{mint: mint_capability, burn: burn_capability});
    }

    public fun register_pair<X: copy + drop + store, Y: copy + drop + store>(signer: &signer)
    acquires LiquidityEventHandle {
        assert_is_coin<X>();
        assert_is_coin<Y>();

        init_event_handle(signer);
        let result = compare_coin<X, Y>();
        assert!(Comparator::is_equal(&result), ERROR_SWAP_INVALID_TOKEN_PAIR);

        let pair = create_pair<X, Y>();
        move_to(signer, pair);

        register_liquidity_coin<X, Y>(signer);

        let event_handle = borrow_global_mut<LiquidityEventHandle>(Config::admin_address());
        Event::emit_event(&mut event_handle.register_pair_event, PairRegisterEvent {
            coin_x_type: type_of<X>(),
            coin_y_type: type_of<Y>(),
            signer: Signer::address_of(signer)
        });
    }

    public fun get_reserves<X: copy + drop + store, Y: copy + drop + store>(): (u64, u64) acquires Pair {
        let pair = borrow_global<Pair<X, Y>>(Config::admin_address());
        let x_reserve = Coin::value(&pair.coin_0_reserve);
        let y_reserve = Coin::value(&pair.coin_1_reserve);

        (x_reserve, y_reserve)
    }

    fun update<X: copy + drop + store, Y: copy + drop + store>(x_reserve: u64, y_reserve: u64) acquires Pair {
        let pair = borrow_global_mut<Pair<X, Y>>(Config::admin_address());

        let last_block_timestamp = pair.last_block_timestamp;
        let block_timestamp = Timestamp::now_seconds() % (1u64 << 32);
        let time_elapsed = block_timestamp - last_block_timestamp;
        if (time_elapsed > 0 && x_reserve > 0 && y_reserve > 0) {
            let last_price_0_cumulative = FixedPoint64::to_u128(FixedPoint64::div(FixedPoint64::encode(x_reserve), y_reserve)) * (time_elapsed as u128);
            let last_price_1_cumulative = FixedPoint64::to_u128(FixedPoint64::div(FixedPoint64::encode(y_reserve), x_reserve)) * (time_elapsed as u128);
            pair.last_price_0_cumulative = *&pair.last_price_0_cumulative + last_price_0_cumulative;
            pair.last_price_1_cumulative = *&pair.last_price_1_cumulative + last_price_1_cumulative;
        };

        pair.last_block_timestamp = block_timestamp;
    }

    public fun mint<X: copy + drop + store, Y: copy + drop + store>(
        x: Coin::Coin<X>,
        y: Coin::Coin<Y>
    ): Coin::Coin<LiquidityCoin<X, Y>> acquires Pair, LiquidityCoinCapability {
        let total_supply_option = Coin::supply<LiquidityCoin<X, Y>>();
        let total_supply = Option::get_with_default(&total_supply_option, 0u128);
        let (x_reserve, y_reserve) = get_reserves<X, Y>();

        let x_value = Coin::value<X>(&x);
        let y_value = Coin::value<Y>(&y);

        let liquidity = if (total_supply == 0u128) {
            let init_liquidity = Math::sqrt((x_value as u128) * (y_value as u128));
            assert!(init_liquidity > 1000u64, ERROR_SWAP_ADDLIQUIDITY_INVALID);
            init_liquidity - 1000u64
        }
        else {
            let x_liquidity = ((x_value as u128) * total_supply) / (x_reserve as u128);
            let y_liquidity = ((y_value as u128) * total_supply) / (y_reserve as u128);

            if (x_liquidity < y_liquidity) {
                (x_liquidity as u64)
            }
            else {
                (y_liquidity as u64)
            }
        };

        assert!(liquidity > 0u64, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        let admin_address = Config::admin_address();
        let _pair = borrow_global_mut<Pair<X, Y>>(admin_address);

        Coin::deposit<X>(admin_address, x);
        Coin::deposit<Y>(admin_address, y);
        let liquidity_cap = borrow_global<LiquidityCoinCapability<X, Y>>(admin_address);
        let mint_liquidity = Coin::mint(liquidity, &liquidity_cap.mint);

        update<X, Y>(x_reserve, y_reserve);

        mint_liquidity
    }
}