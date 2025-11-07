#include <libdef.h>
#include <tinylib.h>

static unsigned long int rand_nxt = 1;

int atoi(const char *str) {
    int x = 0;
    while (*str == ' ') { str++; }
    while (*str >= '0' && *str <= '9') {
      x = x * 10 + *str - '0';
      str++;
    }
    return x;
}

char *itoa(unsigned int val, char *str, int base) {
  char *p = str;
  while(val) {
    int tmp = val % base;
    if(tmp <= 9)
      *p++ = '0' + tmp;
    else
      *p++ = 'A' + tmp - 10;
    val /= base;
  }
  for(char *i = str, *j = p - 1; i < p; ++i, --j) {
    if(i >= j) break;
    char tmp = *i;
    *i = *j;
    *j = tmp;
  }
  *p = 0;
  return str;
}

void *malloc(size_t size) {
    // static void *program_break = 0;
    // if (program_break == 0) {
    //   if (heap.start == 0) return 0;
    //   program_break = heap.start;
    // }
    // size = (size + 15) & ~15;
    // void *mem = program_break;
    // program_break += size;
    // //assert(program_break <= heap.end, "Run out of memory");
    // return mem;
    (void) size;
    return NULL;
}

void free(void *ptr) {
    (void) ptr;
}

int abs(int x) {
    return (x < 0 ? -x : x);
}

int rand(void) {
  rand_nxt = rand_nxt * 1103515245 + 12345;
  return (unsigned int)(rand_nxt/65536) % RAND_MAX;
}

void srand(unsigned int seed) {
  rand_nxt = seed;
}