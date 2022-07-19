// token holder address, not admin address
module Sender::CoinMock {
    use AptosFramework::Coin;
    use Std::Signer;
    use Std::ASCII::{String, string};

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


    public fun register_token<TokenType: store>(account: &signer, name: String, symbol: String, precision: u8){
        let (mint_capability, burn_capability) =
            Coin::initialize<TokenType>(account, name, symbol, (precision as u64), true);
        move_to(account, TokenSharedCapability { mint: mint_capability, burn: burn_capability });
    }

    public fun mint_token<TokenType: store>(amount: u64, to: address): Coin::Coin<TokenType> acquires TokenSharedCapability{
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(to);
        Coin::mint<TokenType>(amount, &cap.mint)
    }

    public fun burn_token<TokenType: store>(account: &signer, coin: Coin::Coin<TokenType>) acquires TokenSharedCapability{
        //token holder address
        let cap = borrow_global<TokenSharedCapability<TokenType>>(Signer::address_of(account));
        Coin::burn<TokenType>(coin, &cap.burn);
    }

    #[test(account = @Sender)]
    public fun test_mint_burn_coins(account: &signer) acquires TokenSharedCapability {
        register_token<WETH>(account, string(b"Wapper ETH"), string(b"WETH"), 9);
        let coin = mint_token<WETH>(10000u64, Signer::address_of(account));
        burn_token(account, coin);
    }
}

