#!/bin/python

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


os.system(f'git clone --recursive --depth 1 https://github.com/IHP-GmbH/IHP-Open-PDK.git {SCRIPT_DIR}/IHP-Open-PDK')
os.system(f'git clone --recursive --depth 1 https://github.com/openecos-projects/icsprout55-pdk.git {SCRIPT_DIR}/icsprout55-pdk')
# os.system(f'git clone --recursive --depth 1 https://github.com/google/skywater-pdk.git {SCRIPT_DIR}/skywater-pdk')
# os.system(f'git clone --recursive --depth 1 https://github.com/google/gf180mcu-pdk.git {SCRIPT_DIR}/gf180mcu-pdk')
