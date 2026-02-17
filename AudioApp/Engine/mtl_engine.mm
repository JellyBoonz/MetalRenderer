#include "mtl_engine.hpp"
#include "../../external/imgui/imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_metal.h"

// Audio function declarations
bool initAudioCapture();
void shutdownAudioCapture();

// MARK: - Lifecycle

void MtlEngine::init() {
    initDevice();
    initWindow();


    camera = new Camera();
    
    createCube();
    createLight(); // Light cube
    createPlane();
    createBuffers();
    createDefaultLibrary();
    createCommandQueue();
    createBlinnPhongRenderPipeline();
    createBPNoShadowRenderPipeline();
    createLightSourceRenderPipeline();
    createDepthAndMSAATextures();
    createRenderPassDescriptor();
    
    createShadowCommandQueue();
    createShadowMapTexture();
    createShadowMapSampler();
    createShadowPassDescriptor();
    createShadowPipeline();
    
    if(!initAudioInputLayer()) {
        std::cout << "Audio failed to start" << "\n";
    }
    
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
    
    _audioInputLayer.stop();
    
    // Clean up Metal resources
    transformationBuffer->release();
    lightTransformationBuffer->release();
    shadowTransformBuffer->release();
    msaaRenderTargetTexture->release();
    shadowMapTexture->release();
    depthTexture->release();
    renderPassDescriptor->release();
    metalDevice->release();
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
}

MTL::Device* MtlEngine::getDevice() {
    return metalDevice;
}

// MARK: - Initialization

void MtlEngine::initDevice() {
    metalDevice = MTL::CreateSystemDefaultDevice();
}

void MtlEngine::initWindow() {
    if (!glfwGetCurrentContext()) {
            glfwInit();
        }
    // Disabling context creation by setting the value of the first argument to the
    // value of the second. Basically saying no to OpenGL context
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
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

// MARK: - Input Callbacks

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

bool MtlEngine::initAudioInputLayer() {
    return _audioInputLayer.start([this](AVAudioPCMBuffer* buffer, AVAudioTime* when) {
        _audioAnalyzer.processBuffer(buffer, when);
    });
}

// MARK: - Geometry Creation

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
        {{-1.5, 0.0, 1.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
        {{1.5, 0.0, 1.5, 1.0}, {1.0, 0.0}, {0.0,1.0,0.0}},
        {{1.5, 0.0, -1.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{1.5, 0.0, -1.5, 1.0}, {1.0, 1.0}, {0.0,1.0,0.0}},
        {{-1.5, 0.0, -1.5, 1.0}, {0.0, 1.0}, {0.0,1.0,0.0}},
        {{-1.5, 0.0, 1.5, 1.0}, {0.0, 0.0}, {0.0,1.0,0.0}},
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
        {{-0.5, -0.5,  0.5, 1.0f}, {0.0, 0.0}},
        {{-0.5,  0.5,  0.5, 1.0f}, {0.0, 1.0}},
        {{ 0.5,  0.5,  0.5, 1.0f}, {1.0, 1.0}},
        {{-0.5, -0.5,  0.5, 1.0f}, {0.0, 0.0}},
        {{ 0.5,  0.5,  0.5, 1.0f}, {1.0, 1.0}},
        {{ 0.5, -0.5,  0.5, 1.0f}, {1.0, 0.0}}
    };
    
    squareVertexBuffer = metalDevice->newBuffer(&squareVertices, sizeof(squareVertices), MTL::ResourceStorageModeShared);
}

// MARK: - Resource Creation - Buffers

void MtlEngine::createBuffers() {
    transformationBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    lightTransformationBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    shadowTransformBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    planeTransformBuffer = metalDevice->newBuffer(sizeof(TransformationData), MTL::ResourceStorageModeShared);
    lightingBuffer = metalDevice->newBuffer(sizeof(LightingData), MTL::ResourceStorageModeShared);
}


// MARK: - Resource Creation - Command Queues

/**
 The command queue is responsible for creating command buffers, which are chunks of work sent to the GPU from the command queue. These commands are executed via shader code.
 */
void MtlEngine::createCommandQueue() {
    metalCommandQueue = metalDevice->newCommandQueue();
}

void MtlEngine::createShadowCommandQueue() {
    shadowCommandQueue = metalDevice->newCommandQueue();
}

// MARK: - Resource Creation - Pipelines

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

    if (blinnPhongRenderPSO == nil) {
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

void MtlEngine::createBPNoShadowRenderPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("vertexBP", NS::ASCIIStringEncoding));
    assert(vertexShader);
    MTL::Function* fragmentShader = metalDefaultLibrary->newFunction(NS::String::string("fragmentBP_NoShadow", NS::ASCIIStringEncoding));
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
    blinnPhongNoShadowRenderPSO = metalDevice->newRenderPipelineState(renderPipelineDescriptor, &error);

    if (blinnPhongNoShadowRenderPSO == nil) {
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

void MtlEngine::createShadowPipeline() {
    MTL::Function* vertexShader = metalDefaultLibrary->newFunction(NS::String::string("shadowVertex", NS::ASCIIStringEncoding));
    assert(vertexShader);
    
    MTL::RenderPipelineDescriptor* desc = MTL::RenderPipelineDescriptor::alloc()->init();
    desc->setVertexFunction(vertexShader);
    desc->setDepthAttachmentPixelFormat(MTL::PixelFormatDepth32Float);
    desc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatInvalid); // No color
    desc->setLabel(NS::String::string("Shadow Render Pipeline", NS::ASCIIStringEncoding));
    
    NS::Error* error;
    shadowRenderPSO = metalDevice->newRenderPipelineState(desc, &error);
    desc->release();
    vertexShader->release();
}

// MARK: - Resource Creation - Textures & Samplers

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

void MtlEngine::createShadowMapTexture(){
    MTL::TextureDescriptor* shadowDesc = MTL::TextureDescriptor::alloc()->init();
    shadowDesc->setTextureType(MTL::TextureType2D);
    shadowDesc->setPixelFormat(MTL::PixelFormatDepth32Float);
    shadowDesc->setWidth(1024);  // Shadow map resolution
    shadowDesc->setHeight(1024);
    shadowDesc->setStorageMode(MTL::StorageModePrivate);
    shadowDesc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    
    shadowMapTexture = metalDevice->newTexture(shadowDesc);
    shadowDesc->release();
}

void MtlEngine::createShadowMapSampler(){
    MTL::SamplerDescriptor* desc = MTL::SamplerDescriptor::alloc()->init();
    
    desc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    desc->setMagFilter(MTL::SamplerMinMagFilterLinear);
    desc->setSAddressMode(MTL::SamplerAddressModeRepeat);
    desc->setTAddressMode(MTL::SamplerAddressModeRepeat);
    
    shadowSampler = metalDevice->newSamplerState(desc);
    desc->release();
}

// MARK: - Resource Creation - Render Pass Descriptors

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

void MtlEngine::createShadowPassDescriptor() {
    shadowPassDescriptor = MTL::RenderPassDescriptor::alloc()->init();
    MTL::RenderPassDepthAttachmentDescriptor* depthAttachment = shadowPassDescriptor->depthAttachment();
    depthAttachment->setTexture(shadowMapTexture);
    depthAttachment->setLoadAction(MTL::LoadActionClear); // clear the previous pixel values before the pass
    depthAttachment->setStoreAction(MTL::StoreActionStore); // save the rendered output to the texture
    depthAttachment->setClearDepth(1.0); // setting depth for all pixel values
    
    // Tell Metal the size of the render area for depth-only pass
    shadowPassDescriptor->setRenderTargetWidth(shadowMapTexture->width());
    shadowPassDescriptor->setRenderTargetHeight(shadowMapTexture->height());
}

// MARK: - Per-Frame Updates

void MtlEngine::updateRenderPassDescriptor() {
    renderPassDescriptor->colorAttachments()->object(0)->setTexture(msaaRenderTargetTexture);
    renderPassDescriptor->colorAttachments()->object(0)->setResolveTexture(metalDrawable->texture());
    renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
}

void MtlEngine::updateSharedTransformData() {
    float near_plane = 0.1f, far_plane = 15.0f;
    matrix_float4x4 lightProj = matrix_ortho_right_hand(-8.0f, 8.0f, -8.0f, 8.0f, near_plane, far_plane);
    
    // Use ImGui controlled cube position
    matrix_float4x4 modelMatrix = matrix4x4_translation(cubePosition.x, cubePosition.y, cubePosition.z);
    
    
    // Use ImGui controlled light position
    matrix_float4x4 lightModelMatrix = matrix4x4_translation(lightPosition.x, lightPosition.y, lightPosition.z);
    matrix_float4x4 viewMatrix = camera->getViewMatrix();
    matrix_float4x4 planeModelMatrix = matrix4x4_translation(0, -1.0f, 0); // Slightly below origin
    planeModelMatrix = matrix_multiply(planeModelMatrix, matrix4x4_scale(10.0f, 1.0f, 10.0f)); // Big floor
    
    float aspectRatio = (metalLayer.frame.size.width / metalLayer.frame.size.height);
    camera->aspectRatio = aspectRatio;
    float fov = camera->fov * (M_PI / 180.0f);
    matrix_float4x4 projectionMatrix = matrix_perspective_right_hand(fov, aspectRatio, camera->nearPlane, camera->farPlane);

    TransformationData tMain = {modelMatrix, viewMatrix, projectionMatrix};
    memcpy(transformationBuffer->contents(), &tMain, sizeof(tMain));

    // Extract light position from model matrix
    simd::float3 lightPos = lightPosition;

    // The light should look at where your main cube is
    simd::float3 mainCubePos = cubePosition;
    simd::float3 forward = simd_normalize(mainCubePos - lightPos);
    
    // Choose a consistent up vector based on which axis has the least influence
    simd::float3 absForward = {abs(forward.x), abs(forward.y), abs(forward.z)};
    simd::float3 worldUp;
    
    if (absForward.y < absForward.x && absForward.y < absForward.z) {
        worldUp = {0.0, 1.0, 0.0}; // Y is smallest, use Y up
    } else if (absForward.x < absForward.z) {
        worldUp = {1.0, 0.0, 0.0}; // X is smallest, use X up
    } else {
        worldUp = {0.0, 0.0, 1.0}; // Z is smallest, use Z up
    }
    
    simd::float3 right = simd_normalize(simd_cross(forward, worldUp));
    simd::float3 up = simd_cross(right, forward);

    matrix_float4x4 lightView = matrix_look_at_right_hand(lightPos, mainCubePos, up);
    
    TransformationData tLight = {
        lightModelMatrix,  // model (you can use identity or place light model here)
        lightView,
        lightProj
    };
    memcpy(shadowTransformBuffer->contents(), &tLight, sizeof(tLight));
    
    TransformationData lightCubeT = {
        lightModelMatrix,
        viewMatrix,                // from camera
        projectionMatrix           // from camera
    };
    memcpy(lightTransformationBuffer->contents(), &lightCubeT, sizeof(lightCubeT));
    
    TransformationData planeTransform = {
        planeModelMatrix,
        viewMatrix,
        projectionMatrix
    };
    memcpy(planeTransformBuffer->contents(), &planeTransform, sizeof(planeTransform));

    LightingData lightingData;
    lightingData.cameraPos = camera->getPosition();
    lightingData.lightPos = lightPosition;
    
    BandEnergies bands = _audioAnalyzer.getBandEnergies();
    // Compensate for spectral tilt (treble/mid boost) and balance (bass boost)
    constexpr float kBassBoost = 5.0f;
    constexpr float kMidBoost = .8f;
    constexpr float kTrebleBoost = 1.0f;
    float bass = std::sqrt(std::max(0.0f, bands.bass * kBassBoost));
    float mid = std::sqrt(std::max(0.0f, bands.mid * kMidBoost));
    float treble = std::sqrt(std::max(0.0f, bands.treble * kTrebleBoost));
    float total = bass + mid + treble;
    float r = 0.0f, g = 0.0f, b = 0.0f;
    if (total > 1e-6f) {
        r = treble / total;
        g = mid / total;
        b = bass / total;
    } else {
        r = g = b = 1.0f / 3.0f;
    }
    constexpr float kBrightnessScale = 15.0f;
    constexpr float kBrightnessFloor = 0.08f;
    constexpr float kDecayFactor = 0.96f;  // per-frame decay; lower = faster trail-off
    float rawBrightness = total > 0.0f ? std::min(1.0f, total * kBrightnessScale) : 0.0f;
    _brightnessEnvelope = std::max(rawBrightness, _brightnessEnvelope * kDecayFactor);
    float brightness = std::max(kBrightnessFloor, _brightnessEnvelope);
    lightColor = {r * brightness, g * brightness, b * brightness};
    
    lightingData.lightColor = lightColor;
    lightingData.lightIntensity = brightness;
    lightingData.ambientIntensity = 0.1f;
    lightingData.shininess = 32.0f;
    memcpy(lightingBuffer->contents(), &lightingData, sizeof(lightingData));
}

// MARK: - Draw / Render

void MtlEngine::draw() {
    renderShadowPass();
    sendRenderCommand();
}

void MtlEngine::renderShadowPass() {
    shadowCommandBuffer = shadowCommandQueue->commandBuffer();
    
    MTL::RenderCommandEncoder* shadowEncoder = shadowCommandBuffer->renderCommandEncoder(shadowPassDescriptor);
    
    shadowEncoder->setRenderPipelineState(shadowRenderPSO);
    shadowEncoder->setDepthStencilState(depthStencilState);
    
    shadowEncoder->setVertexBuffer(cubeVertexBuffer, 0, 0);
//    shadowEncoder->setVertexBuffer(planeVertexBuffer, 0, 0);
    shadowEncoder->setVertexBuffer(shadowTransformBuffer, 0, 1); // Use light's transform
    
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 36;
    
    shadowEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);

    shadowEncoder->endEncoding();
    shadowCommandBuffer->commit();
    shadowCommandBuffer->waitUntilCompleted();
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

void MtlEngine::encodeRenderCommand(MTL::RenderCommandEncoder* renderCommandEncoder) {
    updateSharedTransformData();
    
    encodeMainCube(renderCommandEncoder);
    encodeLightCube(renderCommandEncoder);
    encodePlane(renderCommandEncoder);
    
    drawImGui(renderCommandEncoder);
}

void MtlEngine::encodeMainCube(MTL::RenderCommandEncoder *renderCommandEncoder) {
    simd::float3 cubeColor = {1.0f, 0.5f, 0.31f};
    NS::UInteger vertexStart = 0;
    NS::UInteger vertexCount = 36;
    
    // Use the NO-SHADOW pipeline for the cube
    renderCommandEncoder->setRenderPipelineState(blinnPhongNoShadowRenderPSO);
    renderCommandEncoder->setDepthStencilState(depthStencilState);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);
    
    renderCommandEncoder->setVertexBuffer(cubeVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBuffer(transformationBuffer, 0, 1);
    renderCommandEncoder->setVertexBuffer(lightTransformationBuffer, 0, 2);
    // No need to set shadow texture/sampler for no-shadow pipeline
    renderCommandEncoder->setFragmentBuffer(lightingBuffer, 0, 3);
    renderCommandEncoder->setFragmentBytes(&cubeColor, sizeof(cubeColor), 0);
    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);
}

void MtlEngine::encodeLightCube(MTL::RenderCommandEncoder* renderCommandEncoder) {
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
    
    // Use the WITH-SHADOW pipeline for the plane
    renderCommandEncoder->setRenderPipelineState(blinnPhongRenderPSO); // This should use fragmentBP_WithShadow
    renderCommandEncoder->setDepthStencilState(depthStencilState);
    renderCommandEncoder->setFrontFacingWinding(MTL::WindingCounterClockwise);
    renderCommandEncoder->setCullMode(MTL::CullModeBack);

    renderCommandEncoder->setVertexBuffer(planeVertexBuffer, 0, 0);
    renderCommandEncoder->setVertexBuffer(planeTransformBuffer, 0, 1);
    renderCommandEncoder->setVertexBuffer(shadowTransformBuffer, 0, 2);
    renderCommandEncoder->setFragmentTexture(shadowMapTexture, 0);
    renderCommandEncoder->setFragmentSamplerState(shadowSampler, 0);
    renderCommandEncoder->setFragmentBuffer(lightingBuffer, 0, 3);

    simd::float3 color = {0.5f, 0.7f, 0.5f};
    renderCommandEncoder->setFragmentBytes(&color, sizeof(color), 0);

    renderCommandEncoder->drawPrimitives(MTL::PrimitiveTypeTriangle, vertexStart, vertexCount);
}

void MtlEngine::drawImGui(MTL::RenderCommandEncoder *renderCommandEncoder) {
    // Build ImGui UI
    ImGui::Begin("Scene Controls");
    ImGui::SliderFloat3("Light Position", (float*)&lightPosition, -5.0f, 5.0f);
    ImGui::SliderFloat3("Cube Position", (float*)&cubePosition, -5.0f, 5.0f);
    ImGui::ColorEdit3("Light Color", reinterpret_cast<float*>(&lightColor));
    
    ImGui::Separator();
    ImGui::Text("FPS: %.1f", ImGui::GetIO().Framerate);
    
    // Grabbing audio features
    AudioFeatures features = _audioAnalyzer.getFeatures();
    
    float rms = features.rms;
    float avg = features.rollingAvg;
    ImGui::Separator();
    ImGui::Text("Audio RMS: %.4f", rms);
    ImGui::Text("Audio Rolling Avg: %.4f", avg);
    
    const std::vector<float>& spectrum = _audioAnalyzer.getSpectrumMagnitudes();
    if (!spectrum.empty()) {
        ImGui::Separator();
        ImGui::Text("Spectrum (20–4180 Hz)");
        constexpr float kFreqRangeLow = 20.0f;
        constexpr float kFreqRangeHigh = 4180.0f;
        float sampleRate = _audioAnalyzer.getSampleRate();
        int startBin = 0;
        int endBin = (int)spectrum.size() - 1;
        if (sampleRate > 0.0f) {
            startBin = (int)(kFreqRangeLow * (float)kFFTSize / sampleRate);
            endBin = (int)(kFreqRangeHigh * (float)kFFTSize / sampleRate);
            startBin = std::max(1, std::min(startBin, endBin));  // skip DC
            endBin = std::max(startBin, std::min(endBin, (int)spectrum.size() - 1));
        }
        int plotCount = endBin - startBin + 1;
        ImGui::PlotLines("##Spectrum", spectrum.data() + startBin, plotCount,
                        0, nullptr, 0.0f, FLT_MAX, ImVec2(300, 80));
        
        // Display band energies
        ImGui::Separator();
        BandEnergies bands = _audioAnalyzer.getBandEnergies();
        constexpr float kBassBoost = 5.0f;
        constexpr float kMidBoost = .8f;
        constexpr float kTrebleBoost = 3.0f;
        ImGui::Text("Band Energies: Bass %.2f, Mid %.2f, Treble %.2f", bands.bass * kBassBoost, bands.mid * kMidBoost, bands.treble * kTrebleBoost);
    }
    
    ImGui::End();
    
    // Render ImGui
    ImGui::Render();

    // Render ImGui draw data here, after all scene rendering, before endEncoding
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), (__bridge id<MTLCommandBuffer>)metalCommandBuffer, (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder);
}
