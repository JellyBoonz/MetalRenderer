#include <metal_stdlib>
using namespace metal;

#include "VertexData.hpp"

struct VertexOut {
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 position [[position]];

    // Since this member does not have a special attribute, the rasterizer
    // interpolates its value with the values of the other triangle vertices
    // and then passes the interpolated value to the fragment shader for each
    // fragment in the triangle.
    float2 textureCoordinate;
};

// How are shader functions processed?
vertex VertexOut vertexShader(uint vertexID [[vertex_id]], constant VertexData* vertexData, constant TransformationData* transformationData, constant LightingData* lightData) {
    VertexOut out;
    out.position = transformationData->perspectiveMatrix * transformationData->viewMatrix * transformationData->modelMatrix * vertexData[vertexID].position;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],  constant float4& color [[ buffer(0) ]]) {
    
    // Sample the texture to obtain a color
    return color;
}

