#include <stdbool.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinyspisd.h>
#include <wav_decoder.h>

static void printfln(char *buff, uint32_t len) {
    for(uint32_t i = 0; i < len; ++i) printf("%c", buff[i]);
    printf("\n");
}


static void parseLISTChunk(WAVHeader_t *header, uint32_t addr) {
    const char *info_tag[] = {"IART", "ICOP", "ICRD", "IGNR", "INAM", "IPRD", "ISFT", "ISRC", "ICMT", "ISBJ", "ITCH"};
    char info_tag_len = sizeof(info_tag) / sizeof(info_tag[0]);
    ChunkHeader_t chunkHeader;
    uint32_t info_num = 0;
    

    // "LIST"
    spisd_mem_read((uint8_t *)&chunkHeader, 1, sizeof(ChunkHeader_t), addr);
    printf("ChunkID: %.4s\n", chunkHeader.ChunkID);
    uint32_t list_end = addr + chunkHeader.ChunkSize;
    addr += sizeof(ChunkHeader_t);

    spisd_mem_read((uint8_t *)&chunkHeader, 1, sizeof(ChunkHeader_t) - 4, addr);
    if (memcmp(chunkHeader.ChunkID, "INFO", 4) == 0) {
        addr += 4;
        while (addr < list_end) {
            spisd_mem_read((uint8_t *)&chunkHeader, 1, sizeof(ChunkHeader_t), addr);
            bool is_find = false;
            for(int i = 0; i < info_tag_len; ++i) {
                if (memcmp(chunkHeader.ChunkID, info_tag[i], 4) == 0) {
                    // printf("tag %.4s\n", chunkHeader.ChunkID);
                    printf("ChunkID: %.4s\n", chunkHeader.ChunkID);
                    printf("addr: %x\n", addr);
                    is_find = true;
                    spisd_mem_read((uint8_t *)&header->list[info_num++], 1, chunkHeader.ChunkSize + 8, addr);
                    addr += chunkHeader.ChunkSize + 8;
                }
            }
            
            if(!is_find) addr += 1; // for align the exten data
        }
    }
    header->info_num = info_num;
}



WAVFile_t* wav_file_decoder(uint32_t start_addr) {
    WAVHeader_t header;
    ChunkHeader_t chunkHeader;

    spisd_mem_read((uint8_t *)&header.riff, 1, sizeof(RIFFChunk_t), start_addr);
    start_addr += sizeof(RIFFChunk_t);

    if (memcmp(header.riff.ChunkID, "RIFF", 4) != 0 || memcmp(header.riff.Format, "WAVE", 4) != 0) {
        return NULL;
    }

    while(1) {
        spisd_mem_read((uint8_t *)&chunkHeader, 1, sizeof(ChunkHeader_t), start_addr);
        // printf("start addr: %x\n", start_addr);
        if (memcmp(chunkHeader.ChunkID, "fmt ", 4) == 0) {
            spisd_mem_read((uint8_t *)&header.fmt, 1, sizeof(FMTChunk_t), start_addr);
            start_addr += sizeof(FMTChunk_t);
        } else if(memcmp(chunkHeader.ChunkID, "LIST", 4) == 0) {
            parseLISTChunk(&header, start_addr);
            start_addr += chunkHeader.ChunkSize + sizeof(ChunkHeader_t);
            printf("start addr: %x\n", start_addr);
        } else if(memcmp(chunkHeader.ChunkID, "data", 4) == 0) {
            spisd_mem_read((uint8_t *)&header.data, 1, sizeof(DATAChunk_t), start_addr);
            start_addr += sizeof(DATAChunk_t);
            break;
        }
    }
    

    // RIFF
    printf("File size:     %d bytes(~%dMiB)\n", header.riff.ChunkSize + 8, (header.riff.ChunkSize + 8) / 1024 / 1024);
    printf("Format:        %.4s\n", header.riff.Format);
    // FMT
    printf("AudioFormat:   %d(PCM)\n", header.fmt.AudioFormat); // TODO: need to assign by looking up table
    printf("NumChannels:   %d channels\n", header.fmt.NumChannels);
    printf("SampleRate:    %d kHz\n", header.fmt.SampleRate);
    printf("ByteRate:      %d bps\n", header.fmt.ByteRate);
    printf("BlockAlign:    %d\n", header.fmt.BlockAlign);
    printf("BitsPerSample: %d bits\n", header.fmt.BitsPerSample);
    // LIST(optional)
    for(int i = 0; i < header.info_num; ++i) {
        printf("%.4s:          ", header.list[i].ChunkID);
        printfln(header.list[i].ChunkData, header.list[i].ChunkSize);
    }
    // data
    printf("Data size:     %d bytes(~%dMiB)\n", header.data.Subchunk2Size, (header.data.Subchunk2Size) / 1024 / 1024);

    // audio_data = (WAVFile_t*)malloc(sizeof(struct WAVData));
    // if (audio_data == NULL) {
    //     return NULL;
    // }
    // audio_data->header = header;
    // // audio_data->sample = (uint8_t*)malloc(header.Subchunk2Size);
    // // if (audio_data->sample == NULL) {
    // //     return NULL;
    // // }
    // // fread(audio_data->sample, header.Subchunk2Size, 1, inputFile);
    // // fclose(inputFile);

    // return audio_data;
    return NULL;
}