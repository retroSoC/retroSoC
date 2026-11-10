# retroSoC

An open-source RISC-V SoC platform, from SystemVerilog RTL and firmware to reproducible verification and release artifacts.

| Information | | | |
| --- | --- | --- | --- |
| [![License](https://img.shields.io/badge/License-Mulan%20PSL%20v2-d4a72c?style=flat-square&labelColor=3b301a&logo=github&logoColor=f6d365)](LICENSE) | [![RTL](https://img.shields.io/badge/RTL-SystemVerilog-d4a72c?style=flat-square&labelColor=3b301a&logo=devbox&logoColor=f6d365)](rtl) | [![ISA](https://img.shields.io/badge/ISA-RV32IM+RV64GC-d4a72c?style=flat-square&labelColor=3b301a&logo=riscv&logoColor=f6d365)](configs/ci/ihp130.mk) | [![RISC-V GCC](https://img.shields.io/badge/RISC--V%20GCC-2025.05.01-d4a72c?style=flat-square&labelColor=3b301a&logo=c&logoColor=f6d365)](dependencies/dependencies.lock.json) |

| CI/CD Status | | | |
| --- | --- | --- | --- |
| [![ICS55 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ics55.yml?branch=main&style=flat-square&label=ICS55&&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA3NDUuOCA0MDIiPjxwYXRoIGZpbGw9IiNENDUxNTAiIGZpbGwtcnVsZT0iZXZlbm9kZCIgZD0ibTEwIDExLjZjMjQuOCAyNy4zIDQ4LjkgNjAuOSA2MSA4NC45IDIzIDQ1LjcgODguNiAxMDguMyAxMzkuNSAxMzMgNTcuNSAyOCAxMDggMzkuOCAxNzkgNDIgNDkuOSAxLjUgNTUuNyA0LjggNzQgNDIuNSA2IDEyLjIgMTkuOCA1OC40IDI0LjUgODEuN2wxLjEgNS44IDEzLjUgMCAxMy40IDAgMCAtMjkuOCAwIC0yOS43IC0xOS4xIC0yNWMtMTAuNiAtMTMuOCAtMjIuNCAtMjkuMyAtMjYuMyAtMzQuNiAtMy45IC01LjIgLTExLjggLTE1LjQgLTE3LjUgLTIyLjVsLTEwLjQgLTEzLjEgLTI5LjEgLTAuNmMtMTYgLTAuNCAtNDkuNyAtMC43IC03NC44IC0wLjdsLTQ1LjggMCAwIC0yNC40IDAgLTI0LjUgLTUuNyAtNC45Yy0xMS43IC05LjIgLTE0LjUgLTIwLjMgLTcuOCAtMzEuMiAxMSAtMTcuNiA0MS4zIC0xNCA0NS4yIDUuNSAyLjUgMTIuNCAwLjIgMTkuNiAtOC4xIDI2bC01LjYgNC4yIDAgMTUuOSAwIDE2IDcwIDAgNjkuOSAwIDkuMyAxMi4yYzUuMSA2LjggMjAuOCAyNy4zIDM1IDQ1LjdsMjUuOCAzMy4zIC0wLjIgLTI0LjIgLTAuMyAtMjQuMyAtOCAtNC45Yy05LjkgLTYuMSAtMTAuOSAtNy4xIC0yNS45IC0yOS44IC03Mi42IC0xMDkuNiAtMjA3LjQgLTE4NC45IC0zOTkuMSAtMjIyLjkgLTMxLjIgLTYuMiAtNzYuNyAtMTMuMSAtODYuMyAtMTMuMSAtMC43IDAgMy4zIDUgOC44IDExLjF6bTE0Ny4yIDIyLjhjMTcuMyA4LjMgMTkgMjguNiAzLjMgMzguOCAtNi4xIDQgLTYuMyA0LjYgLTYuNCAxNS45bC0wLjEgOSA2LjggMi44YzEyIDUuMSA0OSAxOS40IDU5LjUgMjMuMiA1LjYgMiAxMy43IDUuMiAxOCA3LjJsNy43IDMuNSAwIDIzLjIgMCAyMy4zIDUgMy4yYzIzLjMgMTQuOSA5LjcgNDcuNyAtMTcuNCA0MiAtMjMgLTQuNyAtMjYuOSAtMzEuNSAtNi4zIC00Mi41bDMuNyAtMiAwIC0xOS4zIDAgLTE5LjMgLTYuMiAtMi44Yy0zLjUgLTEuNSAtMjAuNSAtOC4xIC0zNy44IC0xNC42IC0xNy4zIC02LjQgLTM0LjkgLTEzLjMgLTM5LjEgLTE1LjJsLTcuNyAtMy41IC0wLjcgLTE0LjkgLTAuNyAtMTQuOCAtNC45IC0zLjJjLTI2LjcgLTE3LjEgLTUuMyAtNTMuOSAyMy4zIC00MHptLTE2LjQgOS43Yy02IDMuMiAtNy42IDEyLjEgLTMuMiAxNy4zIDUuOCA3IDE1LjggNS45IDE5LjggLTIuMiA0LjkgLTEwLjIgLTYuNiAtMjAuNiAtMTYuNiAtMTUuMXptOTIgMTUwYy04IDQuMyAtNy41IDE2LjkgMC44IDIwLjkgNy45IDMuNyAxNi40IC0xLjUgMTYuNCAtMTAuMiAwIC05LjcgLTkgLTE1LjIgLTE3LjIgLTEwLjd6bTYxLjYgLTMwLjNjLTYuOCA2LjIgLTQuOSAxNi4yIDMuOCAxOS41IDEzLjIgNSAyMS45IC0xNCA5LjggLTIxLjIgLTQuNiAtMi43IC05LjUgLTIuMSAtMTMuNiAxLjd6Ii8%2BPHBhdGggZmlsbD0iI0JEMUEyMSIgZmlsbC1ydWxlPSJldmVub2RkIiBkPSJtNzM1IDEyOS4xYy0xNi44IDExIC0yOC4zIDE0LjcgLTY3IDIxLjQgLTEyLjkgMi4zIC0yNy45IDUuMiAtMzMuMyA2LjYgLTU2LjUgMTQuMyAtOTEuOCA1NyAtOTEuNyAxMTAuOWwwIDggMy44IC00LjVjMTEuNiAtMTQuMSAzNS4xIC0zNyA0Ni42IC00NS40IDE3LjMgLTEyLjggNjEuNiAtMzUuOSA3OC42IC00MS4xIDMuOSAtMS4yIDIuMSAwLjUgLTI1IDI0LjUgLTMyLjUgMjguOCAtNDMuMyA0MC41IC04NC45IDkyLjUgLTIxLjEgMjYuMiAtMjIuMyAyNy41IC0yNS42IDI3LjUgLTIuNCAwIC0zLjUgOC4yIC0zLjUgMjQuNGwwIDYuMSA2LjEgLTYuN2MxMC41IC0xMS43IDIzLjEgLTE4LjggNjguNCAtMzkgNTguNCAtMjYgNzcuOCAtNDAuMyAxMTIgLTgyLjggMTQuMiAtMTcuNiAyMS41IC0zOS44IDI0LjUgLTc0IDEuMiAtMTMuNSAxLjMgLTM0IDAuMyAtMzQgLTAuNSAwIC00LjYgMi42IC05LjMgNS42eiIvPjwvc3ZnPg%3D%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ics55.yml) | [![IHP130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-ihp130.yml?branch=main&style=flat-square&label=IHP130&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCEtLSBPZmZpY2lhbCBJSFAgbG9nbyAod2l0aG91dCBjbGFpbSkuIFNvdXJjZToKICAgICBodHRwczovL3d3dy5paHAtbWljcm9lbGVjdHJvbmljcy5jb20vX2Fzc2V0cy8wN2Y0M2Y3NjRmZDM0NTU3M2QwMWMzZmE2MWFiODZkNS9JbWFnZXMvSUhQLUxvZ28tb2huZS1jbGFpbS5zdmcKICAgICBNZWRpYSBwYWdlOiBodHRwczovL3d3dy5paHAtbWljcm9lbGVjdHJvbmljcy5jb20vbmV3cy0yL21lZGlhdGhlay9paHAtbG9nb3MKICAgICBPZmZpY2lhbCBmaWxscyAjRTQxODFBIC8gI0ZGRkZGRjsgcGF0aHMgdW5jaGFuZ2VkIGV4Y2VwdCBkZWNpbWFsIGNvbXBhY3RpbmcuIC0tPgo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgdmlld0JveD0iNy45MzMgNy4xMTcgMzMyLjYxNyAzNTAuOTYyIiByb2xlPSJpbWciIGFyaWEtbGFiZWw9IklIUCI%2BCiAgPHJlY3QgeD0iNy45MzMiIHk9IjU3LjQ0MSIgd2lkdGg9IjMwMC42NDYiIGhlaWdodD0iMzAwLjYzOCIgZmlsbD0iI0ZGRkZGRiIvPgogIDxwYXRoIGZpbGw9IiNFNDE4MUEiIGQ9Ik03LjkzMyw1Ny40NDFoMzAwLjY0NnYxODAuNDMxYy0yNC4zOTMsMTUuMjE3LTY3Ljg2MSwzMC44NzYtMTEwLjkzNyw0My40MjEgYzAuMjc3LTMuNzAzLDAuNTI5LTcuNDI2LDAuNzYtMTEuMjA3YzMuMjI5LTAuODAxLDYuODI4LTEuNzQ5LDguODI2LTIuMzMxYzIxLjM3My02LjIwOSw0My42ODMtMTQuODI1LDU4Ljc2MS0zMS4yODYgYzQuNzI3LTUuMTYzLDcuMzItMTEuNjI5LDYuMDc5LTE3LjgxMmMtMy4yOTctMTYuNDA5LTI4LjcwMi0yMS44MjItNDUuNDQtMjEuODk0Yy05LjkxNC0wLjA0NC0xOS41OSwwLjM0Ny0yOS4wNjEsMi4xNzIgYy0wLjU2MS0zLjE0Ni0xLjIzNS02LjIxNC0yLjA0OS05LjE2OGMtMC4zNzItMS4zNTgtMS40NzEtMS40MjItMi44MzMtMC43NzVjLTIuNjAyLDEuMjM3LTQuNzA1LDUuMDYyLTYuMDQ3LDcuMzg3IGMtMC4zNjEsMC42MjItMC4xMTcsMS4yNjksMC4yNjksMS44OTFjMC4zMjEsMC41MTQsMC43NzQsMS40NzQsMS4yNzIsMi45OTFjLTEuOTc3LDAuNjEtMy45NDUsMS4zMDItNS45MDUsMi4wODMgYy0yLjQyNywwLjk2MS0yLjYxNSwxLjQ1Ni0zLjA3OCwyLjYyOGMtMS4yOTQsMy4zMTItMS44NjMsOS43OTctMS4zMjUsMTEuNDc1YzAuMjg0LDAuODkyLDIuMDk3LDEuMzQ2LDIuODgsMC43MTIgYzAuNzQyLTAuNjEsMy45NTEtMy4wOTUsOS43MTUtNS41NjljMC4wNDksMC40MTEsMC4wOTgsMC44NCwwLjE0NiwxLjI3NmMxLjE5MywxMC44MDEsMS4yNzgsMjIuNDI0LDAuNjg4LDM5LjcxNyBjLTAuMDc3LDIuMjU0LTAuMTc0LDQuNTE3LTAuMjkxLDYuNzcyYy0xLjMwNywwLjAzOS0yLjUzMSwwLjAxMy0zLjY1Ni0wLjA5OGMtMy44MjctMC4zNjMtNy4xMTUtMS4yMDUtOC4zNDUsMS43OTUgYy0wLjc2NSwxLjg2NC01Ljc0Myw4LjQ3Ny0yLjU3MywxMC4wMDhjMi43MTIsMS4zMDcsNy42NywwLjkxNiwxMy44MDgtMC4xOTJjLTAuMzIsMy45Ni0wLjcsNy45MjEtMS4xMzgsMTEuODY2IGMtMC43MzIsMC4yMTMtMS40NjcsMC40MTYtMi4yMDMsMC42MjFjLTI3LjM2Nyw3LjY2NC01OS42ODgsMTQuNjQ2LTg2LjY2OCwxNy4wMjljLTE1LjU1MSwxLjM3Ny0yNS4zODItMS40OTYtMzUuMzAxLTguNzk3IGMtNy43My01LjY4OC05LjAwMi0xOC4yODUtOS40OTgtMjMuMDA4Yy0xLjE3Ni0xMS4xODgsMC4yNjUtMjEuNjExLDQuNTAzLTM2Ljk2OGMxLjQ0My01LjIzNCwzLjIzLTkuNjU2LDQuMjgtMTEuNDcgYzEuMDA4LTEuNzM1LDEuNTQ3LTMuNTY4LDAuMzkxLTQuNzRjLTEuNjk3LTEuNzE5LTQuNTQ0LTUuMDI0LTYuNzgtNy4wMDNjLTEuMzQ2LTEuMTkyLTQuMDc5LTAuODY1LTQuOTM0LDAuOTc5IGMtMC43NzEsMS42NjctMS4zOTQsNC45NzMtMi4xNzksOC4wNTRjLTIuNjM5LDEwLjM2LTYuMDEzLDI5LjAwNS01LjM5NSw0Mi41NzVjMC42MDYsMTMuMjQ5LDEuOTM0LDI3LjEzNCwxMS45MzgsMzcuMDg1IGMxMS43OTMsMTEuNzM3LDI0LjkwOCwxNC4wNDMsNTAuNjQ2LDExLjA5MmMyNi4yOTItMy4wMTksNTEuOTY1LTkuNTIyLDgwLjI3NC0xNy42OTFjLTIuMTk5LDE3LjA0OC01LjQxOSwzMy45MTgtOS40NTMsNTAuMzE2IGMtMC4zMjMsMS4zMTMtMC4yOTMsMy4xNzYsMS40NjcsMy4wMzVjMi4xMDQtMC4xNTgsNi42ODktMi41NjgsOS4wMzQtMy44NzVjMC44MDEtMC40NTEsMS4xODUtMS4yOTcsMS4zMDQtMS45OTQgYzMuMTcyLTE4LjUxNyw1LjEzNC0zNC4zMTQsNi40OTYtNTAuMDU5YzIuMjI5LTAuNjYsNC40NzMtMS4zMiw2LjczNC0xLjk5MmMzMy4wNjYtOS44MDMsNjUuNTM1LTIxLjM0OCw5NS40LTM0LjQ4OCBjMi44MjEtMS4yNDIsNi4wODQtMi43NSw5LjQxOC00LjM5NnYxMTAuMDRINy45MzNWNTcuNDQxeiBNMTk5LDI1OS40NTdjNy4xNjUtMS4yNjIsMTUuNTIyLTMuNzIzLDIzLjY4OC02LjcwMiBjMTAuMjEzLTMuNzE1LDI5Ljc5My0xMi43NjMsMzcuNTYzLTIyLjEyM2M1LjIwOC02LjI3OSw0LjI3OC0xNC4xNTItMy40OTEtMTguMTMzYy0xNC40ODQtNy40MTEtMzUuMzc3LTYuODEtNTAuMTAzLTQuNDgzIGMtMi43NzEsMC40NDItNS4zMTMsMC45OTItNy42MzQsMS42MjFjMS4yODQsMTIuOTg2LDEuMDY0LDI2LjYwOCwwLjUxMiwzOC43NDlDMTk5LjM2MywyNTIuMTcyLDE5OS4xODcsMjU1Ljg1MiwxOTksMjU5LjQ1NyBNMjMwLjE3MywxMjkuNTI1bDExMC4zNzctMTkuNDYzTDMyMi4zOTUsNy4xMTdMMjEyLjAyMSwyNi41ODJMMjMwLjE3MywxMjkuNTI1eiIvPgogIDxwYXRoIGZpbGw9IiNGRkZGRkYiIGQ9Ik04NS4yNDEsMjcyLjk1NWM2LjQyNS00NS42MzksMTguMzExLTg5LjExNSwzNC43NDktMTI3LjEzM2MyLjQ1NC01LjY3Myw0LjQ5LTExLjA1NCw1LjYxNi0xNC40NTggYzEuNTYtNC43MjksNS4zLTAuNDM3LDYuMTY0LDAuNTM4YzQuMjYsNC43OTYsNS44Myw2LjI4MywzLjE0OCwxMC4xODljLTMuNjA1LDUuMjU0LTguOTU1LDE3LjM1NC0xMS45MDIsMjQuNzMgYy0xMy42NzUsMzQuMjEzLTE4LjMwNCw1My40NzMtMjYuNzExLDkxLjc1YzguMjM3LTE1LjUxNSwyNy41MzQtNDMuMjc3LDM5LjM0Ni01Mi4zMzRjNi44NTctNS4yNTMsMjIuNTQ0LTEzLjA4MywyOC4xMywzLjUzNyBjMy43NzUsMTEuMjMxLTAuMTI3LDQ0LjktMy45NjMsNjQuMDY0Yy0wLjIwOCwxLjAzOC0wLjIxOSwyLjg4OS0yLjc3Niw0LjA5M2MtMC45ODEsMC40Ny00LjkwMiwyLjAzMS02LjYzNywyLjUxMyBjLTAuOTAzLDAuMjUtMi43NSwwLjEwOS0yLjIzNy0yLjQ4NmMzLjg3OS0xOS42NDUsOC44MDEtNDMuMjM5LDcuMjA1LTYyLjk1NWMtMC41MDMtNi4yMTctMi45NzQtMTIuMTIxLTE0Ljk4NS0wLjg0NiBjLTE3Ljk0OCwxNi44NS0zNi45NjIsNDUuOTU5LTQ0Ljk4OSw2Mi44NTRjLTEuMTU5LDIuNDM0LTIuODQ2LDQuNjMyLTQuODUyLDYuNTA5Yy0xLjM4MSwxLjI4OC00LjU0NCwxLjM4Ni01LjIwNC0yLjYwNiBDODQuODMzLDI3Ny44MTIsODUuMTE1LDI3My44NTksODUuMjQxLDI3Mi45NTUiLz4KICA8cGF0aCBmaWxsPSIjRkZGRkZGIiBkPSJNNzcuODA3LDE1OC4xNDljOS42MzEsMCwxNy40ODQsNy45ODIsMTcuNDg0LDE3Ljc2NmMwLDkuNzkxLTcuODU0LDE3Ljc2Ni0xNy40ODQsMTcuNzY2IHMtMTcuNDgzLTcuOTc1LTE3LjQ4My0xNy43NjZDNjAuMzIzLDE2Ni4xMzEsNjguMTc2LDE1OC4xNDksNzcuODA3LDE1OC4xNDkiLz4KPC9zdmc%2BCg%3D%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-ihp130.yml) | [![GF180 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-gf180.yml?branch=main&style=flat-square&label=GF180&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCEtLSBHbG9iYWxGb3VuZHJpZXMgZ3JhcGhpYyBtYXJrIG9ubHkgKHdvcmRtYXJrIGFuZCDCriByZW1vdmVkKS4KICAgICBPZmZpY2lhbCBvcmFuZ2UgI0ZGNjAxMiBmcm9tIHRoZSBjdXJyZW50IGdmLmNvbSBoZWFkZXIgc2ltcGxpZmllZCBsb2dvLgogICAgIFNvdXJjZSBwYWdlOiBodHRwczovL2dmLmNvbS8gICh0aGVtZSBhc3NldCBhbHNvIGF0CiAgICAgaHR0cHM6Ly9nZi5jb20vd3AtY29udGVudC90aGVtZXMvZ2YtMjAyNS9hc3NldHMvaW1hZ2VzL2dmLWxvZ28uc3ZnICkuIC0tPgo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgdmlld0JveD0iLTMuMzEyIC0zLjMxMiA4OS40MjQgODYuNjI0IiByb2xlPSJpbWciIGFyaWEtbGFiZWw9Ikdsb2JhbEZvdW5kcmllcyBtYXJrIj4KICA8cGF0aCBmaWxsPSIjRkY2MDEyIiBkPSJNNTQuMjAzIDBDNDEuNTk3IDAgMzEuMzggMTAuMjMyIDMxLjM4IDIyLjg1N1Y4MEM0My45ODYgODAgNTQuMjAzIDY5Ljc2OCA1NC4yMDMgNTcuMTQzVjBaTTI1LjY3NSAwQzExLjQ5MiAwIDAgMTEuNTA5IDAgMjUuNzE0QzAgMzkuOTE5IDExLjQ5MiA1MS40MjkgMjUuNjc1IDUxLjQyOVYwWk01OS45MDggNTEuNDI5SDgyLjczVjI4LjU3MUg1OS45MDhWNTEuNDI5Wk01OS45MDggMjIuODU3SDgyLjczVjBINTkuOTA4VjIyLjg1N1pNMi44NTMgNTcuMTQzSDI1LjY3NVY4MEMxMy4wNjkgODAgMi44NTMgNjkuNzY4IDIuODUzIDU3LjE0M1oiLz4KPC9zdmc%2BCg%3D%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-gf180.yml) | [![SKY130 regression](https://img.shields.io/github/actions/workflow/status/retroSoC/retroSoC/regression-sky130.yml?branch=main&style=flat-square&label=SKY130&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCEtLSBTa3lXYXRlciBUZWNobm9sb2d5IGdyYXBoaWMgbWFyayBvbmx5ICh3b3JkbWFyayByZW1vdmVkKS4KICAgICBPZmZpY2lhbCBDb2xvci1MYW5kc2NhcGUtQmx1ZVNreSBmaWxsOiBsaW5lYXIgZ3JhZGllbnQgIzAwNjI4OCDihpIgI0IyRDIzNS4KICAgICBTb3VyY2UgcGF0aHMgZnJvbSBodHRwczovL3MyNy5xNGNkbi5jb20vNjU2NzAyNDgyL2ZpbGVzL2Rlc2lnbi9za3l3YXRlci1sb2dvLnN2ZwogICAgIEdyYWRpZW50IHN0b3BzLCBjb29yZGluYXRlcyBhbmQgcGF0aCBnZW9tZXRyeSBhcmUgb2ZmaWNpYWw7IG5vdCBhIHJlY29sb3Igb2YgdGhlIDIwMjYgYmxhY2sgaWNvbi4gLS0%2BCjxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB2aWV3Qm94PSItNS4yNDYgLTUuMjQ2IDE0MS42NDMgMTQwLjk5MiIgcm9sZT0iaW1nIiBhcmlhLWxhYmVsPSJTa3lXYXRlciBtYXJrIj4KICA8ZGVmcz4KICAgIDxsaW5lYXJHcmFkaWVudCBpZD0ic2t5R3JhZDEiIGdyYWRpZW50VW5pdHM9InVzZXJTcGFjZU9uVXNlIiB4MT0iODIuODExOSIgeTE9IjcyNi4wOCIgeDI9IjQ4LjMyMTkiIHkyPSI2NDIuMDUiIGdyYWRpZW50VHJhbnNmb3JtPSJtYXRyaXgoMSAwIDAgMSAtNSAtNjE4LjMxKSI%2BCiAgICAgIDxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzAwNjI4OCIvPgogICAgICA8c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiNCMkQyMzUiLz4KICAgIDwvbGluZWFyR3JhZGllbnQ%2BCiAgICA8bGluZWFyR3JhZGllbnQgaWQ9InNreUdyYWQyIiBncmFkaWVudFVuaXRzPSJ1c2VyU3BhY2VPblVzZSIgeDE9IjIwLjI1NTQiIHkxPSI1MzUuNjA4IiB4Mj0iNjEuMTg1NCIgeTI9IjY0Ni44NTgiIGdyYWRpZW50VHJhbnNmb3JtPSJtYXRyaXgoMSAwIDAgMSAtNSAtNjE4LjMxKSI%2BCiAgICAgIDxzdG9wIG9mZnNldD0iMCIgc3RvcC1jb2xvcj0iIzAwNjI4OCIvPgogICAgICA8c3RvcCBvZmZzZXQ9IjEiIHN0b3AtY29sb3I9IiNCMkQyMzUiLz4KICAgIDwvbGluZWFyR3JhZGllbnQ%2BCiAgPC9kZWZzPgogIDxwYXRoIGZpbGw9InVybCgjc2t5R3JhZDEpIiBkPSJNMTI0LDY5LjlINjEuN2MtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDQuNmMyLjYsMCw0LjgsMi4xLDQuOCw0LjggYzAsMi42LTIuMSw0LjgtNC44LDQuOEgzNS41Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDEuNmMzLjgtMC4xLDYuOC0zLjQsNi43LTcuMmMtMC4xLTMuNi0zLTYuNS02LjctNi43SDYuOSBjLTMuOC0wLjEtNywyLjgtNy4yLDYuN2MtMC4xLDMuOCwyLjgsNyw2LjcsNy4yYzAuMiwwLDAuNCwwLDAuNSwwaDExLjRjMi42LDAsNC44LDIuMSw0LjgsNC44YzAsMi42LTIuMSw0LjgtNC44LDQuOGgtMi43IGMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDQxLjhjMi42LDAsNC43LDIuMSw0LjgsNC44bDAsMGMwLDIuNi0yLjEsNC43LTQuOCw0LjhoLTljLTMuOCwwLTYuOSwzLjEtNi45LDYuOSBsMCwwYzAsMy44LDMuMSw2LjksNi45LDYuOWgzNC45YzMuOCwwLDYuOS0zLjEsNi45LTYuOWwwLDBjMC0zLjgtMy4xLTYuOS02LjktNi45aC05Yy0yLjYsMC00LjctMi4xLTQuOC00LjhsMCwwIGMwLTIuNiwyLjEtNC43LDQuOC00LjhIMTE0YzMuOCwwLjEsNy0yLjgsNy4yLTYuN2MwLjEtMy44LTIuOC03LTYuNy03LjJjLTAuMiwwLTAuNCwwLTAuNSwwaC05LjJjLTIuNiwwLTQuOC0yLjEtNC44LTQuOCBjMC0yLjYsMi4xLTQuOCw0LjgtNC44bDAsMGgxOS4yYzMuOCwwLDYuOS0zLjEsNi45LTYuOWMwLjEtMy43LTIuOC02LjgtNi42LTYuOUMxMjQuMiw2OS45LDEyNC4xLDY5LjksMTI0LDY5Ljl6IE05Mi41LDg4LjYgYzAsMi42LTIuMSw0LjctNC44LDQuOGgtNC41Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDQuNUM5MC40LDgzLjgsOTIuNSw4NS45LDkyLjUsODguNnoiLz4KICA8cGF0aCBmaWxsPSJ1cmwoI3NreUdyYWQyKSIgZD0iTTEyNCw0Ni43aC05LjVjLTIuNiwwLTQuOC0yLjEtNC44LTQuOGMwLTIuNiwyLjEtNC44LDQuOC00LjhoLTAuNGMzLjgsMC4xLDctMi44LDcuMi02LjdzLTIuOC03LTYuNy03LjIgYy0wLjIsMC0wLjQsMC0wLjUsMEg3NC42Yy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDljMy44LDAuMSw3LTIuOCw3LjItNi43cy0yLjgtNy02LjctNy4yYy0wLjIsMC0wLjQsMC0wLjUsMCBINDguNmMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDljMi42LDAsNC44LDIuMSw0LjgsNC44YzAsMi42LTIuMSw0LjgtNC44LDQuOGgtMC4xIGMtMy44LDAuMS02LjgsMy40LTYuNyw3LjJjMC4xLDMuNiwzLDYuNSw2LjcsNi43aDAuMWMyLjYsMCw0LjgsMi4xLDQuOCw0LjhjMCwyLjYtMi4xLDQuOC00LjgsNC44SDM1LjVjLTIuNiwwLTQuOC0yLjEtNC44LTQuOCBjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDEuNmMzLjgsMC4xLDctMi44LDcuMi02LjdjMC4xLTMuOC0yLjgtNy02LjctNy4yYy0wLjIsMC0wLjQsMC0wLjUsMEgxNy4yYy0zLjgtMC4xLTcsMi44LTcuMiw2LjcgczIuOCw3LDYuNyw3LjJjMC4yLDAsMC40LDAsMC41LDBoMS4xYzIuNiwwLDQuOCwyLjEsNC44LDQuOGMwLDIuNi0yLjEsNC44LTQuOCw0LjhINi45Yy0zLjgsMC02LjksMy4yLTYuOSw3bDAsMCBjMCwzLjgsMy4xLDYuOSw2LjksNi45aDY5LjVjMy44LDAsNi45LTMuMSw2LjktNi45bDAsMGMwLTMuOC0zLjEtNy02LjktN2gtMi4yYy0yLjYsMC00LjgtMi4xLTQuOC00LjhjMC0yLjYsMi4xLTQuOCw0LjgtNC44aDIyLjggYzIuNiwwLDQuOCwyLjEsNC44LDQuOGMwLDIuNi0yLjEsNC44LTQuOCw0LjhsMCwwbDAsMGMtMy44LDAtNi45LDMuMi02LjksN2wwLDBjMCwzLjgsMy4xLDYuOSw2LjksNi45aDI2LjZjMy44LDAsNi45LTMuMSw2LjktNi45IGwwLDBjMC4zLTMuNi0yLjQtNi43LTYtN0MxMjQuNSw0Ni43LDEyNC4yLDQ2LjcsMTI0LDQ2Ljd6Ii8%2BCjwvc3ZnPgo%3D)](https://github.com/retroSoC/retroSoC/actions/workflows/regression-sky130.yml) |
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
