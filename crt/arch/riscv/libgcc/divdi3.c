#include <stdbool.h>
#include <stdint.h>

unsigned long long __udivdi3(unsigned long long dividend, unsigned long long divisor);
long long __divdi3(long long dividend, long long divisor);

long long __divdi3(long long dividend, long long divisor) {
    const bool dividend_negative = dividend < 0;
    const bool divisor_negative = divisor < 0;
    const unsigned long long unsigned_dividend =
        dividend_negative ? 0U - (unsigned long long)dividend : (unsigned long long)dividend;
    const unsigned long long unsigned_divisor =
        divisor_negative ? 0U - (unsigned long long)divisor : (unsigned long long)divisor;
    const unsigned long long quotient = __udivdi3(unsigned_dividend, unsigned_divisor);

    if (unsigned_divisor == 0U) {
        return 0;
    }
    return (dividend_negative != divisor_negative) ? (long long)(0U - quotient)
                                                   : (long long)quotient;
}
