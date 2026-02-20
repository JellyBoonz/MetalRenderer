#include <AVFoundation/AVFoundation.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <vector>

#include "AudioAnalyzer.hpp"

AudioAnalyzer::AudioAnalyzer()
: _fftSetup(vDSP_create_fftsetup(kFFTLog2, kFFTRadix2)) {
        
        _windowBuffer.resize(kFFTSize);
        _windowedBuffer.resize(kFFTSize);
        _realpBuffer.resize(kFFTSize / 2);
        _imagpBuffer.resize(kFFTSize / 2);
        _spectrumMagnitudes.resize(kSpectrumSize, 0.0f);
        
        vDSP_hann_window(_windowBuffer.data(), kFFTSize, vDSP_HANN_NORM);
}

AudioAnalyzer::~AudioAnalyzer() {
    vDSP_destroy_fftsetup(_fftSetup);
}

void AudioAnalyzer::processBuffer(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
    _sampleRate = (float)buffer.format.sampleRate;
    currentFeatures.rms = computeRMS(buffer);
    currentFeatures.rollingAvg = gRolling.average();
    gCurrentRMS.store(currentFeatures.rms, std::memory_order_relaxed);
    gRolling.push(currentFeatures.rms);
    
    computeSpectrum(buffer);

    auto [pitchHz, confidence] = computePitchMPM(_windowedBuffer.data(), kFFTSize, _sampleRate);
    _detectedPitchHz = pitchHz;
    _pitchConfidence = confidence;

    BandEnergies raw = computeRawBandEnergies();
    _smoothedBass = kBandSmoothAlpha * raw.bass + (1.0f - kBandSmoothAlpha) * _smoothedBass;
    _smoothedMid = kBandSmoothAlpha * raw.mid + (1.0f - kBandSmoothAlpha) * _smoothedMid;
    _smoothedTreble = kBandSmoothAlpha * raw.treble + (1.0f - kBandSmoothAlpha) * _smoothedTreble;
}

AudioFeatures AudioAnalyzer::getFeatures() const {
    return currentFeatures;
}

float AudioAnalyzer::computeRMS(AVAudioPCMBuffer *buffer) {
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

void AudioAnalyzer::computeSpectrum(AVAudioPCMBuffer *buffer) {
    AVAudioFrameCount frames = buffer.frameLength;
    if (frames < kFFTSize || !buffer.floatChannelData) return;
    
    float* channelData = buffer.floatChannelData[0];
    if (!channelData) return;

    for (size_t i = 0; i < kFFTSize; ++i)
        _windowedBuffer[i] = channelData[i] * _windowBuffer[i];

    DSPSplitComplex splitComplex;
    splitComplex.realp = _realpBuffer.data();
    splitComplex.imagp = _imagpBuffer.data();
    
    // 1. Apply window and pack real input into split-complex format.
    //    For vDSP_fft_zrip: even samples -> realp, odd samples -> imagp
    for (size_t i = 0; i < kFFTSize / 2; ++i) {
        _realpBuffer[i] = channelData[2 * i] * _windowBuffer[2 * i];
        _imagpBuffer[i] = channelData[2 * i + 1] * _windowBuffer[2 * i + 1];
    }
    
    // 2. Forward FFT (in-place)
    vDSP_fft_zrip(_fftSetup, &splitComplex, 1, kFFTLog2, FFT_FORWARD);
        
    // 3. Compute magnitudes (bin 0 = DC, bin kSpectrumSize-1 = Nyquist)
    vDSP_zvabs(&splitComplex, 1, _spectrumMagnitudes.data(), 1, kSpectrumSize);
    
    float scale = 2.0f / (float)kFFTSize;
    vDSP_vsmul(_spectrumMagnitudes.data(), 1, &scale, _spectrumMagnitudes.data(), 1, kSpectrumSize);
}

BandEnergies AudioAnalyzer::getBandEnergies() const {
    return BandEnergies{_smoothedBass, _smoothedMid, _smoothedTreble};
}

BandEnergies AudioAnalyzer::computeRawBandEnergies() const {
    BandEnergies out = {0.0f, 0.0f, 0.0f};
    if (_spectrumMagnitudes.empty() || _sampleRate <= 0.0f) return out;

    constexpr float kBassHigh = 155.0f;
    constexpr float kMidHigh = 880.0f;
    constexpr float kTrebleHigh = 4186.0f;
    
    // Finding the bin index for each segment end (frequency / bin width)
    int bassEnd = (int)(kBassHigh * (float)kFFTSize / _sampleRate);
    int midEnd = (int)(kMidHigh * (float)kFFTSize / _sampleRate);
    int trebleEnd = (int)(kTrebleHigh * (float)kFFTSize / _sampleRate);
    
    bassEnd = std::max(1, std::min(bassEnd, (int)_spectrumMagnitudes.size() - 1));
    midEnd = std::max(bassEnd, std::min(midEnd, (int)_spectrumMagnitudes.size() - 1));
    trebleEnd = std::max(midEnd, std::min(trebleEnd, (int)_spectrumMagnitudes.size() - 1));

    for (int i = 1; i <= bassEnd; ++i)
        out.bass += _spectrumMagnitudes[i];
    for (int i = bassEnd + 1; i <= midEnd; ++i)
        out.mid += _spectrumMagnitudes[i];
    for (int i = midEnd + 1; i <= trebleEnd; ++i)
        out.treble += _spectrumMagnitudes[i];

    return out;
}

std::pair<float, float> AudioAnalyzer::computePitchMPM(const float* samples, size_t n, float sampleRate) {
    if (!samples || n < 2 || sampleRate <= 0.0f)
        return {0.0f, 0.0f};

    int minLag = (int)(sampleRate / 1500.0f);
    int maxLag = (int)(sampleRate / 50.0f);
    minLag = std::max(1, minLag);
    maxLag = std::min(maxLag, (int)n - 1);
    if (minLag >= maxLag)
        return {0.0f, 0.0f};

    float bestCorr = -1.0f;
    int bestLag = minLag;

    // Finding the best lag helps to find the period, which is the pitch.
    // We compare the pairwise values at samples[i] and samples[i + lag] to find the best correlation.
    // Values that are similar will have a high correlation, while values that are different will have a low correlation.
    for (int lag = minLag; lag <= maxLag; lag++) {
        float sumXY = 0.0f, sumX2 = 0.0f, sumY2 = 0.0f;
        for (int i = 0; i < (int)n - lag; i++) {
            float x = samples[i];
            float y = samples[i + lag];
            sumXY += x * y;
            sumX2 += x * x;
            sumY2 += y * y;
        }
        float denom = std::sqrt(sumX2 * sumY2); // normalizing the correlation so that we aren't biased by amplitude
        float corr = (denom > 1e-10f) ? (sumXY / denom) : 0.0f;
        if (corr > bestCorr) {
            bestCorr = corr;
            bestLag = lag;
        }
    }

    float pitchHz = sampleRate / (float)bestLag;
    float confidence = std::max(0.0f, std::min(1.0f, bestCorr));
    return {pitchHz, confidence};
}
