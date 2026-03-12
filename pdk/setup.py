#!/bin/python

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


os.system(f'git clone --depth 1 https://github.com/IHP-GmbH/IHP-Open-PDK.git {SCRIPT_DIR}/IHP-Open-PDK')
os.system(f'cd {SCRIPT_DIR}/IHP-Open-PDK && git checkout 6ecd4ad0bb27c5150cf17e474c8f595c42fa44e2 && git submodule init && cd ..')
os.system(f'git clone --recursive --depth 1 https://github.com/openecos-projects/icsprout55-pdk.git {SCRIPT_DIR}/icsprout55-pdk')
