#include "include/HushPortSharedAudio.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define HUSHPORT_SHARED_AUDIO_PATH "/tmp/hushport-audio.frames"
#define HUSHPORT_SHARED_AUDIO_MAGIC 0x48535054u
#define HUSHPORT_SHARED_AUDIO_VERSION 1u
#define HUSHPORT_SHARED_AUDIO_CAPACITY_FRAMES 48000u
#define HUSHPORT_SHARED_AUDIO_CHANNELS 2u

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t capacityFrames;
    uint32_t channelCount;
    _Atomic uint64_t writeFrame;
    float samples[HUSHPORT_SHARED_AUDIO_CAPACITY_FRAMES * HUSHPORT_SHARED_AUDIO_CHANNELS];
} HushPortSharedAudioStorage;

struct HushPortSharedAudio {
    HushPortSharedAudioStorage* storage;
    size_t mappedSize;
    uint64_t readFrame;
    bool writer;
};

static HushPortSharedAudio* HushPortSharedAudioOpen(bool writer)
{
    const int flags = writer ? (O_RDWR | O_CREAT) : O_RDONLY;
    const int descriptor = open(HUSHPORT_SHARED_AUDIO_PATH, flags, 0666);
    if (descriptor < 0) {
        return NULL;
    }

    const size_t size = sizeof(HushPortSharedAudioStorage);
    if (writer && ftruncate(descriptor, (off_t)size) != 0) {
        close(descriptor);
        return NULL;
    }

    const int protections = writer ? (PROT_READ | PROT_WRITE) : PROT_READ;
    void* mapping = mmap(NULL, size, protections, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (mapping == MAP_FAILED) {
        return NULL;
    }

    HushPortSharedAudio* result = calloc(1, sizeof(*result));
    if (result == NULL) {
        munmap(mapping, size);
        return NULL;
    }
    result->storage = mapping;
    result->mappedSize = size;
    result->writer = writer;

    if (writer && (result->storage->magic != HUSHPORT_SHARED_AUDIO_MAGIC ||
                   result->storage->version != HUSHPORT_SHARED_AUDIO_VERSION)) {
        memset(result->storage, 0, size);
        result->storage->capacityFrames = HUSHPORT_SHARED_AUDIO_CAPACITY_FRAMES;
        result->storage->channelCount = HUSHPORT_SHARED_AUDIO_CHANNELS;
        result->storage->version = HUSHPORT_SHARED_AUDIO_VERSION;
        result->storage->magic = HUSHPORT_SHARED_AUDIO_MAGIC;
    }

    if (writer) {
        atomic_store_explicit(&result->storage->writeFrame, 0, memory_order_release);
    }

    if (result->storage->magic != HUSHPORT_SHARED_AUDIO_MAGIC ||
        result->storage->version != HUSHPORT_SHARED_AUDIO_VERSION) {
        HushPortSharedAudioClose(result);
        return NULL;
    }
    result->readFrame = atomic_load_explicit(&result->storage->writeFrame, memory_order_acquire);
    return result;
}

HushPortSharedAudio* HushPortSharedAudioOpenWriter(void)
{
    return HushPortSharedAudioOpen(true);
}

HushPortSharedAudio* HushPortSharedAudioOpenReader(void)
{
    return HushPortSharedAudioOpen(false);
}

void HushPortSharedAudioClose(HushPortSharedAudio* sharedAudio)
{
    if (sharedAudio == NULL) {
        return;
    }
    munmap(sharedAudio->storage, sharedAudio->mappedSize);
    free(sharedAudio);
}

void HushPortSharedAudioWriteFloat32(
    HushPortSharedAudio* sharedAudio,
    const float* samples,
    uint32_t frameCount
) {
    if (sharedAudio == NULL || samples == NULL || frameCount == 0) {
        return;
    }

    HushPortSharedAudioStorage* storage = sharedAudio->storage;
    const uint64_t writeFrame = atomic_load_explicit(&storage->writeFrame, memory_order_relaxed);
    if (frameCount > storage->capacityFrames) {
        const uint32_t skipped = frameCount - storage->capacityFrames;
        samples += (size_t)skipped * HUSHPORT_SHARED_AUDIO_CHANNELS;
        frameCount = storage->capacityFrames;
    }

    const uint32_t start = (uint32_t)(writeFrame % storage->capacityFrames);
    const uint32_t firstFrames = frameCount < (storage->capacityFrames - start)
        ? frameCount : (storage->capacityFrames - start);
    memcpy(&storage->samples[(size_t)start * HUSHPORT_SHARED_AUDIO_CHANNELS], samples,
           (size_t)firstFrames * HUSHPORT_SHARED_AUDIO_CHANNELS * sizeof(float));
    if (firstFrames < frameCount) {
        memcpy(storage->samples,
               samples + ((size_t)firstFrames * HUSHPORT_SHARED_AUDIO_CHANNELS),
               (size_t)(frameCount - firstFrames) * HUSHPORT_SHARED_AUDIO_CHANNELS * sizeof(float));
    }
    atomic_store_explicit(&storage->writeFrame, writeFrame + frameCount, memory_order_release);
}

uint32_t HushPortSharedAudioReadFloat32(
    HushPortSharedAudio* sharedAudio,
    float* samples,
    uint32_t maximumFrameCount
) {
    if (sharedAudio == NULL || samples == NULL || maximumFrameCount == 0) {
        return 0;
    }

    HushPortSharedAudioStorage* storage = sharedAudio->storage;
    const uint64_t writeFrame = atomic_load_explicit(&storage->writeFrame, memory_order_acquire);
    uint64_t readFrame = sharedAudio->readFrame;
    if (writeFrame - readFrame > storage->capacityFrames) {
        readFrame = writeFrame - storage->capacityFrames;
    }
    const uint64_t available = writeFrame - readFrame;
    const uint32_t frameCount = available < maximumFrameCount ? (uint32_t)available : maximumFrameCount;
    if (frameCount == 0) {
        return 0;
    }

    const uint32_t start = (uint32_t)(readFrame % storage->capacityFrames);
    const uint32_t firstFrames = frameCount < (storage->capacityFrames - start)
        ? frameCount : (storage->capacityFrames - start);
    memcpy(samples, &storage->samples[(size_t)start * HUSHPORT_SHARED_AUDIO_CHANNELS],
           (size_t)firstFrames * HUSHPORT_SHARED_AUDIO_CHANNELS * sizeof(float));
    if (firstFrames < frameCount) {
        memcpy(samples + ((size_t)firstFrames * HUSHPORT_SHARED_AUDIO_CHANNELS), storage->samples,
               (size_t)(frameCount - firstFrames) * HUSHPORT_SHARED_AUDIO_CHANNELS * sizeof(float));
    }
    sharedAudio->readFrame = readFrame + frameCount;
    return frameCount;
}

void HushPortSharedAudioCatchUp(HushPortSharedAudio* sharedAudio, uint32_t maxLatencyFrames)
{
    if (sharedAudio == NULL || maxLatencyFrames == 0) {
        return;
    }

    HushPortSharedAudioStorage* storage = sharedAudio->storage;
    const uint64_t writeFrame = atomic_load_explicit(&storage->writeFrame, memory_order_acquire);
    if (writeFrame > sharedAudio->readFrame + maxLatencyFrames) {
        sharedAudio->readFrame = writeFrame - maxLatencyFrames;
    }
}
