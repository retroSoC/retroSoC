#!/bin/python

import os
import glob
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(f'{SCRIPT_DIR}/../../..')
RTL_DIR    = os.path.abspath(f'{SCRIPT_DIR}/../..')
MINI_DIR   = os.path.abspath(f'{SCRIPT_DIR}/..')
GEN_DIR    = os.path.abspath(f'{MINI_DIR}/.generated_fl')




def process_fl_files(folder_path):
    # source files
    pdk_patn  = re.compile(r'^(/(pdk))')
    rtl_patn  = re.compile(r'^(/(clusterip|ip|tech))')
    mini_patn = re.compile(r'^(/(core|mpw|tb|top))')
    # incdir
    inc_pdk_patn  = re.compile(r'^(\+incdir\+)(/(pdk))')
    inc_rtl_patn  = re.compile(r'^(\+incdir\+)(/(clusterip|ip|tech))')
    inc_mini_patn = re.compile(r'^(\+incdir\+)(/(core|mpw|tb|top))')

    msg_files = glob.glob(os.path.join(folder_path, "*.fl"))
    if not msg_files:
        print("no files found")
        return
    
    for msg_file in msg_files:
        try:
            with open(msg_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()

            processed_lines = []
            for line in lines:
                pdk_repl  = f'{ROOT_DIR}' + r'\1'
                rtl_repl  = f'{RTL_DIR}' + r'\1'
                mini_repl = f'{MINI_DIR}' + r'\1'

                inc_pdk_repl  = r'\1' + f'{ROOT_DIR}' + r'\2'
                inc_rtl_repl  = r'\1' + f'{RTL_DIR}' + r'\2'
                inc_mini_repl = r'\1' + f'{MINI_DIR}' + r'\2'

                new_line = pdk_patn.sub(pdk_repl, line)
                new_line = rtl_patn.sub(rtl_repl, new_line)
                new_line = mini_patn.sub(mini_repl, new_line)
                new_line = inc_pdk_patn.sub(inc_pdk_repl, new_line)
                new_line = inc_rtl_patn.sub(inc_rtl_repl, new_line)
                new_line = inc_mini_patn.sub(inc_mini_repl, new_line)

                processed_lines.append(new_line)
            
            with open(msg_file, 'w', encoding='utf-8') as f:
                f.writelines(processed_lines)

        except FileNotFoundError:
            print(f"ERROR: file {msg_file} is not found")
        except PermissionError:
            print(f"ERROR: file {msg_file} is not permission")
        except Exception as e:
            print(f"ERROR: file {msg_file} unknown {str(e)}")

def process_lint_files(folder_path):
    # source files
    pdk_patn  = re.compile(r'(\,)(/(pdk))')
    rtl_patn  = re.compile(r'(\,)(/(clusterip|ip|tech))')
    mini_patn = re.compile(r'(\,)(/(core|mpw|tb|top))')
    first_patn = re.compile(r'(\=)(/(core|mpw|tb|top))')


    msg_files = glob.glob(os.path.join(folder_path, "*.msg"))
    if not msg_files:
        print("no files found")
        return
    
    for msg_file in msg_files:
        try:
            with open(msg_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()

            processed_lines = []
            for line in lines:
                pdk_repl  = r'\1' + f'{ROOT_DIR}' + r'\2'
                rtl_repl  = r'\1' + f'{RTL_DIR}' + r'\2'
                mini_repl = r'\1' + f'{MINI_DIR}' + r'\2'
                first_repl = r'\1' + f'{MINI_DIR}' + r'\2'

                # seq is important!
                new_line = pdk_patn.sub(pdk_repl, line)
                new_line = rtl_patn.sub(rtl_repl, new_line)
                new_line = mini_patn.sub(mini_repl, new_line)
                new_line = first_patn.sub(first_repl, new_line)

                processed_lines.append(new_line)
            
            with open(msg_file, 'w', encoding='utf-8') as f:
                f.writelines(processed_lines)

        except FileNotFoundError:
            print(f'ERROR: file {msg_file} is not found')
        except PermissionError:
            print(f'ERROR: file {msg_file} has not permission')
        except Exception as e:
            print(f'ERROR: file {msg_file} unknown {str(e)}')


print('generate filelists')
os.system(f'mkdir -p {GEN_DIR}')
os.system(f'cp -rf {RTL_DIR}/filelist/pdk_*.fl {GEN_DIR}')
os.system(f'cp -rf {RTL_DIR}/mini/filelist/*.fl {GEN_DIR}')
os.system(f'cp -rf {RTL_DIR}/mini/lint.msg {GEN_DIR}')

process_fl_files(GEN_DIR)
process_lint_files(GEN_DIR)