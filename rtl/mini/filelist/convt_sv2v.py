#!/bin/python

import os
import sys
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MINI_DIR   = os.path.abspath(f'{SCRIPT_DIR}/..')
GEN_DIR    = os.path.abspath(f'{MINI_DIR}/.iverilog_build/behv')


sv2v_cmd = 'sv2v'

for v in sys.argv[1:]:
    if '-f' not in v:
        if 'pdk' in v: continue
        # print(f'filelist: {v}')
        try:
            result = subprocess.run(
                f"sed -e 's/+incdir+/-I/g' -e 's/+define+/-D/g' -e 's/^-v/-y/g' {v}",
                shell=True,
                capture_output=True,
                text=True,
                check=True
            )
            sed_output = result.stdout
            # print(sed_output.split('\n'))
            lines = sed_output.split('\n')
            for v in lines:
                if v != '':
                    sv2v_cmd = f'{sv2v_cmd} {v}'
        except Exception as e:
            print(f"fail：{str(e)}")


sv2v_cmd = f'{sv2v_cmd} --write {GEN_DIR}/converted_soc.v'
# print(f'sv2v_cmd: {sv2v_cmd}')
os.system(sv2v_cmd)