// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

#include "RemoteBitbang.hpp"

#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

#include "Vretrosoc_top.h"

namespace {

bool setNonBlocking(int descriptor) {
    const int flags = fcntl(descriptor, F_GETFL, 0);
    return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0;
}

} // namespace

RemoteBitbang::RemoteBitbang(std::uint16_t port) : port_(port) {
}

RemoteBitbang::~RemoteBitbang() {
    closeClient();
    if (listener_ >= 0) {
        close(listener_);
    }
}

bool RemoteBitbang::start() {
    listener_ = socket(AF_INET, SOCK_STREAM, 0);
    if (listener_ < 0) {
        std::perror("remote-bitbang socket");
        return false;
    }

    const int enabled = 1;
    if (setsockopt(listener_, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled)) != 0) {
        std::perror("remote-bitbang setsockopt");
        return false;
    }

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port_);
    if (bind(listener_, reinterpret_cast<const sockaddr *>(&address), sizeof(address)) != 0) {
        std::perror("remote-bitbang bind");
        return false;
    }
    if (listen(listener_, 1) != 0 || !setNonBlocking(listener_)) {
        std::perror("remote-bitbang listen");
        return false;
    }

    std::cout << "[verilator] remote-bitbang listening on 127.0.0.1:" << port_ << std::endl;
    return true;
}

void RemoteBitbang::closeClient() {
    if (client_ >= 0) {
        close(client_);
        client_ = -1;
    }
}

bool RemoteBitbang::service(Vretrosoc_top &dut) {
    if (client_ < 0) {
        client_ = accept(listener_, nullptr, nullptr);
        if (client_ >= 0) {
            const int enabled = 1;
            if (setsockopt(client_, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled)) != 0) {
                std::perror("remote-bitbang TCP_NODELAY");
                closeClient();
                return true;
            }
            if (!setNonBlocking(client_)) {
                std::perror("remote-bitbang client");
                closeClient();
                return true;
            }
            std::cout << "[verilator] remote-bitbang client connected" << std::endl;
        } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
            std::perror("remote-bitbang accept");
            return false;
        }
    }

    if (client_ < 0) {
        return true;
    }

    char commands[256];
    const ssize_t received = recv(client_, commands, sizeof(commands), 0);
    if (received == 0) {
        closeClient();
        return true;
    }
    if (received < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return true;
        }
        std::perror("remote-bitbang recv");
        return false;
    }

    for (ssize_t index = 0; index < received; ++index) {
        const char command = commands[index];
        if (command >= '0' && command <= '7') {
            const unsigned value = static_cast<unsigned>(command - '0');
            dut.jtag_tck_i = (value >> 2U) & 1U;
            dut.jtag_tms_i = (value >> 1U) & 1U;
            dut.jtag_tdi_i = value & 1U;
            dut.eval();
        } else if (command == 'R') {
            const char tdo = dut.jtag_tdo_o == 0U ? '0' : '1';
            (void)send(client_, &tdo, 1, MSG_NOSIGNAL);
        } else if (command == 'Q') {
            return false;
        }
    }

    return true;
}
