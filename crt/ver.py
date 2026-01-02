#!/bin/python

import os
import subprocess

ROOT_PATH = os.getcwd()

def get_git_info():
    try:
        branch = subprocess.check_output(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            stderr=subprocess.STDOUT
        ).decode('utf-8').strip()

        # get full commit hash
        commit = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'],
            stderr=subprocess.STDOUT
        ).decode('utf-8').strip()[0:6]

        return branch, commit
    except subprocess.CalledProcessError:
        return None, None

branch, commit = get_git_info()
print(f"current branch: {branch}")
print(f"current commit: {commit}")
print(ROOT_PATH)

res = ''
with open(f'{ROOT_PATH}/crt/ver.tmpl', 'r', encoding='utf-8') as fp:
    file = fp.readlines()

    for line in file:
        if 'SOC_DEFAULT_BRANCH' in line:
            res += line.replace('SOC_DEFAULT_BRANCH', branch)
        elif 'SOC_DEFAULT_COMMIT' in line:
            res += line.replace('SOC_DEFAULT_COMMIT', commit)
        else:
            res += line

with open(f'{ROOT_PATH}/crt/inc/socver.h', 'w', encoding='utf-8') as fp:
    fp.writelines(res)