#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

static ma_device gAudioDevice;

static void audio_data_callback(ma_device* pDevice,
                                void* pOutput,
                                const void* pInput,
                                ma_uint32 frameCount)
{
    (void)pDevice; // unused
    (void)pOutput; // unused for capture

    if (pInput == nullptr) {
        return;
    }

    const float* samples = (const float*)pInput; // assuming mono float
    double sum = 0.0;

    for (ma_uint32 i = 0; i < frameCount; ++i) {
        sum += fabs(samples[i]);
    }

    double avg = (frameCount > 0) ? (sum / frameCount) : 0.0;

    // For now: just print. You should see this respond to mic input.
    printf("Audio avg amplitude: %f\n", avg);
}

bool initAudioCapture()
{
    ma_device_config config = ma_device_config_init(ma_device_type_capture);

    config.capture.format   = ma_format_f32; // 32-bit float
    config.capture.channels = 1;             // mono
    config.sampleRate       = 48000;         // or 44100, either is fine for now
    config.dataCallback     = audio_data_callback;
    config.pUserData        = nullptr;       // not using this yet

    if (ma_device_init(nullptr, &config, &gAudioDevice) != MA_SUCCESS) {
        printf("Failed to init audio capture device\n");
        return false;
    }
    
    printf("Capture device name: %s\n", gAudioDevice.capture.name);
    printf("Capture channels: %u\n", gAudioDevice.capture.channels);
    printf("Capture format: %d\n", gAudioDevice.capture.format);

    if (ma_device_start(&gAudioDevice) != MA_SUCCESS) {
        printf("Failed to start audio capture device\n");
        ma_device_uninit(&gAudioDevice);
        return false;
    }

    return true;
}

void shutdownAudioCapture()
{
    ma_device_uninit(&gAudioDevice);
}
