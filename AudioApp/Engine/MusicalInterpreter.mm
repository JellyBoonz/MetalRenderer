#include "MusicalInterpreter.hpp"
#include "AudioAnalyzer.hpp"
#include <algorithm>
#include <cmath>

namespace {
constexpr float kEnergyScale = 150.0f;
constexpr float kPitchConfidenceThreshold = 0.25f;
constexpr float kMinPitch = 50.0f;
constexpr float kMaxPitch = 2000.0f;
constexpr int kSpectrumWindowRadius = 2;
}  // namespace

MusicalContext MusicalInterpreter::interpret(const AudioAnalyzer& analyzer) const {
    MusicalContext ctx;

    // Energy from rolling average
    float rollingAvg = analyzer.getFeatures().rollingAvg;
    ctx.energy = std::min(1.0f, rollingAvg * kEnergyScale);

    // Brightness from band ratio
    BandEnergies bands = analyzer.getBandEnergies();
    constexpr float kBassBoost = 5.0f;
    constexpr float kMidBoost = 0.8f;
    constexpr float kTrebleBoost = 1.0f;
    float bass = std::sqrt(std::max(0.0f, bands.bass * kBassBoost));
    float mid = std::sqrt(std::max(0.0f, bands.mid * kMidBoost));
    float treble = std::sqrt(std::max(0.0f, bands.treble * kTrebleBoost));
    float total = bass + mid + treble;
    constexpr float kEps = 1e-6f;
    ctx.brightness = (total > kEps) ? (treble / total) : 0.5f;

    // Dominant pitch and confidence (pass through)
    ctx.dominantPitch = analyzer.getDetectedPitch();
    ctx.pitchConfidence = analyzer.getPitchConfidence();

    // Melancholy
    bool usePitchHeuristic = (ctx.pitchConfidence >= kPitchConfidenceThreshold &&
                              ctx.dominantPitch >= kMinPitch &&
                              ctx.dominantPitch <= kMaxPitch);

    if (usePitchHeuristic) {
        const std::vector<float>& spectrum = analyzer.getSpectrumMagnitudes();
        float sampleRate = analyzer.getSampleRate();

        if (!spectrum.empty() && sampleRate > 0.0f) {
            // Minor third: pitch * 2^(3/12), major third: pitch * 2^(4/12)
            float minorFreq = ctx.dominantPitch * std::pow(2.0f, 3.0f / 12.0f);
            float majorFreq = ctx.dominantPitch * std::pow(2.0f, 4.0f / 12.0f);

            auto freqToBin = [sampleRate](float freq) {
                return (int)(freq * (float)kFFTSize / sampleRate);
            };
            auto sumAroundBin = [&spectrum](int centerBin) {
                float sum = 0.0f;
                int lo = std::max(1, centerBin - kSpectrumWindowRadius);
                int hi = std::min((int)spectrum.size() - 1, centerBin + kSpectrumWindowRadius);
                for (int i = lo; i <= hi; ++i)
                    sum += spectrum[i];
                return sum;
            };

            int minorBin = freqToBin(minorFreq);
            int majorBin = freqToBin(majorFreq);
            float minorEnergy = sumAroundBin(minorBin);
            float majorEnergy = sumAroundBin(majorBin);

            float denom = majorEnergy + minorEnergy + kEps;
            float ratio = minorEnergy / denom;

            ctx.melancholy = 0.6f * ratio + 0.2f * (1.0f - ctx.brightness) + 0.2f * (1.0f - ctx.energy);
            ctx.melancholy = std::max(0.0f, std::min(1.0f, ctx.melancholy));
        } else {
            ctx.melancholy = 0.5f * (1.0f - ctx.brightness) + 0.5f * (1.0f - ctx.energy);
        }
    } else {
        ctx.melancholy = 0.5f * (1.0f - ctx.brightness) + 0.5f * (1.0f - ctx.energy);
    }

    return ctx;
}
