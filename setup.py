#!/usr/bin/env python3

import sys
import os

project_path = os.getcwd()
os.chdir(project_path)
os.system("git clone https://github.com/retroSoC/mini-ver-mpw.git rtl/mini/mpw")
