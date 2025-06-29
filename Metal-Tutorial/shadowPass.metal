#include <metal_stdlib>
using namespace metal;
#include "VertexData.hpp"

vertex float4 shadowVertex(uint vertexID [[vertex_id]],
                           constant VertexData* vertexData [[buffer(0)]],
                           constant TransformationData* lightTransform [[buffer(1)]]) {
    return lightTransform->perspectiveMatrix * lightTransform->viewMatrix * lightTransform->modelMatrix * vertexData[vertexID].position;
}

