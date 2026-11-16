/* reference-build shim for tests/c2cud: the linux.cudi output helpers, written with printf */
#include <stdio.h>
void put_i64(long v) { printf("%ld", v); }
void put_u64(unsigned long v) { printf("%lu", v); }
void nl(void) { printf("\n"); }
