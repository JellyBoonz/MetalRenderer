#pragma once
#import <AVFoundation/AVFoundation.h>

#include <Accelerate/Accelerate.h>
#include <atomic>
#include <vector>

struct AudioFeatures {
    float rms;
    float rollingAvg;
};

struct BandEnergies {
    float bass;
    float mid;
    float treble;
};

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

static constexpr size_t kFFTSize = 1024;
static constexpr size_t kFFTLog2 = 10;
static constexpr size_t kSpectrumSize = kFFTSize / 2 + 1;
static constexpr float kBandSmoothAlpha = 0.15f;  // EMA: lower = smoother, higher = snappier

class AudioAnalyzer {
public:
    AudioAnalyzer();
    ~AudioAnalyzer();
    void processBuffer(AVAudioPCMBuffer* buffer, AVAudioTime* when);
    AudioFeatures getFeatures() const;
    
    const std::vector<float>& getSpectrumMagnitudes() const {return _spectrumMagnitudes; }
    float getSampleRate() const { return _sampleRate; }
    BandEnergies getBandEnergies() const;
    
private:
    AudioFeatures currentFeatures;
    std::atomic<float> gCurrentRMS {0.0f};
    RollingAverage gRolling;
    
    float computeRMS(AVAudioPCMBuffer *buffer);
    void computeSpectrum(AVAudioPCMBuffer *buffer);
    BandEnergies computeRawBandEnergies() const;
        
    // FFT state
    FFTSetup _fftSetup;
    std::vector<float> _windowBuffer;
    std::vector<float> _realpBuffer;
    std::vector<float> _imagpBuffer;
    std::vector<float> _spectrumMagnitudes;
    float _sampleRate = 0.0f;
    
    // Smoothed band energies (EMA, like RollingAverage for RMS)
    float _smoothedBass = 0.0f;
    float _smoothedMid = 0.0f;
    float _smoothedTreble = 0.0f;
};
