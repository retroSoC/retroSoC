#!/bin/python

import sys
import os

sim_dir = { 'sim': 'behv', 'netsim': 'netl', 'postsim': 'post' }
tgt  = sys.argv[1]

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
MINI_DIR    = os.path.abspath(f'{SCRIPT_DIR}/..')
ROOT_DIR    = os.path.abspath(f'{MINI_DIR}/../..')
NORLASH_DIR = os.path.abspath(f'{MINI_DIR}/../ip/3rd-party/norflash')
SIM_DIR     = os.path.abspath(f'{MINI_DIR}/.iverilog_build/{sim_dir[tgt]}')


# check 
check_files = ['SECSI', 'SFDP', 'SREG', 'MEM']

try:
    dir_file_list = [
        fname for fname in os.listdir(SIM_DIR)
        if os.path.isfile(os.path.join(SIM_DIR, fname))
    ]
    
    missing_files = []
    for fname in check_files:
        if f'{fname}.TXT' not in dir_file_list:
            missing_files.append(fname)
    
    if not missing_files:
        print(f'contains all files')
    else:
        os.system(f'cp -rf {NORLASH_DIR}/*.TXT {SIM_DIR}')
        os.system(f'ln -sf {ROOT_DIR}/.sw_build/retrosoc_fw.hex {SIM_DIR}/MEM.TXT')
  
except PermissionError:
    print(f"ERROR: {SIM_DIR} has not permission")
except Exception as e:
    print(f"ERROR: unknown {str(e)}")