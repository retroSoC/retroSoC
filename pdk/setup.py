#!/bin/python

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


os.system(f'git clone --recursive https://github.com/IHP-GmbH/IHP-Open-PDK.git {SCRIPT_DIR}/IHP-Open-PDK')
os.system(f'cd {SCRIPT_DIR}/IHP-Open-PDK && git checkout 68eebafcd9b2f5e92c69d37a8d3d90eb266550f5')
os.system(f'git clone --recursive https://github.com/google/skywater-pdk.git {SCRIPT_DIR}/skywater-pdk')
os.system(f'git clone --recursive https://github.com/google/gf180mcu-pdk.git {SCRIPT_DIR}/gf180mcu-pdk')
