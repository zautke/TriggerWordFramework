//
//  TriggerWordDetector.m
//  TriggerWordFramework
//
//  Created by Luke Zautke on 6/11/25.
//

#import "TriggerWordDetector.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface TriggerWordDetector ()
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, assign) AudioComponentInstance audioUnit;
@property (nonatomic, assign) BOOL isListening;
@end

@implementation TriggerWordDetector

// Forward declaration of callback
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData);

- (instancetype)init {
    self = [super init];
    if (self) {
        self.isListening = NO;
        [self setupAudioSession];
    }
    return self;
}

- (void)dealloc {
    [self stopListening];
}

- (void)setupAudioSession {
    self.audioSession = [AVAudioSession sharedInstance];
    NSError *error;
    
    // Set category for background recording with minimal battery impact
    BOOL success = [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                                       withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                                                  AVAudioSessionCategoryOptionDefaultToSpeaker |
                                                  AVAudioSessionCategoryOptionAllowBluetooth
                                             error:&error];
    
    if (!success || error) {
        NSLog(@"Audio session category error: %@", error.localizedDescription);
    }
    
    // Set preferred sample rate for battery efficiency
    [self.audioSession setPreferredSampleRate:16000.0 error:&error];
    if (error) {
        NSLog(@"Sample rate setting error: %@", error.localizedDescription);
    }
}

- (void)startListening {
    NSLog(@"TriggerWordDetector: startListening called.");
    
    if (self.isListening) {
        NSLog(@"Already listening, ignoring start request");
        return;
    }
    
    // Check current permission state
    AVAudioSessionRecordPermission permission = [self.audioSession recordPermission];
    
    switch (permission) {
        case AVAudioSessionRecordPermissionGranted:
            [self setupAudioUnit];
            break;
            
        case AVAudioSessionRecordPermissionDenied:
            NSLog(@"Microphone permission denied");
            break;
            
        case AVAudioSessionRecordPermissionUndetermined:
            // Request permission first time
            [self.audioSession requestRecordPermission:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) {
                        [self setupAudioUnit];
                    } else {
                        NSLog(@"Microphone permission denied by user");
                    }
                });
            }];
            break;
    }
}

- (void)setupAudioUnit {
    NSError *error;
    
    // Activate audio session
    BOOL success = [self.audioSession setActive:YES error:&error];
    if (!success || error) {
        NSLog(@"Audio session activation error: %@", error.localizedDescription);
        return;
    }
    
    // Setup Audio Unit for input
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    if (!component) {
        NSLog(@"Failed to find RemoteIO component");
        return;
    }
    
    OSStatus status = AudioComponentInstanceNew(component, &_audioUnit);
    if (status != noErr) {
        NSLog(@"AudioComponentInstanceNew error: %d", (int)status);
        return;
    }
    
    // Enable input on the input scope of the input element
    UInt32 enableInput = 1;
    status = AudioUnitSetProperty(_audioUnit,
                                 kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Input,
                                 1, // input element
                                 &enableInput,
                                 sizeof(enableInput));
    
    if (status != noErr) {
        NSLog(@"Failed to enable input: %d", (int)status);
        [self cleanupAudioUnit];
        return;
    }
    
    // Disable output on the output scope of the output element
    UInt32 disableOutput = 0;
    status = AudioUnitSetProperty(_audioUnit,
                                 kAudioOutputUnitProperty_EnableIO,
                                 kAudioUnitScope_Output,
                                 0, // output element
                                 &disableOutput,
                                 sizeof(disableOutput));
    
    // Set audio format for battery efficiency
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = 16000.0;  // Lower sample rate for battery savings
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mChannelsPerFrame = 1;  // Mono for efficiency
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerFrame = 2;
    audioFormat.mBytesPerPacket = 2;
    
    status = AudioUnitSetProperty(_audioUnit,
                                 kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Output,
                                 1, // input element
                                 &audioFormat,
                                 sizeof(audioFormat));
    
    if (status != noErr) {
        NSLog(@"Failed to set audio format: %d", (int)status);
        [self cleanupAudioUnit];
        return;
    }
    
    // Set render callback
    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = RenderCallback;
    renderCallback.inputProcRefCon = (__bridge void *)self;
    
    status = AudioUnitSetProperty(_audioUnit,
                                 kAudioOutputUnitProperty_SetInputCallback,
                                 kAudioUnitScope_Global,
                                 1,
                                 &renderCallback,
                                 sizeof(renderCallback));
    
    if (status != noErr) {
        NSLog(@"Failed to set render callback: %d", (int)status);
        [self cleanupAudioUnit];
        return;
    }
    
    // Initialize and start the audio unit
    status = AudioUnitInitialize(_audioUnit);
    if (status != noErr) {
        NSLog(@"AudioUnitInitialize error: %d", (int)status);
        [self cleanupAudioUnit];
        return;
    }
    
    status = AudioOutputUnitStart(_audioUnit);
    if (status != noErr) {
        NSLog(@"AudioOutputUnitStart error: %d", (int)status);
        AudioUnitUninitialize(_audioUnit);
        [self cleanupAudioUnit];
        return;
    }
    
    self.isListening = YES;
    NSLog(@"TriggerWordDetector: Audio unit started successfully, now listening");
}

- (void)stopListening {
    NSLog(@"TriggerWordDetector: stopListening called.");
    
    if (!self.isListening) {
        return;
    }
    
    if (_audioUnit) {
        AudioOutputUnitStop(_audioUnit);
        AudioUnitUninitialize(_audioUnit);
        [self cleanupAudioUnit];
    }
    
    self.isListening = NO;
    
    // Deactivate audio session to save battery
    NSError *error;
    [self.audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        NSLog(@"Audio session deactivation error: %@", error.localizedDescription);
    }
    
    NSLog(@"TriggerWordDetector: Stopped listening");
}

- (void)cleanupAudioUnit {
    if (_audioUnit) {
        AudioComponentInstanceDispose(_audioUnit);
        _audioUnit = NULL;
    }
}

- (void)reset {
    NSLog(@"TriggerWordDetector: reset called.");
    BOOL wasListening = self.isListening;
    
    [self stopListening];
    
    // Reset detection state
    static enum { SILENT, PEAK1, DIP, PEAK2 } state = SILENT;
    state = SILENT;
    
    if (wasListening) {
        // Restart after brief delay to avoid rapid cycling
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startListening];
        });
    }
}

// Battery-optimized amplitude-based state machine RenderCallback for "brazen" detection
static OSStatus RenderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData) {
    
    TriggerWordDetector *self = (__bridge TriggerWordDetector *)inRefCon;
    
    // Create buffer for input
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mDataByteSize = inNumberFrames * sizeof(SInt16);
    bufferList.mBuffers[0].mNumberChannels = 1;
    bufferList.mBuffers[0].mData = malloc(bufferList.mBuffers[0].mDataByteSize);
    
    if (!bufferList.mBuffers[0].mData) {
        NSLog(@"Failed to allocate audio buffer");
        return -1;
    }
    
    OSStatus status = AudioUnitRender(self->_audioUnit,
                                     ioActionFlags,
                                     inTimeStamp,
                                     inBusNumber,
                                     inNumberFrames,
                                     &bufferList);
    
    if (status != noErr) {
        NSLog(@"AudioUnitRender error: %d", (int)status);
        free(bufferList.mBuffers[0].mData);
        return status;
    }
    
    // Process amplitude-based trigger detection optimized for "brazen" (BRAY-zen)
    static enum { SILENT, PEAK1, DIP, PEAK2 } state = SILENT;
    static CFAbsoluteTime peak1Time = 0, dipTime = 0;
    
    // Optimized thresholds for "brazen" detection
    static const Float32 thresholdHigh = 0.12f;     // BRAY peak threshold
    static const Float32 thresholdLow = 0.04f;      // Dip threshold between syllables
    static const Float32 thresholdPeak2 = 0.08f;    // "zen" peak (softer than "BRAY")
    static const Float32 sampleRate = 16000.0f;
    
    // Timing optimized for "brazen" pronunciation (~0.5-0.7 seconds total)
    static const Float32 minPeakSpacing = 0.15f;    // Minimum time between BRAY and zen
    static const Float32 maxPeakSpacing = 0.6f;     // Maximum time between BRAY and zen
    static const Float32 dipMinDuration = 0.05f;    // Minimum dip duration
    static const Float32 stateTimeout = 1.5f;       // Timeout for any state
    
    // Convert to float and find max amplitude efficiently
    SInt16 *samples = (SInt16 *)bufferList.mBuffers[0].mData;
    Float32 maxAmplitude = 0.0f;
    
    // Optimized amplitude detection - process every 4th sample for efficiency
    for (UInt32 i = 0; i < inNumberFrames; i += 4) {
        Float32 sample = (Float32)samples[i] / 32767.0f; // Normalize to [-1, 1]
        Float32 absSample = fabsf(sample);
        if (absSample > maxAmplitude) {
            maxAmplitude = absSample;
        }
    }
    
    CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
    
    switch (state) {
        case SILENT:
            if (maxAmplitude > thresholdHigh) {
                peak1Time = currentTime;
                state = PEAK1;
                NSLog(@"[Brazen] BRAY detected at %.2f (amp: %.3f)", currentTime, maxAmplitude);
            }
            break;
            
        case PEAK1:
            if (maxAmplitude < thresholdLow) {
                dipTime = currentTime;
                state = DIP;
                NSLog(@"[Brazen] Dip after BRAY at %.2f", currentTime);
            } else if (currentTime - peak1Time > stateTimeout) {
                // Timeout, reset
                state = SILENT;
                NSLog(@"[Brazen] BRAY timeout, resetting");
            }
            break;
            
        case DIP:
            // Check for "zen" syllable with lower threshold
            if (maxAmplitude > thresholdPeak2) {
                Float32 peakSpacing = currentTime - peak1Time;
                Float32 dipDuration = currentTime - dipTime;
                
                // Validate timing for "brazen" pronunciation
                if (peakSpacing >= minPeakSpacing && peakSpacing <= maxPeakSpacing &&
                    dipDuration >= dipMinDuration) {
                    NSLog(@"[Brazen] 'BRAZEN' DETECTED! Total duration: %.2fs, zen amplitude: %.3f",
                          peakSpacing, maxAmplitude);
                    
                    // Post notification on main queue for thread safety
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter]
                         postNotificationName:@"TriggerWordDetected"
                                       object:nil
                                     userInfo:@{@"word": @"brazen",
                                               @"brazAmplitude": @(maxAmplitude),
                                               @"zenAmplitude": @(maxAmplitude),
                                               @"duration": @(peakSpacing),
                                               @"confidence": @(MIN(1.0, (maxAmplitude / thresholdPeak2)))}];
                    });
                    
                    state = SILENT;
                    peak1Time = dipTime = 0;
                } else {
                    NSLog(@"[Brazen] zen timing invalid - duration: %.2fs, dip: %.2fs, resetting",
                          peakSpacing, dipDuration);
                    state = SILENT;
                }
            } else if (currentTime - dipTime > stateTimeout) {
                // Timeout waiting for "zen"
                state = SILENT;
                NSLog(@"[Brazen] Timeout waiting for 'zen', resetting");
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
