long long __divdi3(long long dividend, long long divisor) {
    if (divisor == 0) return 0;

    // Handle special overflow case
    if (dividend == (-9223372036854775807LL - 1) && divisor == -1) {
        return dividend;
    }

    // Handle signs
    int sign = 1;
    if (dividend < 0) {
        sign = -sign;
        dividend = -dividend;
    }
    if (divisor < 0) {
        sign = -sign;
        divisor = -divisor;
    }

    // Shift and subtract algorithm
    long long quotient = 0;
    long long remainder = 0;

    for (int i = 63; i >= 0; i--) {
        remainder = (remainder << 1) | ((dividend >> i) & 1);

        if (remainder >= divisor) {
            remainder -= divisor;
            quotient |= (1LL << i);
        }
    }

    return sign < 0 ? -quotient : quotient;
}