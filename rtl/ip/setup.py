#!/bin/python

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

os.system(f'git clone https://github.com/retroSoC/3rd-party.git {SCRIPT_DIR}/3rd-party')
