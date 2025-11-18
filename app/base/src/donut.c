// Copyright 2025 ECOS Team
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

#include <firmware.h>
#include <tinystring.h>
#include <tinyprintf.h>
#include <tinyqspi.h>
#include <tinylcd.h>

#define likely(x)   __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)
#define GRAY_LEVELS 12
// screen framebuffer (128x128)
#define scale_x 8
#define scale_y 8
#define DONUT_SIZE 16
#define DONUT_WIDTH  DONUT_SIZE * scale_x
#define DONUT_HEIGHT DONUT_SIZE * scale_y

const uint32_t gray_colors[GRAY_LEVELS] = {
    0x00000000,  // black (' ')
    0x10821082,  // dark gray ('.')
    0x21042104,  // Dark gray(',')
    0x31863186,  // darker gray ('-')
    0x42084208,  // medium dark gray ('~')
    0x528A528A,  // medium gray(':')
    0x630C630C,  // medium bright gray (';')
    0x738E738E,  // lighter gray ('=')
    0x84108410,  // bright gray('!')
    0x94929492,  // very bright gray ('*')
    0xA514A514,  // extremely bright gray ('#')
    0xB596B596   // brightest gray ('$')
};

uint32_t donut_framebuffer_32[DONUT_WIDTH * DONUT_HEIGHT];

// void screen_clear(void) {
//     memset(donut_framebuffer_32, 0x00, sizeof(donut_framebuffer_32));
// }

// inline marco
#define R_OPT(mul,shift,x,y) \
  do { \
    int _temp = x; \
    x -= mul*y>>shift; \
    y += mul*_temp>>shift; \
    _temp = (3145728-x*x-y*y)>>11; \
    x = x*_temp>>10; \
    y = y*_temp>>10; \
  } while(0)

// trigonometric function table (1024 = 1.0) - reserve 91 values
// static const int16_t sin_table[91] = {
//     0, 18, 36, 54, 71, 89, 107, 125, 143, 160, 178, 195, 213, 230, 248, 265, 282, 299, 316, 333, 350, 367, 384, 400, 416, 433, 449, 465, 481, 496, 512, 527, 542, 557, 572, 587, 601, 615, 629, 643, 657, 670, 683, 696, 709, 721, 733, 745, 757, 768, 779, 790, 801, 811, 821, 831, 841, 850, 859, 868, 876, 884, 892, 900, 907, 914, 921, 927, 933, 939, 945, 950, 955, 960, 964, 968, 972, 975, 978, 981, 984, 986, 988, 990, 991, 992, 993, 994, 994, 995, 995
// };

// static const int16_t cos_table[91] = {
//     1024, 1023, 1023, 1022, 1021, 1019, 1017, 1014, 1011, 1007, 1003, 998, 993, 987, 981, 974, 967, 959, 951, 942, 933, 923, 913, 902, 891, 879, 867, 854, 841, 827, 813, 798, 783, 767, 751, 734, 717, 699, 681, 662, 643, 623, 603, 582, 561, 539, 517, 494, 471, 447, 423, 398, 373, 347, 321, 294, 267, 239, 211, 182, 153, 123, 93, 62, 31, 0, -31, -62, -93, -123, -153, -182, -211, -239, -267, -294, -321, -347, -373, -398, -423, -447, -471, -494, -517, -539, -561, -582, -603, -623, -643
// };

static uint32_t pixel_buffer[DONUT_SIZE * DONUT_SIZE];
static signed char z_buffer[DONUT_SIZE * DONUT_SIZE];

static inline void fast_pixel_write(uint32_t color, int x, int y) {
    if (likely(x >= 0 && x < DONUT_SIZE && y >= 0 && y < DONUT_SIZE)) {
        int index = y * DONUT_SIZE + x;
        pixel_buffer[index] = color;
    }
}

static inline void fast_scaled_pixel_write(uint32_t color, int x, int y) {
    if (likely(x >= 0 && x < DONUT_SIZE && y >= 0 && y < DONUT_SIZE)) {
        int scaled_x = x * scale_x;
        int scaled_y = y * scale_y;
        
        int base_index = scaled_y * DONUT_WIDTH + scaled_x;
        
        int row_index = base_index;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;
        
        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;
        
        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;
        
        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;

        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;

        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;

        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;

        row_index += DONUT_WIDTH;
        donut_framebuffer_32[row_index/2] = color;
        donut_framebuffer_32[row_index/2 + 1] = color;
        donut_framebuffer_32[row_index/2 + 2] = color;
        donut_framebuffer_32[row_index/2 + 3] = color;

    }
}

void donut() {
    register int sA = 1024, cA = 0, sB = 1024, cB = 0;
    
    const int R1 = 1, R2 = 1024, K2 = 4096*1024;
    const int screen_center_x = DONUT_SIZE/2, screen_center_y = DONUT_SIZE/2;
    const int scale_x_val = 12, scale_y_val = 12;

    while(1) {
        // clean buffer
        uint32_t *pixel_ptr = (uint32_t*)pixel_buffer;
        uint32_t *z_ptr = (uint32_t*)z_buffer;
        uint32_t *fb_ptr = (uint32_t*)donut_framebuffer_32;

        // clean zero
        for (int i = 0; i < (DONUT_SIZE*DONUT_SIZE)/2; i++) {
            pixel_ptr[i] = 0;
        }

        // init z-buffer
        for (int i = 0; i < (DONUT_SIZE*DONUT_SIZE)/4; i++) {
            z_ptr[i] = 0x7F7F7F7F;  // 127 in each byte
        }

        // clean zero
        for (int i = 0; i < (DONUT_WIDTH*DONUT_HEIGHT)/2; i++) {
            fb_ptr[i] = 0;
        }

        int sj = 0, cj = 1024;
        for (int j = 0; j < 90; j++) {
            int si = 0, ci = 1024;
            
            for (int i = 0; i < DONUT_SIZE*DONUT_SIZE; i++) {
                int x0 = R1*cj + R2;
                int x1 = ci*x0 >> 10;
                int x2 = cA*sj >> 10;
                int x3 = si*x0 >> 10;
                int x4 = R1*x2 - (sA*x3 >> 10);
                int x5 = sA*sj >> 10;
                int x6 = K2 + R1*1024*x5 + cA*x3;
                int x7 = cj*si >> 10;

                int x = screen_center_x + (scale_x_val*(cB*x1 - sB*x4)) / x6;
                int y = screen_center_y + (scale_y_val*(cB*x4 + sB*x1)) / x6;

                int N = (((-cA*x7 - cB*((-sA*x7>>10) + x2) - ci*(cj*sB >> 10)) >> 10) - x5) >> 7;

                if (likely(y > 0 && y < DONUT_SIZE && x > 0 && x < DONUT_SIZE)) {
                    int o = x + DONUT_SIZE * y;
                    signed char zz = (x6-K2)>>15;
                    if (likely(zz < z_buffer[o])) {
                        z_buffer[o] = zz;
                        uint32_t color = gray_colors[N > 0 ? N : 0];
                        pixel_buffer[o] = color;
                    }
                }
                R_OPT(5, 8, ci, si);
            }
            R_OPT(9, 7, cj, sj);
        }

        R_OPT(5, 7, cA, sA);
        R_OPT(5, 8, cB, sB);
        for (int y = 0; y < DONUT_SIZE; y++) {
            for (int x = 0; x < DONUT_SIZE; x++) {
                int index = x + DONUT_SIZE * y;
                uint32_t color = pixel_buffer[index];
                if (likely(color != 0)) {
                    fast_scaled_pixel_write(color, x, y);
                }
            }
        }

        lcd_fill_image(0, 0, DONUT_WIDTH, DONUT_HEIGHT, donut_framebuffer_32);
    }
}

void donut_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("donut test\n");
    donut();
}