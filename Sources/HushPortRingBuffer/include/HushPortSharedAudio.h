#ifndef HUSHPORT_SHARED_AUDIO_H
#define HUSHPORT_SHARED_AUDIO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HushPortSharedAudio HushPortSharedAudio;

HushPortSharedAudio* HushPortSharedAudioOpenWriter(void);
HushPortSharedAudio* HushPortSharedAudioOpenReader(void);
void HushPortSharedAudioClose(HushPortSharedAudio* sharedAudio);
void HushPortSharedAudioWriteFloat32(
    HushPortSharedAudio* sharedAudio,
    const float* interleavedStereoSamples,
    uint32_t frameCount
);
uint32_t HushPortSharedAudioReadFloat32(
    HushPortSharedAudio* sharedAudio,
    float* interleavedStereoSamples,
    uint32_t maximumFrameCount
);
void HushPortSharedAudioCatchUp(HushPortSharedAudio* sharedAudio, uint32_t maxLatencyFrames);

#ifdef __cplusplus
}
#endif

#endif
