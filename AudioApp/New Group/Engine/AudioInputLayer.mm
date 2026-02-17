// AudioInputMinimal.mm
// Minimal AVAudioEngine capture that computes per-buffer RMS and a rolling average.

#import <AVFoundation/AVFoundation.h>
#include <vector>
#include <atomic>
#include <mutex>
#include <cmath>

struct RollingAverage {
    std::vector<float> window;
    size_t maxSize = 120; // default window size
    size_t idx = 0;
    size_t count = 0;
    float sum = 0.0f;
    mutable std::mutex mtx;

    void setMaxSize(size_t n) {
        std::lock_guard<std::mutex> lock(mtx);
        maxSize = n;
        window.clear();
        window.reserve(maxSize);
        idx = count = 0;
        sum = 0.0f;
    }

    void push(float v) {
        std::lock_guard<std::mutex> lock(mtx);
        if (count < maxSize) {
            window.push_back(v);
            sum += v;
            count++;
        } else {
            sum -= window[idx];
            window[idx] = v;
            sum += v;
            idx = (idx + 1) % maxSize;
        }
    }

    // Average over 120 RMS samples
    float average() const {
        std::lock_guard<std::mutex> lock(mtx);
        return (count > 0) ? (sum / (float)count) : 0.0f;
    }
};

static AVAudioEngine *gEngine = nil;
static std::atomic<float> gCurrentRMS {0.0f};
static RollingAverage gRolling;

// Average over 1024 frames (~21 ms)
static float computeRMS(AVAudioPCMBuffer *buffer) {
    AVAudioFrameCount frames = buffer.frameLength;
    if (frames == 0) return 0.0f;
    AVAudioChannelCount chs = buffer.format.channelCount;

    // Summing the samples from each channel for every frame
    double sumSq = 0.0;
    for (AVAudioChannelCount ch = 0; ch < chs; ++ch) {
        float *data = buffer.floatChannelData[ch];
        for (AVAudioFrameCount i = 0; i < frames; ++i) {
            float s = data[i];
            sumSq += (double)s * (double)s;
        }
    }
    double mean = sumSq / (double)(frames * chs);
    return (float)std::sqrt(mean);
}

extern "C" bool audioInputMinimal_start() {
    @try {
        gEngine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *input = [gEngine inputNode];
        if (!input) {
            NSLog(@"AudioInputMinimal: No input node available.");
            return false;
        }

        gRolling.setMaxSize(120); // ~short smoothing window

        AVAudioFormat *format = [input outputFormatForBus:0];
        __block uint64_t printCounter = 0;

        // Recording tap to recieve data from the input node
        [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            float rms = computeRMS(buffer);
            gCurrentRMS.store(rms, std::memory_order_relaxed);
            gRolling.push(rms);
            if ((++printCounter % 30) == 0) {
                float avg = gRolling.average();
                NSLog(@"RMS: %.4f, RollingAvg: %.4f", rms, avg);
            }
        }];

        NSError *error = nil;
        if (![gEngine startAndReturnError:&error]) {
            NSLog(@"AudioInputMinimal: Failed to start engine: %@", error);
            return false;
        }
        NSLog(@"AudioInputMinimal: Started.");
        return true;
    } @catch (NSException *ex) {
        NSLog(@"AudioInputMinimal: Exception: %@", ex);
        return false;
    }
}

extern "C" void audioInputMinimal_stop() {
    if (gEngine) {
        [[gEngine inputNode] removeTapOnBus:0];
        [gEngine stop];
        gEngine = nil;
    }
}

extern "C" float audioInputMinimal_currentRMS() {
    return gCurrentRMS.load(std::memory_order_relaxed);
}

extern "C" float audioInputMinimal_rollingAvg() {
    return gRolling.average();
}
