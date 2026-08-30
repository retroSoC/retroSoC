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
extern "C" void flash_set_fast_mode(bool enable);

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
    args.fastFlash = res["fast-flash"].as<bool>();

    args.image = res["image"].as<std::string>();

    startTime = chrono::system_clock::now();
    if (args.image == "") {
        std::cout << rang::fg::red << "Image file unspecified. Use -i to provide the image of flash"
                  << rang::fg::reset << std::endl;
        exit(1);
    }

    std::cout << rang::fg::green << "Initializing flash with " << args.image << " ..."
              << rang::fg::reset << std::endl;
    flash_set_fast_mode(args.fastFlash);
    std::cout << "VERILATOR_FAST_FLASH=" << (args.fastFlash ? "enabled" : "disabled") << std::endl;
    flash_init(args.image.c_str());

    dutPtr = new Vretrosoc_top;
    reset();

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

void Emulator::advanceClocks() {
    dutPtr->ext_clk_i = !dutPtr->ext_clk_i;
    ++ref24Divider;
    if (ref24Divider == 3U) {
        dutPtr->ref24_clk_i = !dutPtr->ref24_clk_i;
        ref24Divider = 0U;
    }
}

void Emulator::reset() {
    std::cout << rang::fg::yellow << "Initializing and resetting DUT ..." << rang::fg::reset
              << std::endl;
    dutPtr->rst_n_i = 1;
    dutPtr->ext_clk_i = 0;
    dutPtr->ref24_clk_i = 0;
    ref24Divider = 0U;
    dutPtr->jtag_tck_i = 0;
    dutPtr->jtag_tms_i = 0;
    dutPtr->jtag_tdi_i = 0;
    dutPtr->jtag_trst_n_i = 0;
    dutPtr->eval();
    // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
    // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;

    for (int i = 0; i < 10; i++) {
        advanceClocks();
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    dutPtr->rst_n_i = 0;
    for (int i = 0; i < 10; i++) {
        advanceClocks();
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    dutPtr->rst_n_i = 1;
    dutPtr->jtag_trst_n_i = 1;
    for (int i = 0; i < 5; i++) {
        advanceClocks();
        dutPtr->eval();
        // std::cout << "rst_n_i: " << static_cast<unsigned>(dutPtr->rst_n_i) << " ext_clk_i: " <<
        // static_cast<unsigned>(dutPtr->ext_clk_i) << std::endl;
    }

    std::cout << rang::fg::yellow << "Initializing and resetting DUT done" << rang::fg::reset
              << std::endl;
}

void Emulator::step() {
    advanceClocks();
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

int Emulator::runSim() {
    std::cout << rang::fg::yellow << "Running DUT simulation..." << rang::fg::reset << std::endl;
    while (!Verilated::gotFinish() && signal_received == 0 && !getArriveTime()) {
        // TCP polling need not occur on every simulation half-cycle. A JTAG
        // command is still evaluated one-by-one by RemoteBitbang::service().
        if (remoteBitbang && (cycle & 0x3fU) == 0U && !remoteBitbang->service(*dutPtr)) {
            break;
        }
        step();
        if (dutPtr->test_done_o != 0U) {
            const auto code = static_cast<unsigned>(dutPtr->test_code_o);
            if (dutPtr->test_pass_o != 0U) {
                std::cout << "\nSIM_TEST_PASS code=" << code << std::endl;
                dutPtr->final();
                return 0;
            }
            std::cerr << "\nSIM_TEST_FAIL code=" << code << std::endl;
            dutPtr->final();
            return 1;
        }
    }
    if (getArriveTime()) {
        std::cerr << "SIM_TEST_TIMEOUT" << std::endl;
        std::cerr << "CLOCK_RESET_DIAG aon=" << static_cast<unsigned>(dutPtr->diag_aon_rst_n_o)
                  << " lp=" << static_cast<unsigned>(dutPtr->diag_lp_rst_n_o)
                  << " pclk=" << static_cast<unsigned>(dutPtr->diag_pclk_rst_n_o)
                  << " hp=" << static_cast<unsigned>(dutPtr->diag_hp_rst_n_o) << std::endl;
        std::cerr << "MGMT_READ_DIAG addr=0x" << std::hex
                  << static_cast<unsigned>(dutPtr->diag_mgmt_araddr_o) << std::dec
                  << " valid=" << static_cast<unsigned>(dutPtr->diag_mgmt_arvalid_o)
                  << " ready=" << static_cast<unsigned>(dutPtr->diag_mgmt_arready_o) << std::endl;
        std::cerr << "XPI_READ_DIAG arvalid="
                  << static_cast<unsigned>(dutPtr->diag_xpi_arvalid_o)
                  << " arready=" << static_cast<unsigned>(dutPtr->diag_xpi_arready_o)
                  << " rvalid=" << static_cast<unsigned>(dutPtr->diag_xpi_rvalid_o)
                  << " rready=" << static_cast<unsigned>(dutPtr->diag_xpi_rready_o) << std::endl;
    }
    dutPtr->final();
    return 0;
}
