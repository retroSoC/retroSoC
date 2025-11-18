#include <stdint.h>

unsigned long long __udivdi3(unsigned long long dividend, unsigned long long divisor) {
    // Handle division by zero case
    if (divisor == 0) return 0;

    // Fast path: dividend smaller than divisor
    if (dividend < divisor) return 0;

    // Fast path: divisor equals 1
    if (divisor == 1) return dividend;

    // Split 64-bit values into 32-bit parts
    uint32_t d_hi = (uint32_t)(divisor >> 32);
    uint32_t d_lo = (uint32_t)(divisor & 0xFFFFFFFF);
    uint32_t n_hi = (uint32_t)(dividend >> 32);
    uint32_t n_lo = (uint32_t)(dividend & 0xFFFFFFFF);

    // Case 1: Divisor is 32-bit
    if (d_hi == 0) {
        // 64-bit dividend divided by 32-bit divisor
        uint32_t rem_hi = n_hi % d_lo;
        uint64_t rem64 = ((uint64_t)rem_hi << 32) | n_lo;
        uint32_t quo_hi = n_hi / d_lo;
        uint32_t quo_lo = (uint32_t)(rem64 / divisor);

        return ((uint64_t)quo_hi << 32) | quo_lo;
    }

    // Case 2: Dividend's high 32 bits less than divisor's high 32 bits
    if (n_hi < d_hi) {
        return 0;
    }

    // Case 3: General algorithm
    // Calculate high quotient estimate
    uint32_t q_estimate = n_hi / d_hi;
    uint32_t r = n_hi % d_hi;

    // Compute intermediate value
    uint64_t u = ((uint64_t)r << 32) | n_lo;
    uint64_t product = (uint64_t)q_estimate * divisor;

    // Correct quotient estimate
    while (product > u) {
        q_estimate--;
        product -= divisor;
    }

    // Calculate final high quotient
    uint32_t q_hi = q_estimate;

    // Calculate low 32-bit quotient
    uint64_t remainder = u - product;
    uint32_t q_lo = (uint32_t)(remainder / divisor);

    return ((uint64_t)q_hi << 32) | q_lo;
}