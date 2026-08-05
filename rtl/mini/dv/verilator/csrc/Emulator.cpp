#include <csignal>
#include "rang.hpp"
#include "Emulator.h"

static int signal_received = 0;

void sig_handler(int signo) {
    if (signal_received != 0) {
        std::cout << "SIGINT received, forcely shutting down." << std::endl;
        exit(1);
    }
    std::cout << "\nSIGINT received, gracefully shutting down... Type Ctrl+C again to stop forcely."
              << std::endl;
    signal_received = signo;
}

void env_init() {
    std::cout << rang::fg::magenta << "Emulator compiled at " << __DATE__ << ", " << __TIME__
              << rang::fg::reset << std::endl;
    if (signal(SIGINT, sig_handler) == SIG_ERR) {
        std::cout << "can't catch SIGINT" << std::endl;
    }
}

extern "C" void flash_init(const char *img);

Emulator::Emulator(cxxopts::ParseResult &res) {
    args.dumpWave = res["dump-wave"].as<bool>();
    args.dumpBegin = res["log-begin"].as<unsigned long>();
    auto tmp = res["log-end"].as<unsigned long>();
    if (tmp > 0)
        args.dumpEnd = tmp;

    tmp = res["sim-time"].as<unsigned long>();
    if (tmp > 0)
        args.simTime = tmp;

    args.jtagPort = res["jtag-port"].as<unsigned long>();

    args.image = res["image"].as<std::string>();

    startTime = chrono::system_clock::now();
    if (args.image == "") {
        std::cout << rang::fg::red << "Image file unspecified. Use -i to provide the image of flash"
                  << rang::fg::reset << std::endl;
        exit(1);
    }

    std::cout << rang::fg::green << "Initializing flash with " << args.image << " ..."
              << rang::fg::reset << std::endl;
    flash_init(args.image.c_str());

    dutPtr = new Vretrosoc_top;
    reset();

#ifdef HAVE_DEBUG
    if (args.jtagPort > 0) {
        if (args.jtagPort > 65535UL) {
            std::cerr << "remote-bitbang port is outside the TCP range" << std::endl;
            exit(1);
        }
        remoteBitbang = std::make_unique<RemoteBitbang>(static_cast<std::uint16_t>(args.jtagPort));
        if (!remoteBitbang->start()) {
            exit(1);
        }
    }
#endif

    if (args.dumpWave) {
#ifdef DUMP_WAVE_FST
        wavePtr = new VerilatedFstC;
#endif
        Verilated::traceEverOn(true);
        std::cout << rang::fg::yellow
                  << "`dump-wave` enabled, waves will be written to \"soc.wave\"."
                  << rang::fg::reset << std::endl;
        dutPtr->trace(wavePtr, 1);
        wavePtr->open("soc.wave");
        wavePtr->dump(0);
    }
}

Emulator::~Emulator() {
    if (wavePtr) {
        wavePtr->close();
        delete wavePtr;
    }
}

void Emulator::wave() {
    ++cycle;
    if (args.dumpWave && args.dumpBegin <= cycle && cycle <= args.dumpEnd) {
        wavePtr->dump((vluint64_t)cycle);
    }
}

void Emulator::reset() {
    std::cout << rang::fg::yellow << "Initializing and resetting DUT ..." << rang::fg::reset
              << std::endl;
    dutPtr->rst_n_i = 1;
    dutPtr->ext_clk_i = 0;
#ifdef HAVE_DEBUG
    dutPtr->jtag_tck_i = 0;
    dutPtr->jtag_tms_i = 0;
    dutPtr->jtag_tdi_i = 0;
    dutPtr->jtag_trst_n_i = 0;
#endif
    dutPtr->eval();
    // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
    // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;

    for (int i = 0; i < 10; i++) {
        dutPtr->ext_clk_i = !dutPtr->ext_clk_i;
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    dutPtr->rst_n_i = 0;
    for (int i = 0; i < 10; i++) {
        dutPtr->ext_clk_i = !dutPtr->ext_clk_i;
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    dutPtr->rst_n_i = 1;
#ifdef HAVE_DEBUG
    dutPtr->jtag_trst_n_i = 1;
#endif
    for (int i = 0; i < 5; i++) {
        dutPtr->ext_clk_i = !dutPtr->ext_clk_i;
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    std::cout << rang::fg::yellow << "Initializing and resetting DUT done" << rang::fg::reset
              << std::endl;
}

void Emulator::step() {
    dutPtr->ext_clk_i = !dutPtr->ext_clk_i;
    dutPtr->eval();
    // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
    // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    ++cycle;
    if (args.dumpWave && args.dumpBegin <= cycle && cycle <= args.dumpEnd) {
        wavePtr->dump((vluint64_t)cycle);
    }
}

void Emulator::state() {
    auto elapsed = chrono::duration_cast<chrono::seconds>(chrono::system_clock::now() - startTime);
    std::cout << rang::fg::yellow << "Simulation " << cycle << " cycles in " << elapsed.count()
              << "s" << rang::fg::reset << std::endl;
}

bool Emulator::getArriveTime() {
    auto elapsed = chrono::duration_cast<chrono::seconds>(chrono::system_clock::now() - startTime);
    if (elapsed.count() > args.simTime)
        return true;
    else
        return false;
}

void Emulator::runSim() {
    std::cout << rang::fg::yellow << "Running DUT simulation..." << rang::fg::reset << std::endl;
    while (!Verilated::gotFinish() && signal_received == 0 && !getArriveTime()) {
#ifdef HAVE_DEBUG
        // TCP polling need not occur on every simulation half-cycle. A JTAG
        // command is still evaluated one-by-one by RemoteBitbang::service().
        if (remoteBitbang && (cycle & 0x3fU) == 0U && !remoteBitbang->service(*dutPtr)) {
            break;
        }
#endif
        step();
    }
    dutPtr->final();
}
