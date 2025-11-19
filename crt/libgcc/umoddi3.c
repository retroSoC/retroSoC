#include <stdint.h>

unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor) {
    // Handle division by zero case
    if (divisor == 0) return 0;

    // Fast path: dividend smaller than divisor
    if (dividend < divisor) return dividend;

    // Fast path: divisor equals 1
    if (divisor == 1) return 0;

    // Fast path: divisor is power of two
    if ((divisor & (divisor - 1)) == 0) {
        return dividend & (divisor - 1);
    }

    // Split 64-bit values into 32-bit parts
    uint32_t d_hi = divisor >> 32;
    uint32_t d_lo = divisor & 0xFFFFFFFF;
    uint32_t n_hi = dividend >> 32;
    uint32_t n_lo = dividend & 0xFFFFFFFF;

    // Handle 32-bit divisor case
    if (d_hi == 0) {
        // 64-bit dividend divided by 32-bit divisor
        uint32_t rem_hi = n_hi % d_lo;
        uint64_t rem64 = ((uint64_t)rem_hi << 32) | n_lo;
        return rem64 % divisor;
    }

    // Handle case where dividend's high bits < divisor's high bits
    if (n_hi < d_hi) {
        return dividend;
    }

    // Calculate quotient and remainder
    uint32_t q = n_hi / d_hi;
    uint32_t r = n_hi % d_hi;

    // Compute intermediate remainder
    uint64_t u = ((uint64_t)r << 32) | n_lo;
    uint64_t rem = u - q * divisor;

    // Correction step
    while (rem >= divisor) {
        rem -= divisor;
    }

    return rem;
}