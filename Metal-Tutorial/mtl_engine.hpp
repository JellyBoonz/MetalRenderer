#pragma once

#define GLFW_INCLUDE_NONE
#import <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#import <GLFW/glfw3native.h>

#include <QuartzCore/CAMetalLayer.hpp>
#include <QuartzCore/CAMetalLayer.h>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h> // Apple library for calculating vector and matrix computations efficiently
#include <iostream>
#include "../external/stb/stb_image.h"

#include "VertexData.hpp"
#include "Texture.hpp"
#include "Camera.hpp"
#include "../external/stb/stb_image.h"
#include "AAPLMathUtilities.h"

#include <filesystem>

class MtlEngine
{
public:
    void init();
    void run();
    void cleanup();
    
    MTL::Device* getDevice();

private:
    void initDevice();
    void initWindow();

    // Create objects
    void createTriangle();
    void createSquare();
    void createCube();
    void createPlane();
    void createLight();

    void createDefaultLibrary();
    void createCommandQueue();
    void createShadowCommandQueue();
    void createRenderPipeline();
    void createLightSourceRenderPipeline();
    void createBlinnPhongRenderPipeline();
    void createBPNoShadowRenderPipeline();
    void createShadowPipeline();

    void createBuffers();
    void createDepthAndMSAATextures();
    void createRenderPassDescriptor();
    void createShadowPassDescriptor();
    void createShadowMapSampler();
    void createShadowMapTexture();

    static void mouseCallback(GLFWwindow *window, double xpos, double ypos);
    static void scrollCallback(GLFWwindow *window, double xoffset, double yoffset);

    // Upon resizing, update Depth and MSAA Textures;
    void updateRenderPassDescriptor();
    void updateSharedTransformData();

    void encodeRenderCommand(MTL::RenderCommandEncoder *renderEncoder);
    void encodeMainCube(MTL::RenderCommandEncoder *renderCommandEncoder);
    void encodeLightCube(MTL::RenderCommandEncoder *renderCommandEncoder);
    void encodePlane(MTL::RenderCommandEncoder *renderCommandEncoder); // For your new plane
    void drawImGui(MTL::RenderCommandEncoder *renderCommandEncoder);
    void sendRenderCommand();
    void renderShadowPass();

    void draw();

    static void frameBufferSizeCallback(GLFWwindow *window, int width, int height);
    void resizeFrameBuffer(int width, int height);

    matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
    {
        float ys = 1 / tanf(fovyRadians * 0.5);
        float xs = ys / aspect;
        float zs = farZ / (nearZ - farZ);
        return matrix_make_rows(xs, 0, 0, 0,
                                0, ys, 0, 0,
                                0, 0, zs, nearZ * zs,
                                0, 0, -1, 0);
    }

    MTL::Device *metalDevice; // Gives us access to our device's GPU
    GLFWwindow *glfwWindow;
    NSWindow *metalWindow;
    CAMetalLayer *metalLayer;
    CA::MetalDrawable *metalDrawable;

    MTL::Library *metalDefaultLibrary;

    MTL::CommandQueue *metalCommandQueue;
    MTL::CommandQueue *shadowCommandQueue;
    MTL::CommandBuffer *metalCommandBuffer;
    MTL::CommandBuffer *shadowCommandBuffer;

    MTL::RenderPipelineState *metalRenderPSO;
    MTL::RenderPipelineState *metalLightSourceRenderPSO;
    MTL::RenderPipelineState *blinnPhongRenderPSO;
    MTL::RenderPipelineState *blinnPhongNoShadowRenderPSO;
    MTL::RenderPipelineState *shadowRenderPSO;

    MTL::Buffer *triangleVertexBuffer;
    MTL::Buffer *squareVertexBuffer;
    MTL::Buffer *cubeVertexBuffer;
    
    MTL::Buffer *lightVertexBuffer;
    MTL::Buffer *lightCubeVertexBuffer;
    MTL::Buffer *lightTransformationBuffer;
    MTL::Buffer *lightingBuffer;
    
    MTL::Buffer *planeVertexBuffer;
    MTL::Buffer *planeTransformBuffer;
    MTL::Buffer *transformationBuffer;
    MTL::Buffer *shadowTransformBuffer;

    MTL::DepthStencilState *depthStencilState;
    MTL::RenderPassDescriptor *renderPassDescriptor;
    MTL::RenderPassDescriptor *shadowPassDescriptor;

    MTL::SamplerState *shadowSampler;
    MTL::Texture *msaaRenderTargetTexture = nullptr;
    MTL::Texture *depthTexture;
    MTL::Texture *shadowMapTexture;

    int sampleCount = 4;

    Texture *grassTexture;

    Camera *camera;
    float lastFrameTime;

    // ImGui controlled positions
    simd::float3 lightPosition = {0.0f, 2.0f, 0.0f};
    simd::float3 cubePosition = {0.0f, 0.0f, -1.0f};
    simd::float3 lightColor = {1.0f, 1.0f, 1.0f};
};
