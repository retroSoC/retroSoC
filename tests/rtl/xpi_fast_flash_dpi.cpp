#include <cstdint>

extern "C" void flash_read_byte(std::uint32_t address, std::uint8_t *data) {
    if (data != nullptr) {
        *data = static_cast<std::uint8_t>(address);
    }
}
