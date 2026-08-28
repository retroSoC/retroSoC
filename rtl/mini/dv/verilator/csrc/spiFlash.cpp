#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stdlib.h>
#include <cstring>
#include <svdpi.h>

#define Assert(cond, ...) \
  do { \
    if (!(cond)) { \
      fflush(stdout); \
      fprintf(stderr, "\33[1;31m"); \
      fprintf(stderr, __VA_ARGS__); \
      fprintf(stderr, "\33[0m\n"); \
      assert(cond); \
    } \
  } while (0)

#define FLASH_SIZE (256 * 1024 * 1024) // 256MB
#define PAGE_SIZE  4096
#define PG_ALIGN   __attribute((aligned(PAGE_SIZE)))

static inline bool in_flash(uint64_t addr) { return addr < FLASH_SIZE; }
static uint8_t flash[FLASH_SIZE] PG_ALIGN = {};
static bool fast_mode = false;

extern "C" void flash_read(uint32_t addr, uint32_t *data) {
  if (!data) return;
  Assert(in_flash((uint64_t)addr + sizeof(*data) - 1U), "Flash address 0x%x out of bound", addr);
  *data = *(uint32_t *)(flash + addr);
}

extern "C" void flash_read_byte(uint32_t addr, uint8_t *data) {
  if (!data) return;
  Assert(in_flash(addr), "Flash address 0x%x out of bound", addr);
  *data = flash[addr];
}

extern "C" svBit flash_fast_enabled(void) { return fast_mode ? 1U : 0U; }

extern "C" void flash_set_fast_mode(bool enable) { fast_mode = enable; }

extern "C" void flash_init(char *img) {
  FILE *fp = fopen(img, "rb");
  Assert(fp, "can not open '%s'", img);
  fseek(fp, 0, SEEK_END);
  uint64_t size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  Assert(size <= FLASH_SIZE, "Flash image is too large: %llu bytes", (unsigned long long)size);
  assert(fread(flash, size, 1, fp) == 1);
  fclose(fp);
}

extern "C" void flash_memcpy(uint8_t* src, size_t len) {
  memcpy(flash, src, len);
}
