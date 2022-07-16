module Sender::SafeMath {
    use Std::Errors;

    const EXP_SCALE_9: u128 = 1000000000;// e9
    const EXP_SCALE_10: u128 = 10000000000;// e10
    const EXP_SCALE_18: u128 = 1000000000000000000;// e18
    const U64_MAX:u64 = 18446744073709551615;  //length(U64_MAX)==20
    const U128_MAX:u128 = 340282366920938463463374607431768211455;  //length(U128_MAX)==39

    const EQUAL: u8 = 0;
    const LESS_THAN: u8 = 1;
    const GREATER_THAN: u8 = 2;

    const ERR_U128_OVERFLOW: u64 = 1001;
    const ERR_DIVIDE_BY_ZERO: u64 = 1002;

    public fun to_safe_u64(x: u128): u64 {
        let cmp_order = x > (U64_MAX as u128);
        if (cmp_order) {
            abort Errors::invalid_argument(ERR_U128_OVERFLOW)
        };
        (x as u64)
    }
}
