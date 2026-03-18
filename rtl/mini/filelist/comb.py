#!/bin/python

import sys
import os
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MINI_DIR   = os.path.abspath(f'{SCRIPT_DIR}/..')
GEN_DIR    = os.path.abspath(f'{MINI_DIR}/.generated_fl')

res = f'{GEN_DIR}/yosys.fl'
is_first = True

for v in sys.argv[1:]:
    if '-f' not in v:
        if 'pdk' in v: continue

        print(f'gen code: {v}')

        if is_first:
            os.system(f'cat {v} > {res}')
            is_first = False
        else:
            os.system(f'cat {v} >> {res}')
