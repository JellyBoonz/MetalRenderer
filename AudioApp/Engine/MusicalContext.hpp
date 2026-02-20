#pragma once

// Phase 2 will add: chordRoot, quality, tension, stability
struct MusicalContext {
    float energy = 0.5f;           // 0-1, from RMS/rollingAvg
    float brightness = 0.5f;       // 0-1, from band ratio
    float melancholy = 0.5f;       // 0-1, higher = sadder
    float dominantPitch = 0.0f;   // Hz, from MPM; 0 = invalid
    float pitchConfidence = 0.0f;  // 0-1, gates pitch-based features
};
