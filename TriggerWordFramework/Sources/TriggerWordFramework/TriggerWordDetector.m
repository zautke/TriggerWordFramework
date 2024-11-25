//
//  TriggerWordDetector.m
//  TriggerWordFramework
//
//  Created by Luke Zautke on 6/11/25.
//

#import "TriggerWordDetector.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>


@interface TriggerWordDetector () {
    AudioComponentInstance audioUnit;
}
@end

@implementation TriggerWordDetector

// Forward declaration of callback
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData);

- (void)startListening {
    NSLog(@"TriggerWordDetector: startListening called.");
    // Here you would set up the audio session and install the RenderCallback.
    // For demonstration, assume self->audioUnit is set up elsewhere.
    // AudioUnitSetProperty(self->audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &(AURenderCallbackStruct){ .inputProc = RenderCallback, .inputProcRefCon = (__bridge void *)self }, sizeof(AURenderCallbackStruct));
}

- (void)stopListening {
    NSLog(@"TriggerWordDetector: stopListening called.");
    // Here you would remove or disable the RenderCallback.
}

- (void)reset {
    NSLog(@"TriggerWordDetector: reset called.");
    // Reset any state as needed.
}

// Amplitude-based state machine RenderCallback for "brazen" detection
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData) {
    TriggerWordDetector *self = (__bridge TriggerWordDetector *)inRefCon;

    static enum { SILENT, PEAK1, DIP, PEAK2 } state = SILENT;
    static Float32 peak1Time = 0, dipTime = 0;
    static const Float32 thresholdHigh = 0.15f;
    static const Float32 thresholdLow  = 0.05f;
    static const Float32 sampleRate = 16000.0f;

    static Float32 timeInSeconds = 0;

    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames * sizeof(Float32);
    bufferList.mBuffers[0].mNumberChannels = 1;
    bufferList.mBuffers[0].mData = malloc(bufferList.mBuffers[0].mDataByteSize);

    OSStatus status = AudioUnitRender(self->audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
    if (status != noErr) {
        NSLog(@"AudioUnitRender error: %d", (int)status);
        free(bufferList.mBuffers[0].mData);
        return status;
    }

    Float32 *samples = (Float32 *)bufferList.mBuffers[0].mData;
    Float32 maxAmplitude = 0.0f;
    for (UInt32 i = 0; i < inNumberFrames; i++) {
        Float32 absSample = fabsf(samples[i]);
        if (absSample > maxAmplitude) maxAmplitude = absSample;
    }

    timeInSeconds += inNumberFrames / sampleRate;

    switch (state) {
        case SILENT:
            if (maxAmplitude > thresholdHigh) {
                peak1Time = timeInSeconds;
                state = PEAK1;
                NSLog(@"[Trigger] PEAK 1 detected at %.2f", timeInSeconds);
            }
            break;
        case PEAK1:
            if (maxAmplitude < thresholdLow) {
                dipTime = timeInSeconds;
                state = DIP;
                NSLog(@"[Trigger] DIP after PEAK 1 at %.2f", timeInSeconds);
            }
            break;
        case DIP:
            if (maxAmplitude > thresholdHigh) {
                Float32 peakSpacing = timeInSeconds - peak1Time;
                if (peakSpacing >= 0.2f && peakSpacing <= 1.0f) {
                    NSLog(@"[Trigger] PEAK 2 detected at %.2f (interval: %.2fs) — MATCH", timeInSeconds, peakSpacing);
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"TriggerWordDetected" object:nil];
                    state = SILENT;
                    peak1Time = dipTime = 0;
                } else {
                    NSLog(@"[Trigger] PEAK 2 too late (%.2fs), resetting", peakSpacing);
                    state = SILENT;
                }
            }
            break;
        case PEAK2:
        default:
            state = SILENT;
            break;
    }

    free(bufferList.mBuffers[0].mData);
    return noErr;
}

@end
