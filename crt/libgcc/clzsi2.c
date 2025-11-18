int __clzsi2(unsigned int value) {
    if (value == 0) return 32;
    
    // keep MSB
    value |= value >> 1;
    value |= value >> 2;
    value |= value >> 4;
    value |= value >> 8;
    value |= value >> 16;
    value = (value >> 1) + 1;
    
    // de bruijn sequence
    static const int deBruijn[32] = {
        0,  9,  1, 10, 13, 21,  2, 29,
        11, 14, 16, 18, 22, 25,  3, 30,
        8, 12, 20, 28, 15, 17, 24,  7,
        19, 27, 23,  6, 26,  5,  4, 31
    };
    
    return 31 - deBruijn[(value * 0x07C4ACDDU) >> 27];
}