module Sender::Config {
    use Std::Signer;
    use Std::Errors;

    const ERROR_NOT_HAS_PRIVILEGE: u64 = 101;
    const ERROR_GLOBAL_FREEZE: u64 = 102;

    public fun admin_address(): address {
        @Sender
    }

    public fun assert_admin(signer: &signer) {
        assert!(Signer::address_of(signer) == admin_address(), Errors::invalid_state(ERROR_NOT_HAS_PRIVILEGE));
    }
}
