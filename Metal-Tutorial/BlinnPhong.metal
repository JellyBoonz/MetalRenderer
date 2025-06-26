#include <metal_stdlib>
using namespace metal;

#include "VertexData.hpp"

struct VertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
    float3 worldPos;
    float3 normal;
};

vertex VertexOut vertexBP(uint vertexID [[vertex_id]],
                          constant VertexData* vertexData[[buffer(0)]],
                          constant TransformationData* transformationData[[buffer(1)]]){
    VertexOut out;
    
    out.position = transformationData->perspectiveMatrix * transformationData->viewMatrix * transformationData->modelMatrix * vertexData[vertexID].position;
    
    out.textureCoordinate = vertexData[vertexID].textureCoordinate;
    
    out.worldPos = (transformationData->modelMatrix * vertexData[vertexID].position).xyz;
    
    float3x3 normalMat = float3x3(transformationData->modelMatrix[0].xyz, transformationData->modelMatrix[1].xyz, transformationData->modelMatrix[2].xyz);
    
    out.normal = normalize(normalMat * vertexData[vertexID].normal);
    
    return out;
}

fragment float4 fragmentBP(VertexOut in [[stage_in]],
                           constant float3& materialColor [[buffer(0)]],
                           constant LightingData* lightingData[[buffer(3)]]) {
    
    float3 viewDir = normalize(lightingData->cameraPos - in.worldPos);
    float3 lightDir = normalize(lightingData->lightPos - in.worldPos);
    float3 halfDir = normalize(lightDir + viewDir);
    
    float3 ambient = lightingData->ambientIntensity * lightingData->lightColor;
    
    float diff = max(dot(in.normal, lightDir),0.0);
    float3 diffuse = diff * lightingData->lightColor;
    
    float spec = pow(max(dot(in.normal, halfDir), 0.0), lightingData->shininess);
    float3 specular = lightingData->lightColor * spec;
    
    float3 result = (ambient + diffuse + specular) * materialColor;
    float4 fragColor = float4(result, 1.0);
    
    return fragColor;
}
