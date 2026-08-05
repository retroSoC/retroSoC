#pragma once

#include <chrono>
#include <iostream>
#include <memory>
#include <string>
namespace chrono = std::chrono;

#include <verilated.h>
#include <Vretrosoc_top.h>
#ifdef DUMP_WAVE_FST
#include <verilated_fst_c.h>
#endif
#include "cxxopts.hpp"

#ifdef HAVE_DEBUG
#include "RemoteBitbang.hpp"
#endif

class Emulator {
  public:
    Emulator(cxxopts::ParseResult &res);
    ~Emulator();
    void wave();
    void reset();
    void step();
    void state();
    std::string getAppName(std::string str);
    bool getArriveTime();
    void runSim();

  private:
    unsigned long long cycle = 0;
    chrono::system_clock::time_point startTime;
    Vretrosoc_top *dutPtr = nullptr;
    struct Args {
        bool dumpWave = false;
        unsigned long dumpBegin = 0UL;
        unsigned long dumpEnd = -1UL;
        unsigned long simTime = -1UL;
        unsigned long jtagPort = 0UL;
        std::string simMode = "";
        std::string image = "";
    } args;

#ifdef HAVE_DEBUG
    std::unique_ptr<RemoteBitbang> remoteBitbang;
#endif

#ifdef DUMP_WAVE_FST
    VerilatedFstC *wavePtr = nullptr;
#endif
};
