#pragma once
#include <Metal/Metal.hpp>
#include "../external/stb/stb_image.h"

class Texture {
public:
    Texture(const char* filepath, MTL::Device* metalDevice);
    ~Texture();
    MTL::Texture* texture;
    int width, height, channels;

private:
    MTL::Device* device;
};
