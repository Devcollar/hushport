#include "HushPortRingBuffer.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct PHRingBuffer {
    uint8_t *storage;
    uint32_t frameCapacity;
    uint32_t bytesPerFrame;
    _Atomic uint64_t readFrame;
    _Atomic uint64_t writeFrame;
};

PHRingBuffer *PHRingBufferCreate(uint32_t frameCapacity, uint32_t bytesPerFrame) {
    if (frameCapacity == 0 || bytesPerFrame == 0 ||
        frameCapacity > SIZE_MAX / bytesPerFrame) {
        return NULL;
    }

    PHRingBuffer *buffer = calloc(1, sizeof(PHRingBuffer));
    if (buffer == NULL) {
        return NULL;
    }
    buffer->storage = malloc((size_t)frameCapacity * bytesPerFrame);
    if (buffer->storage == NULL) {
        free(buffer);
        return NULL;
    }
    buffer->frameCapacity = frameCapacity;
    buffer->bytesPerFrame = bytesPerFrame;
    atomic_init(&buffer->readFrame, 0);
    atomic_init(&buffer->writeFrame, 0);
    return buffer;
}

void PHRingBufferDestroy(PHRingBuffer *buffer) {
    if (buffer == NULL) return;
    free(buffer->storage);
    free(buffer);
}

static uint32_t readableFrames(const PHRingBuffer *buffer) {
    uint64_t write = atomic_load_explicit(&buffer->writeFrame, memory_order_acquire);
    uint64_t read = atomic_load_explicit(&buffer->readFrame, memory_order_acquire);
    uint64_t available = write - read;
    return available > buffer->frameCapacity
        ? buffer->frameCapacity
        : (uint32_t)available;
}

uint32_t PHRingBufferWrite(PHRingBuffer *buffer, const void *source, uint32_t frameCount) {
    if (buffer == NULL || source == NULL || frameCount == 0) return 0;

    uint64_t write = atomic_load_explicit(&buffer->writeFrame, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&buffer->readFrame, memory_order_acquire);
    uint32_t writable = buffer->frameCapacity - (uint32_t)(write - read);
    uint32_t count = frameCount < writable ? frameCount : writable;
    uint32_t start = (uint32_t)(write % buffer->frameCapacity);
    uint32_t first = count < buffer->frameCapacity - start
        ? count
        : buffer->frameCapacity - start;

    memcpy(buffer->storage + (size_t)start * buffer->bytesPerFrame,
           source,
           (size_t)first * buffer->bytesPerFrame);
    if (first < count) {
        memcpy(buffer->storage,
               (const uint8_t *)source + (size_t)first * buffer->bytesPerFrame,
               (size_t)(count - first) * buffer->bytesPerFrame);
    }
    atomic_store_explicit(&buffer->writeFrame, write + count, memory_order_release);
    return count;
}

uint32_t PHRingBufferRead(PHRingBuffer *buffer, void *destination, uint32_t frameCount) {
    if (buffer == NULL || destination == NULL || frameCount == 0) return 0;

    uint64_t read = atomic_load_explicit(&buffer->readFrame, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&buffer->writeFrame, memory_order_acquire);
    uint32_t available = (uint32_t)(write - read);
    uint32_t count = frameCount < available ? frameCount : available;
    uint32_t start = (uint32_t)(read % buffer->frameCapacity);
    uint32_t first = count < buffer->frameCapacity - start
        ? count
        : buffer->frameCapacity - start;

    memcpy(destination,
           buffer->storage + (size_t)start * buffer->bytesPerFrame,
           (size_t)first * buffer->bytesPerFrame);
    if (first < count) {
        memcpy((uint8_t *)destination + (size_t)first * buffer->bytesPerFrame,
               buffer->storage,
               (size_t)(count - first) * buffer->bytesPerFrame);
    }
    atomic_store_explicit(&buffer->readFrame, read + count, memory_order_release);
    return count;
}

uint32_t PHRingBufferReadableFrames(const PHRingBuffer *buffer) {
    return buffer == NULL ? 0 : readableFrames(buffer);
}

uint32_t PHRingBufferWritableFrames(const PHRingBuffer *buffer) {
    return buffer == NULL ? 0 : buffer->frameCapacity - readableFrames(buffer);
}

uint32_t PHRingBufferFrameCapacity(const PHRingBuffer *buffer) {
    return buffer == NULL ? 0 : buffer->frameCapacity;
}

void PHRingBufferReset(PHRingBuffer *buffer) {
    if (buffer == NULL) return;
    // Reset only while producer and consumer are stopped.
    atomic_store_explicit(&buffer->readFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&buffer->writeFrame, 0, memory_order_relaxed);
}
