int __ffssi2(unsigned int value) {
    static const char table[32] = {
        0, 1, 2, 24, 3, 19, 6, 25, 22, 4, 20, 10, 16, 7, 12, 26,
        31, 23, 18, 5, 21, 9, 15, 11, 30, 17, 8, 14, 29, 13, 28, 27
    };
    
    // calc LSB mask
    unsigned int mask = value & -value;
    
    // de bruijn sequence
    return table[(mask * 0x04D7651F) >> 27];
}