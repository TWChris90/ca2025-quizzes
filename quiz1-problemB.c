#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef uint8_t uf8;

static inline unsigned clz(uint32_t x)
{
    int n = 32, c = 16;
    do {
        uint32_t y = x >> c;
        if (y) {
            n -= c;
            x = y;
        }
        c >>= 1;
    } while (c);
    return n - x;
}

/* Decode uf8 to uint32_t */
uint32_t uf8_decode(uint8_t fl) {
    uint32_t m = fl & 0x0F;               // m
    uint32_t e = fl >> 4;                  // e
    uint32_t offset = (1u << (e + 4)) - 16u;
    return offset + (m << e);
}

/* Encode uint32_t to uf8 */
uf8 uf8_encode(uint32_t v) {
    if (v < 16u) return (uf8)v;

    unsigned lz = clz(v);
    int msb     = 31 - (int)lz;

    // 1) start from e0 = clamp(msb - 4, 0..15)
    int e = msb - 4;
    if (e < 0)  e = 0;
    if (e > 15) e = 15;

    // 2) closed-form segment starts
    uint32_t offset0 = (1u << (e + 4)) - 16u;                   // start of e
    uint32_t next    = (e < 15) ? ((1u << (e + 5)) - 16u)
                                : UINT32_MAX;                   // start of e+1 (or +¡Û)

    // 3) decide e with two comparisons ¡÷ e ? {e-1, e, e+1}
    if (v < offset0) {
        e -= 1;
        if (e < 0) { e = 0; offset0 = 0u; }
        else       { offset0 = (1u << (e + 4)) - 16u; }
    } else if (v >= next) {
        e += 1;
        if (e > 15) e = 15;
        offset0 = (1u << (e + 4)) - 16u;
    }

    // 4) in-segment index
    uint32_t m = (v - offset0) >> e;                            // floor
    return (uf8)((e << 4) | (m & 0x0F));
}

/* Test encode/decode round-trip */
static bool test(void)
{
    int32_t previous_value = -1;
    bool passed = true;

    for (int i = 0; i < 256; i++) {
        uint8_t fl = i;
        int32_t value = uf8_decode(fl);
        uint8_t fl2 = uf8_encode(value);

        if (fl != fl2) {
            printf("%02x: produces value %d but encodes back to %02x\n", fl,
                   value, fl2);
            passed = false;
        }

        if (value <= previous_value) {
            printf("%02x: value %d <= previous_value %d\n", fl, value,
                   previous_value);
            passed = false;
        }

        previous_value = value;
    }

    return passed;
}

int main(void)
{
    if (test()) {
        printf("All tests passed.\n");
        return 0;
    }
    return 1;
}
