# Count consecutive mov %rN,D(%rbp) / mov D(%rbp),%rN pairs (store then reload).
import re, sys
asm = open(sys.argv[1]).read().splitlines()
n = 0
for i in range(len(asm) - 1):
    a, b = asm[i].strip(), asm[i + 1].strip()
    m = re.match(r"mov (%r\w+),(-?\d+)\(%rbp\)$", a)
    if m and b == "mov {}(%rbp),{}".format(m.group(2), m.group(1)):
        n += 1
print(n)
