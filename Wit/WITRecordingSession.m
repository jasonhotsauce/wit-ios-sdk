//
//  WITRecordingSession.m
//  Wit
//
//  Created by Aric Lasry on 8/14/14.
//  Copyright (c) 2014 Willy Blandin. All rights reserved.
//

#import "WITRecordingSession.h"
#import "WITVadConfig.h"
#import "WITContextSetter.h"

#import <CoreTelephony/CTTelephonyNetworkInfo.h>

#import <GCNetworkReachability/GCNetworkReachability.h>
@interface WITRecordingSession ()

@property WITVadConfig vadEnabled;
@property NSMutableArray *dataBuffer;
@property int buffersToSave;
@end

@implementation WITRecordingSession {
WITContextSetter *wcs;
}

-(id)initWithWitContext:(NSMutableDictionary *)upContext vadEnabled:(WITVadConfig)vadEnabled withWitToken:(NSString *)witToken withDelegate:(id<WITRecordingSessionDelegate>)delegate {
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.dataBuffer = [[NSMutableArray alloc] init];
        self.vadEnabled = vadEnabled;
        
        GCNetworkReachability *reachability = [GCNetworkReachability reachabilityForInternetConnection];
        
        if ([reachability isReachable])
        {
            // do stuff that requires an internet connection…
        }
        
        CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
        NSString *connectionType = networkInfo.currentRadioAccessTechnology;
        BOOL fastConnection = YES;
        switch ([reachability currentReachabilityStatus]) {
            case GCNetworkReachabilityStatusWWAN:
                // e.g. download smaller file sized images...
                
                if ([connectionType isEqualToString:CTRadioAccessTechnologyGPRS] || [connectionType isEqualToString:CTRadioAccessTechnologyWCDMA] || [connectionType isEqualToString:CTRadioAccessTechnologyEdge] || [connectionType isEqualToString:CTRadioAccessTechnologyCDMA1x] || [connectionType isEqualToString:CTRadioAccessTechnologyHSUPA] || [connectionType isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]  || [connectionType isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]  || [connectionType isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]) {
                    fastConnection = NO;
                }
                
                if (fastConnection) {
                    self.uploader = [[WITUploader alloc] initWithAudioFormat:kAudioFormatLinearPCM];
                    self.recorder = [[WITRecorder alloc] initWithAudioFormat:kAudioFormatLinearPCM];
                    
                    NSLog(@"Got FAST GSM connection");
                } else {
                    self.uploader = [[WITUploader alloc] initWithAudioFormat:kAudioFormatULaw];
                    self.recorder = [[WITRecorder alloc] initWithAudioFormat:kAudioFormatULaw];
                    NSLog(@"Got SLOW GSM connection");
                }

                break;
            default:
                    self.uploader = [[WITUploader alloc] initWithAudioFormat:kAudioFormatLinearPCM];
                    self.recorder = [[WITRecorder alloc] initWithAudioFormat:kAudioFormatLinearPCM];
                NSLog(@"Got FAST default connection");
                break;
        }

        self.uploader.delegate = self;
        self.isUploading = false;
        self.context = upContext;
        self.recorder.delegate = self;
        [self.recorder start];
        self.witToken = witToken;
        self.buffersToSave = 25; //hardcode for now
        if (vadEnabled == WITVadConfigDisabled) {
            [self startUploader];
        } else  {
            [self.recorder enabledVad];
            if (vadEnabled == WITVadConfigDetectSpeechStop) {
                [self startUploader];
            } else if (vadEnabled == WITVadConfigFull) {
                
            }
        }
    }
    
    return self;
}

-(void)startUploader
{
    [[Wit sharedInstance].wcs contextFillup:self.context];
    [self.uploader startRequestWithContext:self.context];
    self.isUploading = true;
    [self.delegate recordingSessionDidStartRecording];
}

-(void)stop
{
        [self.recorder stop];
        [self.uploader endRequest];
        self.isUploading = false;
        [self.delegate recordingSessionDidStopRecording];

}

- (BOOL)isRecording {
    return [self.recorder isRecording];
}

-(void)gotResponse:(NSDictionary*)resp error:(NSError*)err {

    [self.delegate recordingSessionGotResponse:resp customData:self.customData error:err];
    
    if (err) {
        NSLog(@"Wit stopped recording because of a (network?) error");
        [self stop];
    }
    [self clean];
}



#pragma mark - WITRecorderDelegate implementation

-(void)recorderGotChunk:(NSData*)chunk {
    dispatch_async(dispatch_get_main_queue(), ^{
    if(self.isUploading) {
        [self.uploader sendChunk:chunk];
    } else {
        //not uploading, so save the chunk to the buffer and remove old chunk
        if ([self.dataBuffer count] >= self.buffersToSave){
            //if we have enough entries, remove the oldest one
            [self.dataBuffer removeObjectAtIndex:0];
        }
        //enqueue the new data
        [self.dataBuffer addObject:chunk];
    }
        [self.delegate recordingSessionRecorderGotChunk:chunk];
    });
}

-(void)recorderDetectedSpeech {
    [self.delegate recordingSessionDidDetectSpeech];
    
    if (self.vadEnabled == WITVadConfigFull) {
        dispatch_async(dispatch_get_main_queue(), ^{
            //start the uploader
            [self startUploader];
    
            //then prepend buffered data
            for(NSData* bufferedData in self.dataBuffer){
                [self.uploader sendChunk:bufferedData];
            }
        });
    }
}

-(void)recorderStarted {
    [self.delegate recordingSessionActivityDetectorStarted];
}


-(void)recorderVadStoppedTalking {
    [self.delegate stop];
}


#pragma mark - cleaning

-(void)clean {
    self.recorder = nil;
    self.uploader = nil;
}


-(void)dealloc {
    
    NSLog(@"Clean WITRecordingSession");
}

@end
