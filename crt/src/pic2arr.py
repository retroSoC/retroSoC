#!/bin/python

# import os

res_8b = []
res_16b = []

for i in range(0, 100):
    print(i + 1)
    with open(f'./pic/batch/{i+1}.c', 'r', encoding='utf-8') as fp:
        for v in fp:
            if '0X' in v and 'const' not in v:
                tmp = v.rstrip('\n').split(',')[:-1]
                res_8b += tmp

print(f'res_8b list len: {len(res_8b)}')

# print(res_8b[0])
# print(res_8b[0] + res_8b[1])
# print(res_8b[2])
# print(res_8b[3])

for i in range(0, len(res_8b) - 1, 2):
    res_16b.append(res_8b[i+1] + res_8b[i][2:])

# print(res_16b)
print(f'res_16b list len: {len(res_16b)}')

with open('video.h', 'w', encoding='utf-8') as fp:
    fp.write('uint16_t only_my_railgun[][32400] = {')
    is_first = True
    for v in res_16b:
        if (is_first):
            fp.write(v)
            is_first = False
        fp.write(f',{v}')
    fp.write('};')

# print(res_8b[:2])
