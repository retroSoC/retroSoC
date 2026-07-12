/* FatFs block-device adapter for the retroSoC SPISD memory window. */

#include <stdbool.h>

#include "ff.h"
#include "diskio.h"

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/spisd.h>

#define RS_FATFS_DRIVE_TF 0U

static bool rs_fatfs_initialized;

static DRESULT rs_fatfs_result(rs_status_t status) {
    return (status == RS_OK) ? RES_OK : RES_ERROR;
}

DSTATUS disk_status(BYTE pdrv) {
    if (pdrv != RS_FATFS_DRIVE_TF) {
        return STA_NOINIT;
    }
    return rs_fatfs_initialized ? 0U : STA_NOINIT;
}

DSTATUS disk_initialize(BYTE pdrv) {
    if (pdrv != RS_FATFS_DRIVE_TF) {
        return STA_NOINIT;
    }
    rs_fatfs_initialized = true;
    return 0U;
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count) {
    if ((pdrv != RS_FATFS_DRIVE_TF) || (buff == NULL) || (count == 0U) ||
        (disk_status(pdrv) != 0U) || (sector > UINT32_MAX)) {
        return RES_PARERR;
    }
    return rs_fatfs_result(rs_spisd_sector_read(buff, (uint32_t)sector, (uint32_t)count));
}

#if FF_FS_READONLY == 0
DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count) {
    if ((pdrv != RS_FATFS_DRIVE_TF) || (buff == NULL) || (count == 0U) ||
        (disk_status(pdrv) != 0U) || (sector > UINT32_MAX)) {
        return RES_PARERR;
    }
    return rs_fatfs_result(rs_spisd_sector_write(buff, (uint32_t)sector, (uint32_t)count));
}
#endif

DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void *buff) {
    if ((pdrv != RS_FATFS_DRIVE_TF) || (disk_status(pdrv) != 0U)) {
        return RES_NOTRDY;
    }

    switch (cmd) {
    case CTRL_SYNC:
        return rs_fatfs_result(rs_spisd_sector_sync(RS_TIMEOUT_DEFAULT));
    case GET_SECTOR_SIZE:
        if (buff == NULL) {
            return RES_PARERR;
        }
        *(WORD *)buff = RS_SPISD_SECTOR_SIZE;
        return RES_OK;
    case GET_SECTOR_COUNT:
        if (buff == NULL) {
            return RES_PARERR;
        }
        *(LBA_t *)buff = (LBA_t)(TF_CARD_OFFST / RS_SPISD_SECTOR_SIZE);
        return RES_OK;
    case GET_BLOCK_SIZE:
        if (buff == NULL) {
            return RES_PARERR;
        }
        *(DWORD *)buff = 1U;
        return RES_OK;
    default:
        return RES_PARERR;
    }
}
