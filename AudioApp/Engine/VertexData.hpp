#pragma once
#include <simd/simd.h>

using namespace simd;

struct VertexData
{
    float4 position; // Vertices
    float2 textureCoordinate;
    float3 normal;
};

struct TransformationData
{
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 perspectiveMatrix;
};

struct LightingData
{
    float3 cameraPos;
    float3 lightPos;
    float3 lightColor;
    float lightIntensity;
    float ambientIntensity;
    float shininess;
};
