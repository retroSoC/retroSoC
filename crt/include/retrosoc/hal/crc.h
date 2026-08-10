#ifndef RETROSOC_CRC_H
#define RETROSOC_CRC_H

#include <crc.h>
#include <crc_regs.h>

#include <retrosoc/core/status.h>

typedef crc_config_t rs_crc_config_t;
typedef crc_profile_t rs_crc_profile_t;
typedef crc_snapshot_t rs_crc_snapshot_t;

#define RS_CRC_PROFILE_CRC7_MMC          CRC_PROFILE_CRC7_MMC
#define RS_CRC_PROFILE_CRC8_SMBUS        CRC_PROFILE_CRC8_SMBUS
#define RS_CRC_PROFILE_CRC16_CCITT_FALSE CRC_PROFILE_CRC16_CCITT_FALSE
#define RS_CRC_PROFILE_CRC16_ARC         CRC_PROFILE_CRC16_ARC
#define RS_CRC_PROFILE_CRC32_ISO_HDLC    CRC_PROFILE_CRC32_ISO_HDLC

#define RS_CRC_ERROR_ACCESS              CRC_ERROR_ACCESS_MASK
#define RS_CRC_ERROR_STATE               CRC_ERROR_STATE_MASK
#define RS_CRC_ERROR_CONFIG              CRC_ERROR_CONFIG_MASK
#define RS_CRC_ERROR_COUNT_OVERFLOW      CRC_ERROR_COUNT_OVERFLOW_MASK
#define RS_CRC_ERROR_ALL                 CRC_ERROR_ALL_MASK

rs_status_t rs_crc_get_profile(rs_crc_profile_t profile, rs_crc_config_t *config);
rs_status_t rs_crc_init(const rs_crc_config_t *config);
rs_status_t rs_crc_start(void);
rs_status_t rs_crc_update(const void *data, size_t length);
rs_status_t rs_crc_finish(uint32_t *result);
rs_status_t rs_crc_abort(void);
rs_status_t rs_crc_compute(const rs_crc_config_t *config, const void *data, size_t length,
                           uint32_t *result);
rs_status_t rs_crc_get_status(rs_crc_snapshot_t *snapshot);
rs_status_t rs_crc_clear_errors(uint32_t mask);
void rs_crc_shell_test(int argc, char **argv);

#endif
