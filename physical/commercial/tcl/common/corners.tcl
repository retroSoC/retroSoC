# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

namespace eval flow {
    variable extraction_corners {
        Cworst_m40  {Cworst -40 NXTGRD_CWORST}
        Cworst_125  {Cworst 125 NXTGRD_CWORST}
        RCworst_m40 {RCworst -40 NXTGRD_RCWORST}
        RCworst_125 {RCworst 125 NXTGRD_RCWORST}
        Cbest_m40   {Cbest -40 NXTGRD_CBEST}
        Cbest_125   {Cbest 125 NXTGRD_CBEST}
        RCbest_m40  {RCbest -40 NXTGRD_RCBEST}
        RCbest_125  {RCbest 125 NXTGRD_RCBEST}
        TYP_25      {TYP 25 NXTGRD_TYP}
    }

    variable scenarios {
        func_MAX_Cworst_125   {MAX Cworst_125 setup}
        func_MAX_RCworst_125  {MAX RCworst_125 setup}
        func_WCL_Cworst_m40   {WCL Cworst_m40 setup}
        func_WCL_RCworst_m40  {WCL RCworst_m40 setup}
        func_TYP_TYP_25       {TYP TYP_25 both}
        func_MIN_Cworst_m40   {MIN Cworst_m40 hold}
        func_MIN_RCworst_m40  {MIN RCworst_m40 hold}
        func_MIN_Cbest_m40    {MIN Cbest_m40 hold}
        func_MIN_RCbest_m40   {MIN RCbest_m40 hold}
        func_ML_Cworst_125    {ML Cworst_125 hold}
        func_ML_RCworst_125   {ML RCworst_125 hold}
        func_ML_Cbest_125     {ML Cbest_125 hold}
        func_ML_RCbest_125    {ML RCbest_125 hold}
    }
}

proc flow::rc_cap_table {corner} {
    switch -glob -- $corner {
        Cworst_*  { return [lindex [flow::env_list CAP_TABLE_CWORST] 0] }
        RCworst_* { return [lindex [flow::env_list CAP_TABLE_RCWORST] 0] }
        Cbest_*   { return [lindex [flow::env_list CAP_TABLE_CBEST] 0] }
        RCbest_*  { return [lindex [flow::env_list CAP_TABLE_RCBEST] 0] }
        TYP_*     { return [lindex [flow::env_list CAP_TABLE_TYP] 0] }
        default   { flow::fail "unknown RC corner: $corner" }
    }
}

proc flow::spef_name {top corner} {
    return "${top}.${corner}.spef.gz"
}
