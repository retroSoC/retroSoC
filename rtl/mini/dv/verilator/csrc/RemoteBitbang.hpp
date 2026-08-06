// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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
