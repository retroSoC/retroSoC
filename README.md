# retroSoC

An open-source RISC-V SoC platform, from SystemVerilog RTL and firmware to reproducible verification and release artifacts.

| Information | | | |
| --- | --- | --- | --- |
| [![License](https://img.shields.io/badge/License-Mulan%20PSL%20v2-d4a72c?style=flat-square&labelColor=3b301a&logo=github&logoColor=f6d365)](LICENSE) | [![RTL](https://img.shields.io/badge/RTL-SystemVerilog-d4a72c?style=flat-square&labelColor=3b301a&logo=devbox&logoColor=f6d365)](rtl) | [![ISA](https://img.shields.io/badge/ISA-RV32IM+RV64GC-d4a72c?style=flat-square&labelColor=3b301a&logo=riscv&logoColor=f6d365)](configs/ci/ihp130.mk) | [![RISC-V GCC](https://img.shields.io/badge/RISC--V%20GCC-2025.05.01-d4a72c?style=flat-square&labelColor=3b301a&logo=c&logoColor=f6d365)](dependencies/dependencies.lock.json) |

| CI/CD Status | | | |
| --- | --- | --- | --- |
| [![ICS55 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ics55.yml?branch=main&style=flat-square&label=ICS55&&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA3NDUuOCA0MDIiPjxwYXRoIGZpbGw9IiNENDUxNTAiIGZpbGwtcnVsZT0iZXZlbm9kZCIgZD0ibTEwIDExLjZjMjQuOCAyNy4zIDQ4LjkgNjAuOSA2MSA4NC45IDIzIDQ1LjcgODguNiAxMDguMyAxMzkuNSAxMzMgNTcuNSAyOCAxMDggMzkuOCAxNzkgNDIgNDkuOSAxLjUgNTUuNyA0LjggNzQgNDIuNSA2IDEyLjIgMTkuOCA1OC40IDI0LjUgODEuN2wxLjEgNS44IDEzLjUgMCAxMy40IDAgMCAtMjkuOCAwIC0yOS43IC0xOS4xIC0yNWMtMTAuNiAtMTMuOCAtMjIuNCAtMjkuMyAtMjYuMyAtMzQuNiAtMy45IC01LjIgLTExLjggLTE1LjQgLTE3LjUgLTIyLjVsLTEwLjQgLTEzLjEgLTI5LjEgLTAuNmMtMTYgLTAuNCAtNDkuNyAtMC43IC03NC44IC0wLjdsLTQ1LjggMCAwIC0yNC40IDAgLTI0LjUgLTUuNyAtNC45Yy0xMS43IC05LjIgLTE0LjUgLTIwLjMgLTcuOCAtMzEuMiAxMSAtMTcuNiA0MS4zIC0xNCA0NS4yIDUuNSAyLjUgMTIuNCAwLjIgMTkuNiAtOC4xIDI2bC01LjYgNC4yIDAgMTUuOSAwIDE2IDcwIDAgNjkuOSAwIDkuMyAxMi4yYzUuMSA2LjggMjAuOCAyNy4zIDM1IDQ1LjdsMjUuOCAzMy4zIC0wLjIgLTI0LjIgLTAuMyAtMjQuMyAtOCAtNC45Yy05LjkgLTYuMSAtMTAuOSAtNy4xIC0yNS45IC0yOS44IC03Mi42IC0xMDkuNiAtMjA3LjQgLTE4NC45IC0zOTkuMSAtMjIyLjkgLTMxLjIgLTYuMiAtNzYuNyAtMTMuMSAtODYuMyAtMTMuMSAtMC43IDAgMy4zIDUgOC44IDExLjF6bTE0Ny4yIDIyLjhjMTcuMyA4LjMgMTkgMjguNiAzLjMgMzguOCAtNi4xIDQgLTYuMyA0LjYgLTYuNCAxNS45bC0wLjEgOSA2LjggMi44YzEyIDUuMSA0OSAxOS40IDU5LjUgMjMuMiA1LjYgMiAxMy43IDUuMiAxOCA3LjJsNy43IDMuNSAwIDIzLjIgMCAyMy4zIDUgMy4yYzIzLjMgMTQuOSA5LjcgNDcuNyAtMTcuNCA0MiAtMjMgLTQuNyAtMjYuOSAtMzEuNSAtNi4zIC00Mi41bDMuNyAtMiAwIC0xOS4zIDAgLTE5LjMgLTYuMiAtMi44Yy0zLjUgLTEuNSAtMjAuNSAtOC4xIC0zNy44IC0xNC42IC0xNy4zIC02LjQgLTM0LjkgLTEzLjMgLTM5LjEgLTE1LjJsLTcuNyAtMy41IC0wLjcgLTE0LjkgLTAuNyAtMTQuOCAtNC45IC0zLjJjLTI2LjcgLTE3LjEgLTUuMyAtNTMuOSAyMy4zIC00MHptLTE2LjQgOS43Yy02IDMuMiAtNy42IDEyLjEgLTMuMiAxNy4zIDUuOCA3IDE1LjggNS45IDE5LjggLTIuMiA0LjkgLTEwLjIgLTYuNiAtMjAuNiAtMTYuNiAtMTUuMXptOTIgMTUwYy04IDQuMyAtNy41IDE2LjkgMC44IDIwLjkgNy45IDMuNyAxNi40IC0xLjUgMTYuNCAtMTAuMiAwIC05LjcgLTkgLTE1LjIgLTE3LjIgLTEwLjd6bTYxLjYgLTMwLjNjLTYuOCA2LjIgLTQuOSAxNi4yIDMuOCAxOS41IDEzLjIgNSAyMS45IC0xNCA5LjggLTIxLjIgLTQuNiAtMi43IC05LjUgLTIuMSAtMTMuNiAxLjd6Ii8%2BPHBhdGggZmlsbD0iI0JEMUEyMSIgZmlsbC1ydWxlPSJldmVub2RkIiBkPSJtNzM1IDEyOS4xYy0xNi44IDExIC0yOC4zIDE0LjcgLTY3IDIxLjQgLTEyLjkgMi4zIC0yNy45IDUuMiAtMzMuMyA2LjYgLTU2LjUgMTQuMyAtOTEuOCA1NyAtOTEuNyAxMTAuOWwwIDggMy44IC00LjVjMTEuNiAtMTQuMSAzNS4xIC0zNyA0Ni42IC00NS40IDE3LjMgLTEyLjggNjEuNiAtMzUuOSA3OC42IC00MS4xIDMuOSAtMS4yIDIuMSAwLjUgLTI1IDI0LjUgLTMyLjUgMjguOCAtNDMuMyA0MC41IC04NC45IDkyLjUgLTIxLjEgMjYuMiAtMjIuMyAyNy41IC0yNS42IDI3LjUgLTIuNCAwIC0zLjUgOC4yIC0zLjUgMjQuNGwwIDYuMSA2LjEgLTYuN2MxMC41IC0xMS43IDIzLjEgLTE4LjggNjguNCAtMzkgNTguNCAtMjYgNzcuOCAtNDAuMyAxMTIgLTgyLjggMTQuMiAtMTcuNiAyMS41IC0zOS44IDI0LjUgLTc0IDEuMiAtMTMuNSAxLjMgLTM0IDAuMyAtMzQgLTAuNSAwIC00LjYgMi42IC05LjMgNS42eiIvPjwvc3ZnPg%3D%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ics55.yml) | [![IHP130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ihp130.yml?branch=main&style=flat-square&label=IHP130&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjcuOTMzIDcuMTE3IDMzMi42MTcgMzUwLjk2MiI%2BPHJlY3QgeD0iNy45MzMiIHk9IjU3LjQ0MSIgd2lkdGg9IjMwMC42NDYiIGhlaWdodD0iMzAwLjYzOCIgZmlsbD0iI0ZGRkZGRiIvPjxwYXRoIGZpbGw9IiNFNDE4MUEiIGQ9Ik03LjkgNTcuNGgzMDAuNnYxODAuNGMtMjQuNCAxNS4yLTY3LjkgMzAuOS0xMTAuOSA0My40YzAuMy0zLjcgMC41LTcuNCAwLjgtMTEuMmMzLjItMC44IDYuOC0xLjcgOC44LTIuM2MyMS40LTYuMiA0My43LTE0LjggNTguOC0zMS4zYzQuNy01LjIgNy4zLTExLjYgNi4xLTE3LjhjLTMuMy0xNi40LTI4LjctMjEuOC00NS40LTIxLjljLTkuOSAwLTE5LjYgMC4zLTI5LjEgMi4yYy0wLjYtMy4xLTEuMi02LjItMi05LjJjLTAuNC0xLjQtMS41LTEuNC0yLjgtMC44Yy0yLjYgMS4yLTQuNyA1LjEtNiA3LjRjLTAuNCAwLjYtMC4xIDEuMyAwLjMgMS45YzAuMyAwLjUgMC44IDEuNSAxLjMgM2MtMiAwLjYtMy45IDEuMy01LjkgMi4xYy0yLjQgMS0yLjYgMS41LTMuMSAyLjZjLTEuMyAzLjMtMS45IDkuOC0xLjMgMTEuNWMwLjMgMC45IDIuMSAxLjMgMi45IDAuN2MwLjctMC42IDQtMy4xIDkuNy01LjZjMCAwLjQgMC4xIDAuOCAwLjEgMS4zYzEuMiAxMC44IDEuMyAyMi40IDAuNyAzOS43Yy0wLjEgMi4zLTAuMiA0LjUtMC4zIDYuOGMtMS4zIDAtMi41IDAtMy43LTAuMWMtMy44LTAuNC03LjEtMS4yLTguMyAxLjhjLTAuOCAxLjktNS43IDguNS0yLjYgMTBjMi43IDEuMyA3LjcgMC45IDEzLjgtMC4yYy0wLjMgNC0wLjcgNy45LTEuMSAxMS45Yy0wLjcgMC4yLTEuNSAwLjQtMi4yIDAuNmMtMjcuNCA3LjctNTkuNyAxNC42LTg2LjcgMTdjLTE1LjYgMS40LTI1LjQtMS41LTM1LjMtOC44Yy03LjctNS43LTktMTguMy05LjUtMjNjLTEuMi0xMS4yIDAuMy0yMS42IDQuNS0zN2MxLjQtNS4yIDMuMi05LjcgNC4zLTExLjVjMS0xLjcgMS41LTMuNiAwLjQtNC43Yy0xLjctMS43LTQuNS01LTYuOC03Yy0xLjMtMS4yLTQuMS0wLjktNC45IDFjLTAuOCAxLjctMS40IDUtMi4yIDguMWMtMi42IDEwLjQtNiAyOS01LjQgNDIuNmMwLjYgMTMuMiAxLjkgMjcuMSAxMS45IDM3LjFjMTEuOCAxMS43IDI0LjkgMTQgNTAuNiAxMS4xYzI2LjMtMyA1Mi05LjUgODAuMy0xNy43Yy0yLjIgMTctNS40IDMzLjktOS41IDUwLjNjLTAuMyAxLjMtMC4zIDMuMiAxLjUgM2MyLjEtMC4yIDYuNy0yLjYgOS0zLjljMC44LTAuNSAxLjItMS4zIDEuMy0yYzMuMi0xOC41IDUuMS0zNC4zIDYuNS01MC4xYzIuMi0wLjcgNC41LTEuMyA2LjctMmMzMy4xLTkuOCA2NS41LTIxLjMgOTUuNC0zNC41YzIuOC0xLjIgNi4xLTIuOCA5LjQtNC40djExMEg3LjlWNTcuNHpNMTk5IDI1OS41YzcuMi0xLjMgMTUuNS0zLjcgMjMuNy02LjdjMTAuMi0zLjcgMjkuOC0xMi44IDM3LjYtMjIuMWM1LjItNi4zIDQuMy0xNC4yLTMuNS0xOC4xYy0xNC41LTcuNC0zNS40LTYuOC01MC4xLTQuNWMtMi44IDAuNC01LjMgMS03LjYgMS42YzEuMyAxMyAxLjEgMjYuNiAwLjUgMzguN0MxOTkuNCAyNTIuMiAxOTkuMiAyNTUuOSAxOTkgMjU5LjVNMjMwLjIgMTI5LjVsMTEwLjQtMTkuNUwzMjIuNCA3LjFMMjEyIDI2LjZMMjMwLjIgMTI5LjV6Ii8%2BPHBhdGggZmlsbD0iI0ZGRkZGRiIgZD0iTTg1LjIgMjczYzYuNC00NS42IDE4LjMtODkuMSAzNC43LTEyNy4xYzIuNS01LjcgNC41LTExLjEgNS42LTE0LjVjMS42LTQuNyA1LjMtMC40IDYuMiAwLjVjNC4zIDQuOCA1LjggNi4zIDMuMSAxMC4yYy0zLjYgNS4zLTkgMTcuNC0xMS45IDI0LjdjLTEzLjcgMzQuMi0xOC4zIDUzLjUtMjYuNyA5MS44YzguMi0xNS41IDI3LjUtNDMuMyAzOS4zLTUyLjNjNi45LTUuMyAyMi41LTEzLjEgMjguMSAzLjVjMy44IDExLjItMC4xIDQ0LjktNCA2NC4xYy0wLjIgMS0wLjIgMi45LTIuOCA0LjFjLTEgMC41LTQuOSAyLTYuNiAyLjVjLTAuOSAwLjItMi44IDAuMS0yLjItMi41YzMuOS0xOS42IDguOC00My4yIDcuMi02M2MtMC41LTYuMi0zLTEyLjEtMTUtMC44Yy0xNy45IDE2LjktMzcgNDYtNDUgNjIuOWMtMS4yIDIuNC0yLjggNC42LTQuOSA2LjVjLTEuNCAxLjMtNC41IDEuNC01LjItMi42Qzg0LjggMjc3LjggODUuMSAyNzMuOSA4NS4yIDI3MyIvPjxwYXRoIGZpbGw9IiNGRkZGRkYiIGQ9Ik03Ny44IDE1OC4xYzkuNiAwIDE3LjUgOCAxNy41IDE3LjhjMCA5LjgtNy45IDE3LjgtMTcuNSAxNy44cy0xNy41LTgtMTcuNS0xNy44QzYwLjMgMTY2LjEgNjguMiAxNTguMSA3Ny44IDE1OC4xIi8%2BPC9zdmc%2B)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ihp130.yml) | [![GF180 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-gf180.yml?branch=main&style=flat-square&label=GF180&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCEtLSBHbG9iYWxGb3VuZHJpZXMgZ3JhcGhpYyBtYXJrIG9ubHkgKHdvcmRtYXJrIGFuZCDCriByZW1vdmVkKS4KICAgICBPZmZpY2lhbCBvcmFuZ2UgI0ZGNjAxMiBmcm9tIHRoZSBjdXJyZW50IGdmLmNvbSBoZWFkZXIgc2ltcGxpZmllZCBsb2dvLgogICAgIFNvdXJjZSBwYWdlOiBodHRwczovL2dmLmNvbS8gICh0aGVtZSBhc3NldCBhbHNvIGF0CiAgICAgaHR0cHM6Ly9nZi5jb20vd3AtY29udGVudC90aGVtZXMvZ2YtMjAyNS9hc3NldHMvaW1hZ2VzL2dmLWxvZ28uc3ZnICkuIC0tPgo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgdmlld0JveD0iLTMuMzEyIC0zLjMxMiA4OS40MjQgODYuNjI0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9Ikdsb2JhbEZvdW5kcmllcyBtYXJrIj4KICA8cGF0aCBmaWxsPSIjRkY2MDEyIiBkPSJNNTQuMjAzIDBDNDEuNTk3IDAgMzEuMzggMTAuMjMyIDMxLjM4IDIyLjg1N1Y4MEM0My45ODYgODAgNTQuMjAzIDY5Ljc2OCA1NC4yMDMgNTcuMTQzVjBaTTI1LjY3NSAwQzExLjQ5MiAwIDAgMTEuNTA5IDAgMjUuNzE0QzAgMzkuOTE5IDExLjQ5MiA1MS40MjkgMjUuNjc1IDUxLjQyOVYwWk01OS45MDggNTEuNDI5SDgyLjczVjI4LjU3MUg1OS45MDhWNTEuNDI5Wk01OS45MDggMjIuODU3SDgyLjczVjBINTkuOTA4VjIyLjg1N1pNMi44NTMgNTcuMTQzSDI1LjY3NVY4MEMxMy4wNjkgODAgMi44NTMgNjkuNzY4IDIuODUzIDU3LjE0M1oiLz4KPC9zdmc%2BCg%3D%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml) | [![SKY130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-sky130.yml?branch=main&style=flat-square&label=SKY130&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9Ii01LjI0NiAtNS4yNDYgMTQxLjY0MyAxNDAuOTkyIj48ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9InNreUdyYWQxIiBncmFkaWVudFVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgeDE9IjgyLjgxMTkiIHkxPSI3MjYuMDgiIHgyPSI0OC4zMjE5IiB5Mj0iNjQyLjA1IiBncmFkaWVudFRyYW5zZm9ybT0ibWF0cml4KDEgMCAwIDEgLTUgLTYxOC4zMSkiPjxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzAwNjI4OCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iI0IyRDIzNSIvPjwvbGluZWFyR3JhZGllbnQ%2BPGxpbmVhckdyYWRpZW50IGlkPSJza3lHcmFkMiIgZ3JhZGllbnRVbml0cz0idXNlclNwYWNlT25Vc2UiIHgxPSIyMC4yNTU0IiB5MT0iNTM1LjYwOCIgeDI9IjYxLjE4NTQiIHkyPSI2NDYuODU4IiBncmFkaWVudFRyYW5zZm9ybT0ibWF0cml4KDEgMCAwIDEgLTUgLTYxOC4zMSkiPjxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzAwNjI4OCIvPjxzdG9wIG9mZnNldD0iMSIgc3RvcC1jb2xvcj0iI0IyRDIzNSIvPjwvbGluZWFyR3JhZGllbnQ%2BPC9kZWZzPjxwYXRoIGZpbGw9InVybCgjc2t5R3JhZDEpIiBkPSJNMTI0LDY5LjlINjEuN2MtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDQuNmMyLjYsMCw0LjgsMi4xLDQuOCw0LjggYzAsMi42LTIuMSw0LjgtNC44LDQuOEgzNS41Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDEuNmMzLjgtMC4xLDYuOC0zLjQsNi43LTcuMmMtMC4xLTMuNi0zLTYuNS02LjctNi43SDYuOSBjLTMuOC0wLjEtNywyLjgtNy4yLDYuN2MtMC4xLDMuOCwyLjgsNyw2LjcsNy4yYzAuMiwwLDAuNCwwLDAuNSwwaDExLjRjMi42LDAsNC44LDIuMSw0LjgsNC44YzAsMi42LTIuMSw0LjgtNC44LDQuOGgtMi43IGMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDQxLjhjMi42LDAsNC43LDIuMSw0LjgsNC44bDAsMGMwLDIuNi0yLjEsNC43LTQuOCw0LjhoLTljLTMuOCwwLTYuOSwzLjEtNi45LDYuOSBsMCwwYzAsMy44LDMuMSw2LjksNi45LDYuOWgzNC45YzMuOCwwLDYuOS0zLjEsNi45LTYuOWwwLDBjMC0zLjgtMy4xLTYuOS02LjktNi45aC05Yy0yLjYsMC00LjctMi4xLTQuOC00LjhsMCwwIGMwLTIuNiwyLjEtNC43LDQuOC00LjhIMTE0YzMuOCwwLjEsNy0yLjgsNy4yLTYuN2MwLjEtMy44LTIuOC03LTYuNy03LjJjLTAuMiwwLTAuNCwwLTAuNSwwaC05LjJjLTIuNiwwLTQuOC0yLjEtNC44LTQuOCBjMC0yLjYsMi4xLTQuOCw0LjgtNC44bDAsMGgxOS4yYzMuOCwwLDYuOS0zLjEsNi45LTYuOWMwLjEtMy43LTIuOC02LjgtNi42LTYuOUMxMjQuMiw2OS45LDEyNC4xLDY5LjksMTI0LDY5Ljl6IE05Mi41LDg4LjYgYzAsMi42LTIuMSw0LjctNC44LDQuOGgtNC41Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDQuNUM5MC40LDgzLjgsOTIuNSw4NS45LDkyLjUsODguNnoiLz48cGF0aCBmaWxsPSJ1cmwoI3NreUdyYWQyKSIgZD0iTTEyNCw0Ni43aC05LjVjLTIuNiwwLTQuOC0yLjEtNC44LTQuOGMwLTIuNiwyLjEtNC44LDQuOC00LjhoLTAuNGMzLjgsMC4xLDctMi44LDcuMi02LjdzLTIuOC03LTYuNy03LjIgYy0wLjIsMC0wLjQsMC0wLjUsMEg3NC42Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDljMy44LDAuMSw3LTIuOCw3LjItNi43cy0yLjgtNy02LjctNy4yYy0wLjIsMC0wLjQsMC0wLjUsMCBINDguNmMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDljMi42LDAsNC44LDIuMSw0LjgsNC44YzAsMi42LTIuMSw0LjgtNC44LDQuOGgtMC4xIGMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDAuMWMyLjYsMCw0LjgsMi4xLDQuOCw0LjhjMCwyLjYtMi4xLDQuOC00LjgsNC44SDM1LjVjLTIuNiwwLTQuOC0yLjEtNC44LTQuOCBjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDEuNmMzLjgsMC4xLDctMi44LDcuMi02LjdjMC4xLTMuOC0yLjgtNy02LjctNy4yYy0wLjIsMC0wLjQsMC0wLjUsMEgxNy4yYy0zLjgtMC4xLTcsMi44LTcuMiw2LjcgczIuOCw3LDYuNyw3LjJjMC4yLDAsMC40LDAsMC41LDBoMS4xYzIuNiwwLDQuOCwyLjEsNC44LDQuOGMwLDIuNi0yLjEsNC44LTQuOCw0LjhINi45Yy0zLjgsMC02LjksMy4yLTYuOSw3bDAsMCBjMCwzLjgsMy4xLDYuOSw2LjksNi45aDY5LjVjMy44LDAsNi45LTMuMSw2LjktNi45bDAsMGMwLTMuOC0zLjEtNy02LjktN2gtMi4yYy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDIyLjggYzIuNiwwLDQuOCwyLjEsNC44LDQuOGMwLDIuNi0yLjEsNC44LTQuOCw0LjhsMCwwbDAsMGMtMy44LDAtNi45LDMuMi02LjksN2wwLDBjMCwzLjgsMy4xLDYuOSw2LjksNi45aDI2LjZjMy44LDAsNi45LTMuMSw2LjktNi45IGwwLDBjMC4zLTMuNi0yLjQtNi43LTYtN0MxMjQuNSw0Ni43LDEyNC4yLDQ2LjcsMTI0LDQ2Ljd6Ii8%2BPC9zdmc%2B)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml) |
| [![Quality](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/quality.yml?branch=main&style=flat-square&label=Quality&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/quality.yml) | [![Nightly](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/nightly.yml?branch=main&style=flat-square&label=Nightly&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml) | | [![Nix/Docker](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/development-environment.yml?branch=main&style=flat-square&label=Nix%20Docker&logo=githubactions&logoColor=f6d365)](https://github.com/retroSoC/retroSoC/actions/workflows/development-environment.yml?query=branch%3Amain) |


[Overview](#platform-overview) · [Quick start](#quick-start) · [Configurations](#configurations-and-common-flows) · [Documentation](#documentation-and-repository) · [Validation](#validation-and-reproducibility) · [Contributing](#contributing)

## Platform overview

**Mini and Tiny have independent integration flows.** Mini combines a
low-power Hazard3 management hart and a T-Head OpenC906 application hart; its separate
MPW profile retains selectable-core compatibility. [Tiny](docs/ip/tiny-soc.md)
is a wired MCU with one Hazard3 RV32IMC hart, 128 KiB SRAM, AXI4/APB4 and no
wireless IP. Tiny defaults to ICS55 SAFE24 with a parked PLL and retains
IHP130 compatibility; [Std and Pro](docs/soc-family-positioning.md)
remain roadmap products. Qualification is determined by each profile's retained
verification and physical reports.

The [Tiny Gen1 datasheet](publications/datasheets/tiny/README.md) provides the
independent product, register, software and evidence reference using the
established publication layout. Its build does not require Mini's HP or
multimedia inputs.

| Area | Mini platform |
| --- | --- |
| Compute | Hazard3 LP management hart; locked pre-generated T-Head OpenC906 HP application hart. Baseline profiles compile LP firmware for RV32IM and use the OpenC906 DEFAULT RV64GC configuration with T-Head custom cache-maintenance instructions. |
| Memory and interconnect | Native AXI4 data plane, APB4 control, configurable on-chip SRAM, SDRAM, PSRAM/OPI-PSRAM, and XPI flash integration. |
| Control and I/O | GPIO, timers, UART, I2C, I2S, PWM, RTC, watchdog, storage interfaces, DMA, interrupt routing, and fixed EXT-L/EXT-H extension slots. |
| Software | Freestanding C runtime and HAL, board support, diagnostic and shell applications, CoreMark, and HP boot/bundle tooling. |
| Development | Locked toolchains and dependencies; Icarus Verilog and Verilator simulation, Yosys synthesis, OpenSTA timing analysis, and structured verification artifacts. |

The accelerator integrations include:

- **[APU](docs/ip/apu.md)** — LP-loaded audio microcode, WAV/PCM and native FLAC
  decoding, I2S streaming, and optional keyword spotting (KWS). MP3 decoding
  is deferred.
- **[NPU](docs/ip/npu.md)** — an INT8 inference engine with 64 dense MAC lanes,
  64 KiB of private banked SRAM, offline compilation, and bare-metal deployment.
- **[GA2D](docs/ip/ga2d.md)** — 2D fill, copy, pixel conversion, and alpha
  blending with opaque output and A8 foreground masks; no scaler or Linux driver.
- **[JPEG](docs/ip/jpeg.md) and [crypto](docs/ip/crypto.md)** — dedicated image
  and cryptographic blocks with their own interface and verification contracts.

Capabilities depend on the selected profile and each IP's implementation and
qualification status. Linux boot and performance qualification remain separate
from baseline CI coverage. The integrated RNG uses an unqualified deterministic
source for diagnostics; it does not provide production entropy. See the
[architecture](docs/lp-hp-architecture.md) and [engineering guide](docs/engineering.md)
for these boundaries.

## Quick start

### 1. Prepare the development environment

Use the [development environment guide](docs/development-environment.md) to
prepare the locked tools before building. The native environment targets
Linux x86_64. Docker supports a Linux/amd64 environment, including emulation
on Apple Silicon; Nix support is Linux x86_64 only.

| Environment | Setup instructions |
| --- | --- |
| Docker | [Build and enter the development image](docs/development-environment.md#docker). |
| Nix | [Open the repository development shell](docs/development-environment.md#nix). |
| Manual Ubuntu 22.04 | [Bootstrap and activate the locked tools](docs/development-environment.md#shared-bootstrap). |

For manual Ubuntu installs, first install the host packages from the
`apt-get install` list in [docker/Dockerfile](docker/Dockerfile), including
Java 17. The bootstrap checks these tools but does not install OS packages.

Tools and checkout inputs are separate: the environment provides compilers and
EDA tools, while `make setup` retrieves the profile's managed sources, PDK,
and application inputs. Tool versions come from the
[dependency lock](dependencies/dependencies.lock.json).

### 2. Build and simulate Mini

From the repository root, inside the prepared environment:

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG setup
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG doctor
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG firmware sim
```

This runs the IHP130 profile's manual `bringup` application. It is not the
exact PR regression: automated Verilator runs select `ci_smoke`, while Icarus
regressions use the assembly self-test. See
[supported flows](docs/engineering.md#supported-profiles) for the overrides.

Keep `firmware sim` in the same Make invocation so both use one build variant.
Outputs live under `build/<profile>-<YYYY-MM-DD-HH-MM>-<config-hash>/`.
Check the flow logs and result JSON; UART startup text alone is not a pass.

### Build and simulate Tiny

```sh
make CONFIG=configs/ci/ihp130-tiny.mk setup
make CONFIG=configs/ci/ihp130-tiny.mk doctor
make CONFIG=configs/ci/ihp130-tiny.mk firmware sim
make CONFIG=configs/ci/ihp130-tiny.mk SIMU=IVERILOG firmware sim
```

Tiny uses its own source lists and product maps under `rtl/tiny`. Its firmware
loads into on-chip SRAM without PSRAM/SDRAM initialization. The first release
uses a fixed 24 MHz clock and disables atomic instructions. Wireless, external
RAM, HP cores, accelerators and advanced low-power modes remain deferred.

## Configurations and common flows

Start from a [committed profile](configs/README.md). These are selected entry
points, not the complete profile or application inventory.

| Profile | Purpose |
| --- | --- |
| [ICS55 Tiny](configs/ci/ics55-tiny.mk) | Default Tiny platform: 128 KiB SRAM, SAFE24 boot, PLL present but held off. |
| [IHP130 Tiny](configs/ci/ihp130-tiny.mk) | Explicit Tiny compatibility, 128 KiB SRAM, 24 MHz/no PLL. |
| [IHP130 Mini](configs/ci/ihp130.mk) | Manual bring-up with 32 KiB macro-backed SRAM. |
| [GF180](configs/ci/gf180.mk) / [SKY130](configs/ci/sky130.mk) | Alternative PDK profiles with 32 KiB macro-backed SRAM. |
| [ICS55 Mini](configs/ci/ics55.mk) | Regression-compatible Mini profile with locked SRAM and PLL disabled. |
| [Interactive shell](configs/ci/ihp130-shell.mk) | Shell firmware with CSR support enabled. |
| [Hazard3 debug](configs/ci/ihp130-debug.mk) | JTAG acceptance using Verilator, OpenOCD, and GDB. |
| [HP Linux](configs/ci/ihp130-hp.mk) | LP RV32IM / HP RV64IMAFDC Linux image/bundle flow and HP RTL validation; outside the supported PR matrix. |
| [HP RT-Thread](configs/ci/ihp130-rtthread.mk) | Locked RT-Thread v5.3.0 M-mode kernel/platform acceptance on HP hart 1. |
| [APU LP/HP](configs/ci/ihp130-apu.mk) | Audio and KWS evidence flow with ownership handoff to HP. |
| [CoreMark](configs/benchmark/ihp130-hazard3-coremark.mk) | Fixed LP SRAM benchmark with the RV64 product HP core present. |
| [Mini MPW](configs/cluster/mini-mpw.mk) | Legacy MPW C0-C3/user-IP compatibility, separate from the product ABI. |

Tiny's [2026-10-07 target refreeze](docs/ip/tiny-soc.md#ics55-default-platform-and-final-timing-gate-2026-10-07)
selects ICS55 with `HAVE_PLL=YES` and SAFE24 startup as the default.
The PLL starts parked off. The [R2-P7 implementation](docs/ip/tiny-soc-r2-clock-reset.md)
adds software-controlled SYS transitions; acceptance evidence is tracked in
the Tiny ledger and physical qualification remains pending. IHP130 remains
explicit compatibility.
Locked PLL views can be acquired
with `python3 physical/pdk/setup.py --pdk ICS55 --component pll` independently
of platform implementation or timing qualification.

After the corresponding setup, use these common commands:

```sh
# Build the interactive shell firmware
make CONFIG=configs/ci/ihp130-shell.mk firmware

# Inspect the effective configuration and available targets
make CONFIG=configs/ci/ihp130.mk config
make help

# Check source formatting and embedded C policy/host tests
make format-check
make sw-policy-check sw-host-test

# Run the shared fast quality and agent-control checks
make check-fast

# Inspect the deterministic changed-file validation matrix
make validation-plan
```

| Validation flow | Command |
| --- | --- |
| IHP130 smoke: RTL lint, firmware, SVA compilation, Icarus self-test | `make regress-smoke` |
| IHP130 behavioral flows, including debug acceptance | `make regress-rtl` |
| Full local PR matrix across four PDKs | `make regress-pr` |
| Extended local regression | `make regress-nightly` |

Prepare the multi-PDK inputs with `make setup-regression` before the full PR
matrix. PR regressions keep the Icarus assembly self-test, while the multi-hour
Tiny P7 Icarus acceptance command runs in dedicated nightly jobs for IHP130 and
ICS55. Profile setup does not install every optional reference corpus; follow
any additional prerequisites in the affected IP or test guide. For debugging,
benchmarks, and HP software, use the dedicated guides linked below.

<details>
<summary>Advanced local flows: netlist simulation and licensed VCS</summary>

These flows require the relevant synthesis/timing tools and PDK inputs, or a
licensed VCS environment. Keep one timestamp across dependent commands:

```sh
export BUILD_TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG RTL_SIM_TIMEOUT=5200000 sim-asm
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS synth
make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG \
  SIM_FIRMWARE_NAME=retrosoc_asm RTL_SIM_TIMEOUT=5200000 netsim
make CONFIG=configs/ci/ihp130.mk STA=OPENSTA sta
```

VCS defaults to `bsub -Is` for licensed cluster runs. Disable LSF for a licensed
local run, or set `VCS_RUNNER` to the site's wrapper:

```sh
make CONFIG=configs/ci/ihp130.mk SIMU=VCS VCS_USE_LSF=NO firmware sim
```

After this sequence, `unset BUILD_TIMESTAMP` to restore automatic timestamps.
See [build layout](docs/engineering.md#build-layout) and
[result policy](docs/engineering.md#result-policy) for artifacts and verdicts.

</details>

## Documentation and repository

| Start here | Guides |
| --- | --- |
| Understand the platform | [LP/HP architecture](docs/lp-hp-architecture.md), [IP specifications](docs/ip/README.md), [datasheet workflow](publications/README.md). |
| Develop firmware | [SDK](crt/README.md), [applications](app/README.md), [HP software](app/ports/linux/README.md). |
| Debug and measure | [Hazard3 debug](docs/hazard3-debug.md), [CoreMark](docs/coremark.md), [engineering workflow](docs/engineering.md). |
| Change RTL or tooling | [RTL conventions](docs/rtl-coding-style.md), [MISRA policy](docs/misra-c-2012.md), [agent contract](AGENTS.md). |
| Explore further | [Documentation index](docs/README.md), [build profiles](configs/README.md), [contribution process](CONTRIBUTING.md). |

| Directory | Contents |
| --- | --- |
| [rtl/](rtl/README.md) | SoC integration, IP, interfaces, simulation, and technology wrappers. |
| [crt/](crt/README.md) / [app/](app/README.md) | Freestanding SDK, firmware applications, and software integrations. |
| [configs/](configs/README.md) / [dependencies/](dependencies/README.md) | Reproducible profiles and locked external inputs. |
| [tests/](tests/README.md) / [scripts/](scripts/README.md) / [quality/](quality/README.md) | Verification, build helpers, and executable quality policy. |
| [physical/](physical/README.md) / [fpga/](fpga/README.md) | Physical-design flows and FPGA integration. |
| [docs/](docs/README.md) / [publications/](publications/README.md) | Engineering specifications and manually built datasheets. |
| [.github/](.github/GUIDE.md) / [docker/](docker/README.md) | Automation and the container development environment. |

## Validation and reproducibility

The status badges above track **`main`**, not the current checkout. Other runs:
[GF180](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml),
[ICS55](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ics55.yml),
[SKY130](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml),
and [nightly](https://github.com/retroSoC/retroSoC/actions/workflows/nightly.yml).

The quality gate checks source policy and runs script/RTL fixture tests.
Hosted SoC regression and development-environment workflows use
`--behavioral-only`: they do not run the full SoC synthesis, netlist simulation,
or OpenSTA stages. Local full-flow commands retain those stages. Neither CI
status nor core timing analysis establishes physical or silicon signoff.

Dependencies and tool archives are pinned by revision or checksum. Each build
variant records its configuration and lock digest, and EDA flows produce logs
and structured results. Warning and metric policies remain defined by the
[engineering guide](docs/engineering.md); no performance claim is implied by
a badge. Maintainer-published `v*` tags trigger
[release packaging](docs/engineering.md#ci-and-releases), including the source
archive, manifest, dependency lock, SBOM, and checksums.

## Contributing

Start with the [contribution guide](CONTRIBUTING.md), follow the
[Git workflow](docs/git-workflow.md), and use the
[PR template](.github/pull_request_template.md). Ordinary contributions target
`dev` and preserve meaningful commits through merge-commit integration.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

retroSoC is licensed under [Mulan PSL v2](LICENSE). Third-party terms are
recorded in [NOTICE](NOTICE), [ATTRIBUTIONS](ATTRIBUTIONS.md), and
[licenses/](licenses/README.md). See the existing [security policy](Security.md)
for its current reporting information.

Thanks to everyone contributing to retroSoC.

[![retroSoC contributors](https://contrib.rocks/image?repo=retroSoC/retroSoC)](https://github.com/retroSoC/retroSoC/graphs/contributors)

## Star History

<a href="https://www.star-history.com/?repos=retrosoc%2Fretrosoc&type=date&logscale=&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=retrosoc/retrosoc&type=date&theme=dark&legend=bottom-right" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=retrosoc/retrosoc&type=date&legend=bottom-right" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=retrosoc/retrosoc&type=date&legend=bottom-right" />
 </picture>
</a>
