#import "AppDelegate.h"
#import "mtl_engine.hpp"

@interface AppDelegate ()
@end

@implementation AppDelegate {
    MtlEngine *engine;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    engine = new MtlEngine();
    engine->init();
    engine->run();
    engine->cleanup();

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
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

@end
