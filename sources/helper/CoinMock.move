// token holder address, not admin address
module Sender::CoinMock {
    use AptosFramework::Coin;
    use Std::Signer;
    use Std::ASCII::{String, string};
    #[test_only]
    use AptosFramework::Coin::{register_internal, Coin};
    #[test_only]
    use Std::Offer;
    #[test_only]
    use Std::UnitTest::create_signers_for_testing;
    #[test_only]
    use Std::Vector;

    struct TokenSharedCapability<phantom TokenType> has key, store {
        mint: Coin::MintCapability<TokenType>,
        burn: Coin::BurnCapability<TokenType>,
    }

    // mock ETH token
    struct WETH has copy, drop, store {}

    // mock USDT token
    struct WUSDT has copy, drop, store {}

    // mock DAI token
    struct WDAI has copy, drop, store {}

    // mock BTC token
    struct WBTC has copy, drop, store {}

    // mock DOT token
    struct WDOT has copy, drop, store {}


    public fun register_coin<TokenType: store>(account: &signer, name: String, symbol: String, precision: u8) {
        let (mint_capability, burn_capability) =
            Coin::initialize<TokenType>(account, name, symbol, (precision as u64), true);
        move_to(account, TokenSharedCapability<TokenType> { mint: mint_capability, burn: burn_capability });
        //Coin::register_internal<TokenType>(account);
    }

    public fun mint_coin<TokenType: store>(amount: u64, to: address): Coin::Coin<TokenType> acquires TokenSharedCapability {
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(to);
        Coin::mint<TokenType>(amount, &cap.mint)
    }

    public fun burn_coin<TokenType: store>(account: &signer, coin: Coin::Coin<TokenType>) acquires TokenSharedCapability {
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(Signer::address_of(account));
        Coin::burn<TokenType>(coin, &cap.burn);
    }

    public fun transfer_coin<TokenType: store>(coin: Coin::Coin<TokenType>, to: address) {
        Coin::deposit<TokenType>(to, coin);
    }

    #[test(account = @Sender)]
    public fun test_mint_burn_coin(account: &signer) acquires TokenSharedCapability {
        register_coin<WETH>(account, string(b"Wapper ETH"), string(b"WETH"), 9);
        let coin = mint_coin<WETH>(10000u64, Signer::address_of(account));
        burn_coin(account, coin);
    }

    #[test(account = @Sender, other = @TestUser)]
    public fun test_mint_transfer_coin(account: &signer, other: &signer) acquires TokenSharedCapability {
        let (mint_capability, burn_capability) =
            Coin::initialize<WETH>(account, string(b"Wapper ETH"), string(b"WETH"), 9u64, true);
        register_internal<WETH>(account);
        register_internal<WETH>(other);

        move_to(account, TokenSharedCapability<WETH> { mint: mint_capability, burn: burn_capability });
        let coin = mint_coin<WETH>(10000u64, Signer::address_of(account));
        transfer_coin(coin, Signer::address_of(other));
    }

    #[test(account = @Sender)]
    public fun test_mint_offer_coin(account: &signer) acquires TokenSharedCapability {
        let others = create_signers_for_testing(1);
        let other = &Vector::remove(&mut others, 0);
        let (mint_capability, burn_capability) =
            Coin::initialize<WETH>(account, string(b"Wapper ETH"), string(b"WETH"), 9u64, true);
        register_internal<WETH>(account);
        move_to(account, TokenSharedCapability<WETH> { mint: mint_capability, burn: burn_capability });

        let coin = mint_coin<WETH>(10000u64, Signer::address_of(account));
        Offer::create<Coin<WETH>>(account, coin, Signer::address_of(other));

        let received = Offer::redeem<Coin<WETH>>(other, Signer::address_of(account));//you don't know the type of Coin
        register_internal<WETH>(other);
        transfer_coin(received, Signer::address_of(other));
    }
}
