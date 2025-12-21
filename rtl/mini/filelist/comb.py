#!/bin/python

import sys
import os
from pathlib import Path


res = f'{Path(__file__).resolve().parent}/yosys.fl'

is_first = True

for v in sys.argv[1:]:
    if '-f' not in v:
        if 'pdk' in v: continue
        print(v)

        if is_first:
            os.system(f'cat {v} > {res}')
            is_first = False
        else:
            os.system(f'cat {v} >> {res}')
