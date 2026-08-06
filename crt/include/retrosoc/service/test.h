#ifndef RETROSOC_SERVICE_TEST_H
#define RETROSOC_SERVICE_TEST_H

#include <stdint.h>

typedef enum { RS_TEST_FAILED = 0, RS_TEST_PASSED = 1 } rs_test_result_t;

void rs_test_finish(rs_test_result_t result, uint8_t code) __attribute__((noreturn));

#endif
