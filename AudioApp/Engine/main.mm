//
//  main.cpp
//  Metal-Guide
//

#include "mtl_engine.hpp"
#include "AudioInputLayer.hpp"

int main(int argc, const char * argv[]) {
    
    MtlEngine engine;
    
    engine.init();
    engine.run();
    engine.cleanup();

    return 0;
}
