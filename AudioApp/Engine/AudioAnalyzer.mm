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
