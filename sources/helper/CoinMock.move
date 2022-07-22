// token holder address, not admin address
module Sender::CoinMock {
    use aptos_framework::coin;
    use std::signer;
    #[test_only]
    use aptos_framework::coin::{register_internal};
    #[test_only]
    use std::vector;
    #[test_only]
    use std::unit_test::create_signers_for_testing;
    use std::string::String;
    #[test_only]
    use std::string;

    struct TokenSharedCapability<phantom TokenType> has key, store {
        mint: coin::MintCapability<TokenType>,
        burn: coin::BurnCapability<TokenType>,
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
            coin::initialize<TokenType>(account, name, symbol, (precision as u64), true);
        move_to(account, TokenSharedCapability<TokenType> { mint: mint_capability, burn: burn_capability });
        //Coin::register_internal<TokenType>(account);
    }

    public fun mint_coin<TokenType: store>(amount: u64, to: address): coin::Coin<TokenType> acquires TokenSharedCapability {
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(to);
        coin::mint<TokenType>(amount, &cap.mint)
    }

    public fun burn_coin<TokenType: store>(account: &signer, coin: coin::Coin<TokenType>) acquires TokenSharedCapability {
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(signer::address_of(account));
        coin::burn<TokenType>(coin, &cap.burn);
    }

    public fun transfer_coin<TokenType: store>(coin: coin::Coin<TokenType>, to: address) {
        coin::deposit<TokenType>(to, coin);
    }

    #[test(account = @Sender)]
    public fun test_mint_burn_coin(account: &signer) acquires TokenSharedCapability {
        register_coin<WETH>(account, string::utf8(b"Wapper ETH"), string::utf8(b"WETH"), 9);
        let coin = mint_coin<WETH>(10000u64, signer::address_of(account));
        burn_coin(account, coin);
    }

    #[test(account = @Sender)]
    public fun test_mint_transfer_coin(account: &signer) acquires TokenSharedCapability {
        let others = create_signers_for_testing(1);
        let other = &vector::remove(&mut others, 0);
        let (mint_capability, burn_capability) =
            coin::initialize<WETH>(account, string::utf8(b"Wapper ETH"), string::utf8(b"WETH"), 9u64, true);
        register_internal<WETH>(account);
        register_internal<WETH>(other);

        move_to(account, TokenSharedCapability<WETH> { mint: mint_capability, burn: burn_capability });
        let coin = mint_coin<WETH>(10000u64, signer::address_of(account));
        transfer_coin(coin, signer::address_of(other));
    }

    /*#[test(account = @Sender)]
    public fun test_mint_offer_coin(account: &signer) acquires TokenSharedCapability {
        let others = create_signers_for_testing(1);
        let other = &vector::remove(&mut others, 0);
        let (mint_capability, burn_capability) =
            coin::initialize<WETH>(account, string(b"Wapper ETH"), string(b"WETH"), 9u64, true);
        register_internal<WETH>(account);
        move_to(account, TokenSharedCapability<WETH> { mint: mint_capability, burn: burn_capability });

        let coin = mint_coin<WETH>(10000u64, signer::address_of(account));
        std::offer::create<Coin<WETH>>(account, coin, signer::address_of(other));

        let received = Offer::redeem<Coin<WETH>>(other, signer::address_of(account));//you maybe don't know the type of Coin
        register_internal<WETH>(other);
        transfer_coin(received, signer::address_of(other));
    }*/
}
