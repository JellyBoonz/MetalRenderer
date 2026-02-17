// AudioInputMinimal.mm
// Minimal AVAudioEngine capture that computes per-buffer RMS and a rolling average.

#import <AVFoundation/AVFoundation.h>
#include <vector>
#include <mutex>
#include <cmath>

#include "AudioInputLayer.hpp"

bool AudioInputLayer::start(BufferCallback cb) {
    @try {
        callback = cb;
        engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *input = [engine inputNode];
        if (!input) {
            return false;
        }
        
        AVAudioFormat *format = [input inputFormatForBus:0];
        
        [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            if(callback) {
                callback(buffer, when);
            }
        }];
        
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) {
            return false;
        }
        
        return true;
    } @catch (NSException *ex) {
        return false;
    }
}

void AudioInputLayer::stop() {
    if(engine) {
        [[engine inputNode] removeTapOnBus:0];
        [engine stop];
        engine = nil;
    }
    callback = nullptr;
}
