#!/bin/python

import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MINI_DIR   = os.path.abspath(f'{SCRIPT_DIR}/..')
GEN_DIR    = os.path.abspath(f'{MINI_DIR}/.generated_fl')

cmd      = ['+timescale+1ns/1ps\n']
filelist = ['def', 'sys_def', 'inc', 'tb']

for file in filelist:
    with open(f'{GEN_DIR}/{file}.fl', 'r', encoding='utf-8') as fp:
        tmp = fp.readlines()
        cmd += tmp
    
cmd += [f'{MINI_DIR}/.iverilog_build/behv/converted_soc.v\n']

pdk = sys.argv[1]
# print(f'PDK: {pdk}')
with open(f'{GEN_DIR}/pdk_{pdk.lower()}.fl', 'r', encoding='utf-8') as fp:
    tmp = fp.readlines()
    cmd += tmp
# print(cmd)

with open(f'{GEN_DIR}/iverilog.fl', 'w', encoding='utf-8') as fp:
    fp.writelines(cmd)

