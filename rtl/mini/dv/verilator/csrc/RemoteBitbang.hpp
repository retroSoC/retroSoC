// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

#pragma once

#include <cstdint>

class Vretrosoc_top;

// Implements the byte-oriented remote-bitbang protocol used by OpenOCD.
class RemoteBitbang {
  public:
    explicit RemoteBitbang(std::uint16_t port);
    ~RemoteBitbang();

    bool start();
    bool service(Vretrosoc_top &dut);

  private:
    void closeClient();
    std::uint16_t port_;
    int listener_ = -1;
    int client_ = -1;
};
