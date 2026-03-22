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


tgt  = sys.argv[1]
pdk  = sys.argv[2]
netl = sys.argv[3]
print(f'tgt: {tgt}')
print(f'pdk: {pdk}')
print(f'netl: {netl}')

if tgt == 'sim':
    cmd += [f'{MINI_DIR}/.iverilog_build/behv/converted_soc.v\n']

elif tgt == 'netsim':
    with open(f'{GEN_DIR}/commonip.fl', 'r', encoding='utf-8') as fp:
        tmp = fp.readlines()
        cmd += tmp
    cmd += f'{netl}\n'

elif tgt == 'postsim':
    pass

with open(f'{GEN_DIR}/pdk_{pdk.lower()}.fl', 'r', encoding='utf-8') as fp:
      tmp = fp.readlines()
      cmd += tmp

with open(f'{GEN_DIR}/iverilog.fl', 'w', encoding='utf-8') as fp:
    fp.writelines(cmd)

