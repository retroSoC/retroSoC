#!/bin/python

import os

ROOT_PATH = os.getcwd()
print(f'ROOT_PATH: {ROOT_PATH}')

lines = ''
# remove parallel case statement
with open(f'{ROOT_PATH}/rtl/mini/filelist/inc.fl', 'r', encoding='utf-8') as fp:
    for v in fp:
        if '+incdir+..' in v:
            lines += v.replace('+incdir+..', f'+incdir+{ROOT_PATH}')
        else:
            lines += v

with open(f'{ROOT_PATH}/rtl/mini/filelist/inc_verilator.fl', 'w', encoding='utf-8') as fp:
    fp.writelines(lines)

os.system(f'cat {ROOT_PATH}/rtl/mini/filelist/inc_verilator.fl')