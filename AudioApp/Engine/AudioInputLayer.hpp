#pragma once
#import <AVFoundation/AVFoundation.h>
#include <functional>

class AudioInputLayer {
public:
    using BufferCallback = std::function<void(AVAudioPCMBuffer*, AVAudioTime*)>;
    
    bool start(BufferCallback callback);
    void stop();
    
private:
    AVAudioEngine *engine = nil;
    BufferCallback callback;
};
