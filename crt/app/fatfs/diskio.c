/*-----------------------------------------------------------------------*/
/* Low level disk I/O module SKELETON for FatFs     (C)ChaN, 2025        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "ff.h"     /* Basic definitions of FatFs */
#include "diskio.h" /* Declarations FatFs MAI */


#define DEV_TF   0 /* Map MMC/SD card to physical drive 1 */

/*-----------------------------------------------------------------------*/
/* Get Drive Status                                                      */
/*-----------------------------------------------------------------------*/
DSTATUS disk_status (
    BYTE pdrv  /* Physical drive nmuber to identify the drive */
)
{
    DSTATUS status = STA_NOINIT;
    switch (pdrv) {
    case DEV_TF:
        status &= ~STA_NOINIT;
        break;
    default:
        status = STA_NOINIT;
    }
    return status;
}


/*-----------------------------------------------------------------------*/
/* Inidialize a Drive                                                    */
/*-----------------------------------------------------------------------*/
DSTATUS disk_initialize (
    BYTE pdrv    /* Physical drive nmuber to identify the drive */
)
{
    DSTATUS status = STA_NOINIT;
    switch (pdrv) {
    case DEV_TF:
        status &= ~STA_NOINIT;
        break;
    default:
        status = STA_NOINIT;
    }
    return status;
}

/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/
DRESULT disk_read (
 BYTE pdrv,  /* Physical drive nmuber to identify the drive */
 BYTE *buff,  /* Data buffer to store read data */
 LBA_t sector, /* Start sector in LBA */
 UINT count  /* Number of sectors to read */
)
{
    DRESULT status = RES_PARERR;

    if (!count) return RES_PARERR;    /* Check parameter */
    switch (pdrv) {
    case DEV_TF:
        spisd_drv_read(buff, sector, count);
        status = RES_OK;
        break;
    default:
        status = RES_PARERR;
    }
    return status;

 return status;
}



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/
#if FF_FS_READONLY == 0



DRESULT disk_write (
 BYTE pdrv,   /* Physical drive nmuber to identify the drive */
 const BYTE *buff, /* Data to be written */
 LBA_t sector,  /* Start sector in LBA */
 UINT count   /* Number of sectors to write */
)
{
    DRESULT status = RES_PARERR;

    if (!count) return RES_PARERR;    /* Check parameter */
    switch (pdrv) {
    case DEV_TF:
        spisd_drv_write(buff, sector, count);
        status = RES_OK;
        break;
    default:
        status = RES_PARERR;
    }
    return status;

 return status;
}

#endif


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/

DRESULT disk_ioctl (
 BYTE pdrv,  /* Physical drive nmuber (0..) */
 BYTE cmd,  /* Control code */
 void *buff  /* Buffer to send/receive control data */
)
{
    DRESULT status = RES_PARERR;

    switch (pdrv) {
    case DEV_TF:
        switch(cmd) {
        case GET_SECTOR_SIZE:
            *(WORD * )buff = 512;
            break;
        case GET_SECTOR_COUNT:
            *(WORD * )buff = 524288; // 256MiB(mem access)
            break;
        case GET_BLOCK_SIZE:
            *(WORD * )buff = 1;
            break;
        case CTRL_SYNC:
            break;
        }
        status = RES_OK;
        break;
    default:
        status = RES_PARERR;
    }
    return status;

 return status;
}

