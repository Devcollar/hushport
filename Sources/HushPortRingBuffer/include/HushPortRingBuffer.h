#ifndef HUSHPORT_RING_BUFFER_H
#define HUSHPORT_RING_BUFFER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "HushPortSharedAudio.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PHRingBuffer PHRingBuffer;

/// Allocates a single-producer/single-consumer ring buffer. Never call from an
/// audio render callback; creation and destruction may allocate memory.
PHRingBuffer *PHRingBufferCreate(uint32_t frameCapacity, uint32_t bytesPerFrame);
void PHRingBufferDestroy(PHRingBuffer *buffer);

/// Copies as many complete frames as fit. These functions do not allocate,
/// lock, block, or perform I/O and are safe for the real-time audio callback.
uint32_t PHRingBufferWrite(
    PHRingBuffer *buffer,
    const void *source,
    uint32_t frameCount
);
uint32_t PHRingBufferRead(
    PHRingBuffer *buffer,
    void *destination,
    uint32_t frameCount
);

uint32_t PHRingBufferReadableFrames(const PHRingBuffer *buffer);
uint32_t PHRingBufferWritableFrames(const PHRingBuffer *buffer);
uint32_t PHRingBufferFrameCapacity(const PHRingBuffer *buffer);
void PHRingBufferReset(PHRingBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
