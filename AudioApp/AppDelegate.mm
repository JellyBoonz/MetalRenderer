#import "AppDelegate.h"
#import "mtl_engine.hpp"

// These are already defined in mtl_engine.mm and AudioInputMinimal.mm
extern "C" bool audioInputMinimal_start(void);
extern "C" void audioInputMinimal_stop(void);

@interface AppDelegate ()
@end

@implementation AppDelegate {
    MtlEngine *engine;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Start audio (optional if MtlEngine::init already calls it; keep behavior consistent with CLI)
    if (!audioInputMinimal_start()) {
        NSLog(@"AudioApp: audioInputMinimal_start failed");
    }

    // Create and run the same engine used by the CLI main()
    engine = new MtlEngine();
    engine->init();
    engine->run();       // This enters your existing GLFW + ImGui loop
    engine->cleanup();

    audioInputMinimal_stop();

    // When the GLFW window is closed, quit the app
    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Just in case we terminate early
    if (engine) {
        engine->cleanup();
        delete engine;
        engine = nullptr;
    }
    audioInputMinimal_stop();
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

@end
