#!/bin/python

import os

ROOT_PATH = os.getcwd()

lines = ''
# remove parallel case statement
with open(f'{ROOT_PATH}/rtl/mini/core/picorv32.v', 'r', encoding='utf-8') as fp:
    for v in fp:
        if '// synopsys parallel_case' in v:
            lines += v.replace('// synopsys parallel_case', '')
        elif '// synopsys full_case parallel_case' in v:
            lines += v.replace('// synopsys full_case parallel_case', '')
        else:
            lines += v

with open(f'{ROOT_PATH}/rtl/mini/core/picorv32_ver.v', 'w', encoding='utf-8') as fp:
    fp.writelines(lines)