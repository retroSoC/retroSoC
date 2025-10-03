#ifndef WAV_DECODER_H__
#define WAV_DECODER_H__

typedef struct {
    char     ChunkID[4];
    uint32_t ChunkSize;
} ChunkHeader_t;

typedef struct {
    char ChunkID[4]; // big endian
    uint32_t ChunkSize;
    char Format[4]; // big endian
} RIFFChunk_t;

typedef struct {
    char Subchunk1ID[4]; // big endian
    uint32_t Subchunk1Size;
    uint16_t AudioFormat;
    uint16_t NumChannels;
    uint32_t SampleRate;
    uint32_t ByteRate;
    uint16_t BlockAlign;
    uint16_t BitsPerSample;
} FMTChunk_t;

typedef struct {
    char     ChunkID[4];
    uint32_t ChunkSize;
    char     ChunkData[60]; // HACK: use flexible array + malloc
} LISTChunkItem_t;

typedef struct {
    char Subchunk2ID[4]; // big endian
    uint32_t Subchunk2Size;
} DATAChunk_t;

typedef struct {
    RIFFChunk_t riff;
    FMTChunk_t fmt;
    DATAChunk_t data;
    LISTChunkItem_t list[20];
    int info_num;
} WAVHeader_t;


typedef struct {
    WAVHeader_t header;
} WAVFile_t;

WAVFile_t* wav_file_decoder(uint32_t start_addr);

#endif