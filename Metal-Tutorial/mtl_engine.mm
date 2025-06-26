#include "mtl_engine.hpp"
#include "../external/imgui/imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"

void MtlEngine::init() {
    initDevice();
    initWindow();

//    simd::float3 cubeCenter = simd::float3 {0,0,-1};
    camera = new Camera();
//    camera->target = cubeCenter;
    
    createCube();
    createLight(); // Light cube
    createPlane();
    createBuffers();
    createDefaultLibrary();
    createCommandQueue();
    createBlinnPhongRenderPipeline();
    createLightSourceRenderPipeline();
    createDepthAndMSAATextures();
    createRenderPassDescriptor();
    // ImGui initialization
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    ImGui::StyleColorsDark();
    ImGui_ImplGlfw_InitForOther(glfwWindow, true);
    ImGui_ImplMetal_Init((__bridge id<MTLDevice>)metalDevice);
}

void MtlEngine::run() {
    while(!glfwWindowShouldClose(glfwWindow)) {
        @autoreleasepool {
            metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
            
            if (glfwGetKey(glfwWindow, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
                glfwSetWindowShouldClose(glfwWindow, true);
            }
            
            camera->update();
            
            // Start ImGui frame
//            CGSize renderSize = metalLayer.drawableSize;
            ImGui_ImplMetal_NewFrame((__bridge MTLRenderPassDescriptor*)renderPassDescriptor);
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();
            draw();
        } // Objects in the autoreleasepool have a lifetime of one frame of the main thread of the program.
        glfwPollEvents();
    }
}

void MtlEngine::cleanup() {
    // First destroy the GLFW window
    if (glfwWindow) {
        glfwDestroyWindow(glfwWindow);
        glfwWindow = nullptr;
    }
    
    // Then terminate GLFW
    glfwTerminate();
    
    // Clean up Metal resources
    transformationBuffer->release();
    lightTransformationBuffer->release();
    msaaRenderTargetTexture->release();
    depthTexture->release();
    renderPassDescriptor->release();
    metalDevice->release();
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}

void MtlEngine::createBuffers() {
    transformationBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    lightTransformationBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    planeTransformBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    lightingBuffer = metalDevice->newBuffer(sizeof(LightingData), MTL::ResourceStorageModeShared);
}

void MtlEngine::draw() {
    sendRenderCommand();
}

void MtlEngine::sendRenderCommand() {
    metalCommandBuffer = metalCommandQueue->commandBuffer();

    updateRenderPassDescriptor();

    // Encoding render commands for the render buffer
    MTL::RenderCommandEncoder* renderCommandEncoder = metalCommandBuffer->renderCommandEncoder(renderPassDescriptor);
    encodeRenderCommand(renderCommandEncoder);
    renderCommandEncoder->endEncoding();    // Telling command buffer we are done issuing commands for the GPU
    
    // Telling the command buffer to present the final drawable
    metalCommandBuffer->presentDrawable(metalDrawable);
    metalCommandBuffer->commit();   // Sending command buffer to GPU
    metalCommandBuffer->waitUntilCompleted();   // Halting the application until the GPU is done processing our command.
}

void MtlEngine::updateSharedTransformData() {
    matrix_float4x4 modelMatrix = matrix4x4_translation(0,0,-1.0);
    
    float time = glfwGetTime();
    matrix_float4x4 rotation = matrix4x4_rotation(time, 0.0f, 1.0f, 0.0f);
    matrix_float4x4 lightModelMatrix = matrix_multiply(rotation, matrix4x4_translation(1.2, 1.0, 2.0));
    matrix_float4x4 viewMatrix = camera->getViewMatrix();
    matrix_float4x4 planeModelMatrix = matrix4x4_translation(0, -1.0f, 0); // Slightly below origin
    planeModelMatrix = matrix_multiply(planeModelMatrix, matrix4x4_scale(10.0f, 1.0f, 10.0f)); // Big floor
    
    float aspectRatio = (metalLayer.frame.size.width / metalLayer.frame.size.height);
    camera->aspectRatio = aspectRatio;
    float fov = camera->fov * (M_PI / 180.0f);
    matrix_float4x4 projectionMatrix = matrix_perspective_right_hand(fov, aspectRatio, camera->nearPlane, camera->farPlane);

    TransformationData tMain = {modelMatrix, viewMatrix, projectionMatrix};
    memcpy(transformationBuffer->contents(), &tMain, sizeof(tMain));

    TransformationData tLight = {lightModelMatrix, viewMatrix, projectionMatrix};
    memcpy(lightTransformationBuffer->contents(), &tLight, sizeof(tLight));
    
    TransformationData planeTransform = {
        planeModelMatrix,
        viewMatrix,
        projectionMatrix
    };
    memcpy(planeTransformBuffer->contents(), &planeTransform, sizeof(planeTransform));

    LightingData lightingData;
    lightingData.cameraPos = camera->getPosition();
    lightingData.lightPos = simd::float3 {lightModelMatrix.columns[3].x, lightModelMatrix.columns[3].y, lightModelMatrix.columns[3].z};
    lightingData.lightColor = simd::float3 {1.0f, 1.0f, 1.0f};
    lightingData.lightIntensity = 0.7f;
    lightingData.ambientIntensity = 0.1f;
    lightingData.shininess = 32.0f;
    memcpy(lightingBuffer->contents(), &lightingData, sizeof(lightingData));
}

void MtlEngine::encodeMainCube(MTL::RenderCommandEncoder *renderCommandEncoder) {
    simd::float3 cubeColor = {1.0f, 0.5f, 0.31f};
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 36;
    renderCommandEncoder->setRenderPipelineState(blinnPhongRenderPSO);
    renderCommandEncoder->setDepthStencilState(depthStencilState);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    
    renderCommandEncoder->setVertexBuffer(cubeVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBuffer(transformationBuffer, 0, 1);
    renderCommandEncoder->setVertexBuffer(lightTransformationBuffer, 0, 2);
    renderCommandEncoder->setFragmentBuffer(lightingBuffer, 0, 3);
    renderCommandEncoder->setFragmentBytes(&cubeColor, sizeof(cubeColor), 0);
    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);
}

void MtlEngine::encodeLightCube(MTL::RenderCommandEncoder* renderCommandEncoder) {
    simd::float3 lightColor = {1.0f, 1.0f, 1.0f};
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 36;
    renderCommandEncoder->setRenderPipelineState(metalLightSourceRenderPSO);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    renderCommandEncoder->setVertexBuffer(lightVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBuffer(lightTransformationBuffer, 0, 1);
    renderCommandEncoder->setFragmentBytes(&lightColor, sizeof(lightColor), 0);
    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);
}

void MtlEngine::encodePlane(MTL::RenderCommandEncoder *renderCommandEncoder) {
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 6;
    renderCommandEncoder->setRenderPipelineState(blinnPhongRenderPSO);
    renderCommandEncoder->setDepthStencilState(depthStencilState);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);

    renderCommandEncoder->setVertexBuffer(planeVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBuffer(planeTransformBuffer, 0, 1);
    renderCommandEncoder->setVertexBuffer(lightTransformationBuffer, 0, 2);
    renderCommandEncoder->setFragmentBuffer(lightingBuffer, 0, 3);

    simd::float3 color = {0.5f, 0.7f, 0.5f};
    renderCommandEncoder->setFragmentBytes(&color, sizeof(color), 0);

    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);
    
}

void MtlEngine::drawImGui(MTL::RenderCommandEncoder *renderCommandEncoder) {
    // Build ImGui UI
    simd::float3 lightColor = {1.0f, 1.0f, 1.0f};
    ImGui::Begin("Engine Controls");
    static float pos[3] = {0.0f, 0.0f, 0.0f};
    static float rot[3] = {0.0f, 0.0f, 0.0f};
    static float scale[3] = {1.0f, 1.0f, 1.0f};
    ImGui::SliderFloat3("Object Position", pos, -10.0f, 10.0f);
    ImGui::SliderFloat3("Object Rotation", rot, 0.0f, 360.0f);
    ImGui::SliderFloat3("Object Scale", scale, 0.1f, 5.0f);
    ImGui::ColorEdit3("Light Color", reinterpret_cast<float*>(&lightColor));
    ImGui::End();
    
    // Render ImGui
    ImGui::Render();

    // Render ImGui draw data here, after all scene rendering, before endEncoding
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), (__bridge id<MTLCommandBuffer>)metalCommandBuffer, (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder);
}


void MtlEngine::encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder) {
    updateSharedTransformData();
    
    encodeMainCube(renderCommandEncoder);
    encodeLightCube(renderCommandEncoder);
    encodePlane(renderCommandEncoder);
    
    drawImGui(renderCommandEncoder);
}

/**
 The command queue is responsible for creating command buffers, which are chunks of works sent to the GPU from the command queue. These commands are executed via shader code.
 */
void MtlEngine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

/**
Note: Metal automatically compiles any shader code (files with .metal extension) inside of a metal project into a 'library'. The default library is where Metal looks for shader functions you've defined in the project.
 */
void MtlEngine::createDefaultLibrary() {
    metalDefaultLibrary = metalDevice->newDefaultLibrary(); // This loads all the compiled shader functions into library
    if(!metalDefaultLibrary){
        std::cerr << "Failed to load default library.";
        std::exit(-1);
    }
}

void MtlEngine::createRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertexShader", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragmentShader", NS::ASCIIStringEncoding));
    assert(fragmentShader);

    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    assert(renderPipelineDescriptor);
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
    renderPipelineDescriptor->setSampleCount(sampleCount);
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);

    NS::Error* error;
    metalRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

    if (metalRenderPSO == nil) {
        std::cout << "Error creating render pipeline state: " << error << std::endl;
        std::exit(0);
    }

    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);

    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MtlEngine::createBlinnPhongRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertexBP", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragmentBP", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    assert(renderPipelineDescriptor);
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
    renderPipelineDescriptor->setSampleCount(sampleCount);
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);

    NS::Error* error;
    blinnPhongRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

    if (metalRenderPSO == nil) {
        std::cout << "Error creating render pipeline state: " << error << std::endl;
        std::exit(0);
    }

    MTL::DepthStencilDescriptor* depthStencilDescriptor = MTL::DepthStencilDescriptor::alloc()->init();
    depthStencilDescriptor->setDepthCompareFunction(MTL::CompareFunctionLessEqual);
    depthStencilDescriptor->setDepthWriteEnabled(true);
    depthStencilState = metalDevice->newDepthStencilState(depthStencilDescriptor);

    renderPipelineDescriptor->release();
    vertexShader->release();
    fragmentShader->release();
}

void MtlEngine::createLightSourceRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("lightVertexShader", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("lightFragmentShader", NS::ASCIIStringEncoding));
    assert(fragmentShader);
    
    MTL::RenderPipelineDescriptor* renderPipelineDescriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    renderPipelineDescriptor->setVertexFunction(vertexShader);
    renderPipelineDescriptor->setFragmentFunction(fragmentShader);
    assert(renderPipelineDescriptor);
    MTL::PixelFormat pixelFormat = (MTL::PixelFormat)metalLayer.pixelFormat;
    renderPipelineDescriptor->colorAttachments()->object(0)->setPixelFormat(pixelFormat);
    renderPipelineDescriptor->setSampleCount(4);
    renderPipelineDescriptor->setLabel(NS::String::string("Light Source Render Pipeline", NS::ASCIIStringEncoding));
    renderPipelineDescriptor->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    renderPipelineDescriptor->setTessellationOutputWindingOrder(MTL::WindingClockwise);
    
    NS::Error* error;
    metalLightSourceRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);
    
    renderPipelineDescriptor->release();
}

void MtlEngine::createDepthAndMSAATextures() {
    MTL::TextureDescriptor* msaaTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    msaaTextureDescriptor->setTextureType(MTL::TextureType2DMultisample);
    msaaTextureDescriptor->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    msaaTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    msaaTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    msaaTextureDescriptor->setSampleCount(sampleCount);
    msaaTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);

    msaaRenderTargetTexture = metalDevice->newTexture(msaaTextureDescriptor);

    MTL::TextureDescriptor* depthTextureDescriptor = MTL::TextureDescriptor::alloc()->init();
    depthTextureDescriptor->setTextureType(MTL::TextureType2DMultisample);
    depthTextureDescriptor->setPixelFormat(MTL::PixelFormatDepth32Float);
    depthTextureDescriptor->setWidth(metalLayer.drawableSize.width);
    depthTextureDescriptor->setHeight(metalLayer.drawableSize.height);
    depthTextureDescriptor->setUsage(MTL::TextureUsageRenderTarget);
    depthTextureDescriptor->setSampleCount(sampleCount);

    depthTexture = metalDevice->newTexture(depthTextureDescriptor);

    msaaTextureDescriptor->release();
    depthTextureDescriptor->release();
}

void MtlEngine::createCube() {
    // Cube for use in a right-handed coordinate system with triangle faces
    // specified with a Counter-Clockwise winding order.
    VertexData cubeVertices[] = {
        // Front face
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, {0.0,0.0,1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, {0.0,0.0,1.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,1.0}},

        // Back face
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,-1.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {0.0,0.0,-1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,-1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,-1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {0.0,0.0,-1.0}},
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,-1.0}},

        // Top face
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},

        // Bottom face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,-1.0,0.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 1.0}, {0.0,-1.0,0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,-1.0,0.0}},

        // Left face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {-1.0,0.0,0.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {-1.0,0.0,0.0}},

        // Right face
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {1.0,0.0,0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {1.0,0.0,0.0}},
    };
        
    cubeVertexBuffer = metalDevice->newBuffer(&cubeVertices, sizeof(cubeVertices), MTL::ResourceStorageModeShared);
    
}

void MtlEngine::createPlane() {
    VertexData planeVertices[] = {
        {{-0.5, 0.0, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.0, 0.5, 1.0}, {1.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.0, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{0.5, 0.0, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.0, -0.5, 1.0}, {0.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.0, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
    };
    
    planeVertexBuffer = metalDevice->newBuffer(&planeVertices, sizeof(planeVertices), MTL::ResourceStorageModeShared);
}

void MtlEngine::createLight() {
    VertexData cubeVertices[] = {
        // Front face
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,1.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, {0.0,0.0,1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,1.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,1.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, {0.0,0.0,1.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,1.0}},
        
        // Back face
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,-1.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {0.0,0.0,-1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,-1.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,0.0,-1.0}},
        {{0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {0.0,0.0,-1.0}},
        {{0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,0.0,-1.0}},
        
        // Top face
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {1.0, 0.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {0.0,1.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
        
        // Bottom face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,-1.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {1.0, 1.0}, {0.0,-1.0,0.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {0.0, 1.0}, {0.0,-1.0,0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {0.0,-1.0,0.0}},
        
        // Left face
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {-1.0,0.0,0.0}},
        {{-0.5, -0.5, 0.5, 1.0}, {1.0, 0.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, 0.5, 1.0}, {1.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, 0.5, -0.5, 1.0}, {0.0, 1.0}, {-1.0,0.0,0.0}},
        {{-0.5, -0.5, -0.5, 1.0}, {0.0, 0.0}, {-1.0,0.0,0.0}},
        
        // Right face
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {1.0,0.0,0.0}},
        {{0.5, -0.5, -0.5, 1.0}, {1.0, 0.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, -0.5, 1.0}, {1.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, 0.5, 0.5, 1.0}, {0.0, 1.0}, {1.0,0.0,0.0}},
        {{0.5, -0.5, 0.5, 1.0}, {0.0, 0.0}, {1.0,0.0,0.0}},
    };
        
    lightVertexBuffer = metalDevice->newBuffer(&cubeVertices, sizeof(cubeVertices), MTL::ResourceStorageModeShared);
}

void MtlEngine::createTriangle() {
    simd::float3 triangleVertices[] = {
            {-0.5f, -0.5f, 0.0f},
            { 0.5f, -0.5f, 0.0f},
            { 0.0f,  0.5f, 0.0f}
        };
    
    triangleVertexBuffer = metalDevice->newBuffer(&triangleVertices, sizeof(triangleVertices), MTL::ResourceStorageModeShared);
}

void MtlEngine::createSquare() {
    VertexData squareVertices[] = {
        {{-0.5, -0.5,  0.5, 1.0f}, {0.0f, 0.0f}},
        {{-0.5,  0.5,  0.5, 1.0f}, {0.0f, 1.0f}},
        {{ 0.5,  0.5,  0.5, 1.0f}, {1.0f, 1.0f}},
        {{-0.5, -0.5,  0.5, 1.0f}, {0.0f, 0.0f}},
        {{ 0.5,  0.5,  0.5, 1.0f}, {1.0f, 1.0f}},
        {{ 0.5, -0.5,  0.5, 1.0f}, {1.0f, 0.0f}}
    };
    
    squareVertexBuffer = metalDevice->newBuffer(&squareVertices, sizeof(squareVertices), MTL::ResourceStorageModeShared);
}

void MtlEngine::createRenderPassDescriptor() {
    renderPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();

    MTL::RenderPassColorAttachmentDescriptor* colorAttachment = renderPassDescriptor->colorAttachments()->object(0);
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = renderPassDescriptor->depthAttachment();

    colorAttachment->setTexture(msaaRenderTargetTexture);
    colorAttachment->setResolveTexture(metalDrawable->texture());
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setClearColor(MTL::ClearColor(41.0f/255.0f, 42.0f/255.0f, 48.0f/255.0f, 1.0));
    colorAttachment->setStoreAction(MTL::StoreActionMultisampleResolve);

    depthAttachment->setTexture(depthTexture);
    depthAttachment->setLoadAction(MTL::LoadActionClear);
    depthAttachment->setStoreAction(MTL::StoreActionDontCare);
    depthAttachment->setClearDepth(1.0);
}

void MtlEngine::updateRenderPassDescriptor() {
    renderPassDescriptor->colorAttachments()->object(0)->setTexture(msaaRenderTargetTexture);
    renderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(metalDrawable->texture());
    renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
}


void MtlEngine::initDevice() {
    metalDevice = MTL::CreateSystemDefaultDevice();
}

void MtlEngine::mouseCallback(GLFWwindow* window, double xpos, double ypos) {
    MtlEngine* engine = (MtlEngine*)glfwGetWindowUserPointer(window);
    
    static bool firstMouse = true;
    static float lastX = 400, lastY = 300;
    
    if (firstMouse) {
        lastX = xpos;
        lastY = ypos;
        firstMouse = false;
    }
    
    float xoffset = xpos - lastX;
    float yoffset = lastY - ypos; // Reversed since y-coordinates go from bottom to top
    
    lastX = xpos;
    lastY = ypos;
    
    // Only process camera movement if shift is held down
    if (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) != GLFW_PRESS &&
        glfwGetKey(window, GLFW_KEY_RIGHT_SHIFT) != GLFW_PRESS) {
        return;
    }
    
    engine->camera->processMouseMovement(xoffset, yoffset);
}

void MtlEngine::scrollCallback(GLFWwindow* window, double xoffset, double yoffset) {
    MtlEngine* engine = (MtlEngine*)glfwGetWindowUserPointer(window);
    engine->camera->processMouseScroll(yoffset);
}

/**
 Because this is static, we can't directly change the size of the frame buffer inside the function. However, we can use glfwGetWindowUserPointer to get the MtlEngine instance we stored, and adjust the frame size using that reference.
 */
void MtlEngine::frameBufferSizeCallback(GLFWwindow *window, int width, int height) {
    MtlEngine* engine = (MtlEngine*)glfwGetWindowUserPointer(window);
    engine->resizeFrameBuffer(width, height);
}

void MtlEngine::resizeFrameBuffer(int width, int height) {
    metalLayer.drawableSize = CGSizeMake(width, height);
    // Deallocate the textures if they have been created
    if (msaaRenderTargetTexture) {
        msaaRenderTargetTexture->release();
        msaaRenderTargetTexture = nullptr;
    }
    if (depthTexture) {
        depthTexture->release();
        depthTexture = nullptr;
    }
    createDepthAndMSAATextures();
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
    updateRenderPassDescriptor();
}

void MtlEngine::initWindow() {
    if (!glfwGetCurrentContext()) {
            glfwInit();
        }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);   //Disabling context creation by setting the value of the first argument to the value of the second. Basically saying no to OpenGL context
    glfwWindow = glfwCreateWindow(800, 600, "Metal Engine", NULL, NULL);
    if (!glfwWindow){
        glfwTerminate();
        exit(EXIT_FAILURE);
    }
    
    int width, height;
    glfwGetFramebufferSize(glfwWindow, &width, &height);
    
    glfwSetWindowUserPointer(glfwWindow, this); // Storing our MtlEngine instance in the glfwWindow
    glfwSetFramebufferSizeCallback(glfwWindow, frameBufferSizeCallback);
    
    glfwSetCursorPosCallback(glfwWindow, mouseCallback);
    glfwSetScrollCallback(glfwWindow, scrollCallback);
    
    // Capture mouse cursor
    glfwSetInputMode(glfwWindow, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    
    metalWindow = glfwGetCocoaWindow(glfwWindow);
    metalLayer = [CAMetalLayer layer];
    metalLayer.device = (__bridge id<MTLDevice>)metalDevice;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.drawableSize = CGSizeMake(width, height);
    metalWindow.contentView.layer = metalLayer; // Whatever is in the metalLayer will be rendered to the cocoa window's content view. Essentially, the metal layer acts as a frame buffer
    metalWindow.contentView.wantsLayer = YES;
    
    metalDrawable = (__bridge CA::MetalDrawable*)[metalLayer nextDrawable];
}
