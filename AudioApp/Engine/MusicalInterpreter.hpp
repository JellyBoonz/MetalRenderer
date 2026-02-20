#pragma once

#include "MusicalContext.hpp"

class AudioAnalyzer;

class MusicalInterpreter {
public:
    MusicalContext interpret(const AudioAnalyzer& analyzer) const;
};
