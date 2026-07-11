#include <stdint.h>

unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor);

unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor) {
    unsigned long long quotient_bit = 1U;

    if (divisor == 0U) {
        return 0U;
    }
    while ((divisor <= dividend) && ((divisor & (1ULL << 63U)) == 0U)) {
        divisor <<= 1U;
        quotient_bit <<= 1U;
    }
    while (quotient_bit != 0U) {
        if (dividend >= divisor) {
            dividend -= divisor;
        }
        divisor >>= 1U;
        quotient_bit >>= 1U;
    }
    return dividend;
}
