#ifndef TINYLIB_H__
#define TINYLIB_H__

#define RAND_MAX 32768

int atoi(const char *str);
char *itoa(unsigned int val, char *str, int base);
void *malloc(size_t size);
void free(void *ptr);
int abs(int x);
int rand(void);
void srand(unsigned int seed);

#endif