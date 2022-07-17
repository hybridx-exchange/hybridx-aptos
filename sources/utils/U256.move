/// Helper module to do u64 arith.
module Sender::Arith {
    use Std::Errors;
    const ERR_INVALID_CARRY:  u64 = 301;
    const ERR_INVALID_BORROW: u64 = 302;

    const P32: u64 = 0x100000000;
    const P64: u128 = 0x10000000000000000;

    spec module {
        pragma verify = true;
        pragma aborts_if_is_strict;
    }

    /// split u64 to (high, low)
    public fun split_u64(i: u64): (u64, u64) {
        (i >> 32, i & 0xFFFFFFFF)
    }

    spec split_u64 {
        pragma opaque; // MVP cannot reason about bitwise operation
        ensures result_1 == i / P32;
        ensures result_2 == i % P32;
    }

    /// split u64 to (high, low)
    public fun split_u128(i: u128): (u64, u64) {
        (((i >> 64) as u64), ((i & 0xFFFFFFFFFFFFFFFF) as u64))
    }

    spec split_u128 {
        pragma opaque; // MVP cannot reason about bitwise operation
        ensures result_1 == i / P64;
        ensures result_2 == i % P64;
    }

    /// combine (high, low) to u64,
    /// any lower bits of `high` will be erased, any higher bits of `low` will be erased.
    public fun combine_u64(hi: u64, lo: u64): u64 {
        (hi << 32) | (lo & 0xFFFFFFFF)
    }

    spec combine_u64 {
        pragma opaque; // MVP cannot reason about bitwise operation
        let hi_32 = hi % P32;
        let lo_32 = lo % P32;
        ensures result == hi_32 * P32 + lo_32;
    }

    /// a + b, with carry
    public fun adc(a: u64, b: u64, carry: &mut u64) : u64 {
        assert!(*carry <= 1, Errors::invalid_argument(ERR_INVALID_CARRY));
        let (a1, a0) = split_u64(a);
        let (b1, b0) = split_u64(b);
        let (c, r0) = split_u64(a0 + b0 + *carry);
        let (c, r1) = split_u64(a1 + b1 + c);
        *carry = c;
        combine_u64(r1, r0)
    }

    spec adc {
        // Carry has either to be 0 or 1
        aborts_if !(carry == 0 || carry == 1);
        ensures carry == 0 || carry == 1;
        // Result with or without carry
        ensures carry == 0 ==> result == a + b + old(carry);
        ensures carry == 1 ==> P64 + result == a + b + old(carry);
    }

    /// a - b, with borrow
    public fun sbb(a: u64, b: u64, borrow: &mut u64): u64 {
        assert!(*borrow <= 1, Errors::invalid_argument(ERR_INVALID_BORROW));
        let (a1, a0) = split_u64(a);
        let (b1, b0) = split_u64(b);
        let (b, r0) = split_u64(P32 + a0 - b0 - *borrow);
        let borrowed = 1 - b;
        let (b, r1) = split_u64(P32 + a1 - b1 - borrowed);
        *borrow = 1 - b;

        combine_u64(r1, r0)
    }

    spec sbb {
        // Borrow has either to be 0 or 1
        aborts_if !(borrow == 0 || borrow == 1);
        ensures borrow == 0 || borrow == 1;
        // Result with or without borrow
        ensures borrow == 0 ==> result == a - b - old(borrow);
        ensures borrow == 1 ==> result == P64 + a - b - old(borrow);
    }
}

/// Implementation u256.
module Sender::U256 {

    spec module {
        pragma verify = true;
    }

    use Std::Vector;
    use Std::Errors;

    const WORD: u8 = 4;
    const P32: u64 = 0x100000000;
    const P64: u128 = 0x10000000000000000;
    const P64MAX: u64 = 0xffffffffffffffff;
    const P128MAX: u128 = 0xffffffffffffffffffffffffffffffff;

    const ERR_INVALID_LENGTH: u64 = 100;
    const ERR_OVERFLOW: u64 = 200;
    /// use vector to represent data.
    /// so that we can use buildin vector ops later to construct U256.
    /// vector should always has two elements.
    struct U256 has copy, drop, store {
        /// little endian representation
        bits: vector<u64>,
    }

    spec U256 {
        invariant len(bits) == 4;
    }

    public fun mul(a: U256, b: U256): U256 {
        let c_bits = Vector::empty<u64>();
        let (i, j) = (0u64, 0u64);
        let len = (WORD as u64);
        let (c_i, c_len) = (0u64, len * 2);
        while (c_i < c_len) {
            Vector::push_back(&mut c_bits, 0u64);
            c_i = c_i + 1;
        };

        while(i < len) {
            let carry = 0u64;
            let b_bit = Vector::borrow<u64>(&b.bits, i);

            while(j < len) {
                let a_bit = Vector::borrow<u64>(&a.bits, j);
                let (hig, low) = Sender::Arith::split_u128((*a_bit as u128) * (*b_bit as u128));

                let overflow = {
                    let existing_low = Vector::borrow_mut<u64>(&mut c_bits, i + j);
                    let carry_tmp = 0u64;
                    *existing_low = Sender::Arith::adc(low, *existing_low, &mut carry_tmp);
                    carry_tmp
                };

                carry = {
                    let existing_hig = Vector::borrow_mut<u64>(&mut c_bits, i + j + 1);
                    let hig = hig + overflow;
                    let carry_tmp0 = 0u64;
                    let carry_tmp1 = 0u64;

                    let hig = Sender::Arith::adc(hig, carry, &mut carry_tmp0);
                    let hig = Sender::Arith::adc(hig, *existing_hig, &mut carry_tmp1);
                    *existing_hig = hig;
                    carry_tmp0 | carry_tmp1
                };

                j = j + 1;
            };

            i = i + 1;
        };

        c_i = Vector::length(&c_bits) - 1;
        while(c_i >= len) {
            let overflow = Vector::remove(&mut c_bits, c_i);
            assert!(overflow == 0, 100);
            c_i = c_i - 1;
        };

        U256 { bits: c_bits }
    }

    spec fun value_of_U256(a: U256): num {
        a.bits[0] +
        a.bits[1] * P64 +
        a.bits[2] * P64 * P64 +
        a.bits[3] * P64 * P64 * P64
    }

    public fun zero(): U256 {
        from_u128(0u128)
    }

    public fun one(): U256 {
        from_u128(1u128)
    }

    public fun max(): U256 {
        let bits = Vector::singleton<u64>(P64MAX);
        Vector::push_back<u64>(&mut bits, P64MAX);
        Vector::push_back<u64>(&mut bits, P64MAX);
        Vector::push_back<u64>(&mut bits, P64MAX);
        U256 { bits }
    }

    public fun max_1(): U256 {
        let bits = Vector::singleton<u64>(P64MAX-1);
        Vector::push_back<u64>(&mut bits, P64MAX);
        Vector::push_back<u64>(&mut bits, P64MAX);
        Vector::push_back<u64>(&mut bits, P64MAX);
        U256 { bits }
    }

    public fun from_u64(v: u64): U256 {
        from_u128((v as u128))
    }

    public fun from_u128(v: u128): U256 {
        let low = ((v & 0xffffffffffffffff) as u64);
        let high = ((v >> 64) as u64);
        let bits = Vector::singleton<u64>(low);
        Vector::push_back<u64>(&mut bits, high);
        Vector::push_back<u64>(&mut bits, 0u64);
        Vector::push_back<u64>(&mut bits, 0u64);
        U256 { bits }
    }

    spec from_u128 {
        pragma opaque; // Original function has bitwise operator
        ensures value_of_U256(result) == v;
    }

    #[test]
    fun test_from_u128() {
        // 2^64 + 1
        let v = from_u128(18446744073709551617u128);
        assert!(*Vector::borrow<u64>(&v.bits, 0) == 1, 0);
        assert!(*Vector::borrow<u64>(&v.bits, 1) == 1, 1);
        assert!(*Vector::borrow<u64>(&v.bits, 2) == 0, 2);
        assert!(*Vector::borrow<u64>(&v.bits, 3) == 0, 3);
    }

    public fun to_u128(v: &U256): u128 {
        assert!(*Vector::borrow<u64>(&v.bits, 3) == 0, Errors::invalid_state(ERR_OVERFLOW));
        assert!(*Vector::borrow<u64>(&v.bits, 2) == 0, Errors::invalid_state(ERR_OVERFLOW));
        ((*Vector::borrow<u64>(&v.bits, 1) as u128) << 64) | (*Vector::borrow<u64>(&v.bits, 0) as u128)
    }

    spec to_u128 {
        pragma opaque; // Original function has bitwise operator
        aborts_if value_of_U256(v) >= P64 * P64;
        ensures value_of_U256(v) == result;
    }

    #[test]
    fun test_to_u128() {
        // 2^^128 - 1
        let i = 340282366920938463463374607431768211455u128;
        let v = from_u128(i);
        assert!(to_u128(&v) == i, 128);
    }
    #[test]
    #[expected_failure]
    fun test_to_u128_overflow() {
        // 2^^128 - 1
        let i = 340282366920938463463374607431768211455u128;
        let v = from_u128(i);
        let v = add(v, one());
        to_u128(&v);
    }

    const EQUAL: u8 = 0;
    const LESS_THAN: u8 = 1;
    const GREATER_THAN: u8 = 2;

    public fun compare(a: &U256, b: &U256): u8 {
        let i = (WORD as u64);
        while (i > 0) {
            i = i - 1;
            let a_bits = *Vector::borrow<u64>(&a.bits, i);
            let b_bits = *Vector::borrow<u64>(&b.bits, i);
            if (a_bits != b_bits) {
                if (a_bits < b_bits) {
                    return LESS_THAN
                } else {
                    return GREATER_THAN
                }
            }
        };
        return EQUAL
    }

    #[test]
    fun test_compare() {
        let a = from_u64(111);
        let b = from_u64(111);
        let c = from_u64(112);
        let d = from_u64(110);
        assert!(compare(&a, &b) == EQUAL, 0);
        assert!(compare(&a, &c) == LESS_THAN, 1);
        assert!(compare(&a, &d) == GREATER_THAN, 2);
    }


    public fun add(a: U256, b: U256): U256 {
        add_nocarry(&mut a, &b);
        a
    }

    spec add {
        aborts_if value_of_U256(a) + value_of_U256(b) >= P64 * P64 * P64 * P64;
        ensures value_of_U256(result) == value_of_U256(a) + value_of_U256(b);
    }

    #[test]
    fun test_add() {
        let a = one();
        let b = from_u128(10);
        let ret = add(a, b);
        assert!(compare(&ret, &from_u64(11)) == EQUAL, 0);
    }

    #[test]
    fun test_add2() {
        let a = one();
        let b = max_1();
        let ret = add(a, b);
        assert!(compare(&ret, &max()) == EQUAL, 0);
    }

    #[test]
    #[expected_failure]
    fun test_add_overflow() {
        let a = one();
        let b = max();
        let _ret = add(a, b);
        //assert!(compare(&ret, &from_u128(0)) == EQUAL, 0);
    }

    public fun sub(a: U256, b: U256): U256 {
        sub_noborrow(&mut a, &b);
        a
    }

    spec sub {
        aborts_if value_of_U256(a) < value_of_U256(b);
        ensures value_of_U256(result) == value_of_U256(a) - value_of_U256(b);
    }

    #[test]
    #[expected_failure]
    fun test_sub_overflow() {
        let a = one();
        let b = from_u128(10);
        let _ = sub(a, b);
    }

    #[test]
    fun test_sub_ok() {
        let a = from_u128(10);
        let b = one();
        let ret = sub(a, b);
        assert!(compare(&ret, &from_u64(9)) == EQUAL, 0);
    }



    spec mul {
        pragma verify = false;
        pragma timeout = 200; // Take longer time
        aborts_if value_of_U256(a) * value_of_U256(b) >= P64 * P64 * P64 * P64;
        ensures value_of_U256(result) == value_of_U256(a) * value_of_U256(b);
    }

    #[test]
    fun test_mul() {
        let a = from_u128(10);
        let b = from_u64(10);
        let ret = mul(a, b);
        assert!(compare(&ret, &from_u64(100)) == EQUAL, 0);
    }

    #[test]
    fun test_mul2() {
        let a = from_u128(10000000);
        let b = from_u64(10000000);
        let ret = mul(a, b);
        assert!(compare(&ret, &from_u64(100000000000000)) == EQUAL, 0);
    }

    #[test]
    fun test_mul3() {
        let a = from_u128(10000000000000000000u128);
        let b = from_u128(10000000000000000000u128);
        let ret = mul(a, b);

        assert!(compare(&ret, &from_u128(100000000000000000000000000000000000000u128)) == EQUAL, 0);
    }

    #[test]
    #[expected_failure]
    fun test_mul_overflow() {
        let a = from_u128(340282366920938463463374607431768211455u128);
        let b = from_u128(340282366920938463463374607431768211455u128);
        let c = add(a, b);
        let _ret = mul(b, c);
    }

    /*public fun div(a: U256, b: U256): U256 {
        native_div(&mut a, &b);
        a
    }

    spec div {
        pragma verify = false;
        pragma timeout = 160; // Might take longer time
        aborts_if value_of_U256(b) == 0;
        ensures value_of_U256(result) == value_of_U256(a) / value_of_U256(b);
    }

    #[test]
    fun test_div() {
        let a = from_u128(10);
        let b = from_u64(2);
        let c = from_u64(3);
        // as U256 cannot be implicitly copied, we need to add copy keyword.
        assert!(compare(&div(copy a, b), &from_u64(5)) == EQUAL, 0);
        assert!(compare(&div(copy a, c), &from_u64(3)) == EQUAL, 0);
    }

    public fun rem(a: U256, b: U256): U256 {
        native_rem(&mut a, &b);
        a
    }

    spec rem {
        pragma verify = false;
        pragma timeout = 160; // Might take longer time
        aborts_if value_of_U256(b) == 0;
        ensures value_of_U256(result) == value_of_U256(a) % value_of_U256(b);
    }

    #[test]
    fun test_rem() {
        let a = from_u128(10);
        let b = from_u64(2);
        let c = from_u64(3);
        assert!(compare(&rem(copy a, b), &from_u64(0)) == EQUAL, 0);
        assert!(compare(&rem(copy a, c), &from_u64(1)) == EQUAL, 0);
    }

    public fun pow(a: U256, b: U256): U256 {
        native_pow(&mut a, &b);
        a
    }

    spec pow {
        // Verfication of Pow takes enormous amount of time
        // Don't verify it, and make it opaque so that the caller
        // can make use of the properties listed here.
        pragma verify = false;
        pragma opaque;
        pragma timeout = 600;
        let p = pow_spec(value_of_U256(a), value_of_U256(b));
        aborts_if p >= P64 * P64 * P64 * P64;
        ensures value_of_U256(result) == p;
    }

    #[test]
    fun test_pow() {
        let a = from_u128(10);
        let b = from_u64(1);
        let c = from_u64(2);
        let d = zero();
        assert!(compare(&pow(copy a, b), &from_u64(10)) == EQUAL, 0);
        assert!(compare(&pow(copy a, c), &from_u64(100)) == EQUAL, 0);
        assert!(compare(&pow(copy a, d), &from_u64(1)) == EQUAL, 0);
    }*/

    /// move implementation of native_add.
    fun add_nocarry(a: &mut U256, b: &U256) {
        let carry = 0;
        let idx = 0;
        let len = (WORD as u64);
        while (idx < len) {
            let a_bit = Vector::borrow_mut<u64>(&mut a.bits, idx);
            let b_bit = Vector::borrow<u64>(&b.bits, idx);
            *a_bit = Sender::Arith::adc(*a_bit, *b_bit, &mut carry);
            idx = idx + 1;
        };

        // check overflow
        assert!(carry == 0, 100);
    }

    /// move implementation of native_add.
    fun add_overflow_nocarry(a: & U256, b: &U256): (U256, bool) {
        let carry = 0;
        let idx = 0;
        let len = (WORD as u64);
        let c_bits = Vector::empty<u64>();
        while (idx < len) {
            let a_bit = Vector::borrow<u64>(&a.bits, idx);
            let b_bit = Vector::borrow<u64>(&b.bits, idx);
            let c_bit = Sender::Arith::adc(*a_bit, *b_bit, &mut carry);
            Vector::push_back(&mut c_bits, c_bit);
            idx = idx + 1;
        };

        // check overflow
        (U256{ bits: c_bits }, carry == 0)
    }

    #[test]
    #[expected_failure]
    fun test_add_nocarry_overflow() {
        let va = Vector::empty<u64>();
        Vector::push_back<u64>(&mut va, 15891);
        Vector::push_back<u64>(&mut va, 0);
        Vector::push_back<u64>(&mut va, 0);
        Vector::push_back<u64>(&mut va, 0);

        let vb = Vector::empty<u64>();
        Vector::push_back<u64>(&mut vb, 18446744073709535725);
        Vector::push_back<u64>(&mut vb, 18446744073709551615);
        Vector::push_back<u64>(&mut vb, 18446744073709551615);
        Vector::push_back<u64>(&mut vb, 18446744073709551615);

        let a = U256 { bits: va };
        let b = U256 { bits: vb };
        add_nocarry(&mut a, &b); // MVP thinks this won't abort
    }

    /// move implementation of native_sub.
    fun sub_noborrow(a: &mut U256, b: &U256) {
        let borrow = 0;
        let idx = 0;
        let len = (WORD as u64);
        while (idx < len) {
            let a_bit = Vector::borrow_mut<u64>(&mut a.bits, idx);
            let b_bit = Vector::borrow<u64>(&b.bits, idx);
            *a_bit = Sender::Arith::sbb(*a_bit, *b_bit, &mut borrow);
            idx = idx + 1;
        };

        // check overflow
        assert!(borrow == 0, 100);
    }
}
