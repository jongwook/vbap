//
//  FetchAudioOperation.m
//  audio
//
//  Created by Jong Wook Kim on 4/19/12.
//  Copyright (c) 2012 University of Michigan, Ann Arbor. All rights reserved.
//

#import "FetchAudioOperation.h"

@implementation FetchAudioOperation

@synthesize delegate, data, reader;

- (id)initWithDelegate:(ViewController*)controller sampleRate:(int)_srate numChannels:(int)_nChannels {
	if(![super init]) return nil;
	
	[self setDelegate:controller];
	[self setData:[delegate data]];
	[self setReader:[delegate reader]];
	
	srate = _srate;
	nChannels = _nChannels;
	
	return self;
}

- (void)dealloc {

}

- (void)main {
	@autoreleasepool {
		[self readAudio];
	}	
}

- (void)readAudio {
	static const NSUInteger memThreshold = (1 << 19);
	
	// Start reading
	if (![reader startReading]) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									message:@"Could not start reading." 
								   delegate:nil 
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}
	
	
	UInt32 bytesPerSample = 2 * nChannels;
	UInt64 totalBytes = 0;
	
	
	[self setData:[NSMutableData new]];
	[delegate setData:data];
	
	delegate.position = 0;
	delegate.canceled = NO;
	delegate.deleted = 0;
	
	while (reader.status == AVAssetReaderStatusReading){
        AVAssetReaderTrackOutput * trackOutput = (AVAssetReaderTrackOutput *)[reader.outputs objectAtIndex:0];
        CMSampleBufferRef sampleBufferRef = [trackOutput copyNextSampleBuffer];
		
        if (sampleBufferRef){
            CMBlockBufferRef blockBufferRef = CMSampleBufferGetDataBuffer(sampleBufferRef);
			
            size_t length = CMBlockBufferGetDataLength(blockBufferRef);
			
            NSMutableData * bufferdata = [NSMutableData dataWithLength:length];
            CMBlockBufferCopyDataBytes(blockBufferRef, 0, length, bufferdata.mutableBytes);
			
            SInt16 * samples = (SInt16 *) bufferdata.mutableBytes;
            int sampleCount = length / bytesPerSample;
            for (int i = 0; i < sampleCount ; i ++) {
                SInt32 sample = *samples++;
                if (nChannels==2) {
                    sample = (sample + *samples++)/2;
                }
				//sample /= (1 << (16-1));
				[data appendBytes:&sample length:sizeof(SInt16)];
				
            }
			
			totalBytes += sampleCount * sizeof(SInt16);
			
		    CMSampleBufferInvalidate(sampleBufferRef);
			CFRelease(sampleBufferRef);
			
			// if we have more than 10 seconds buffered, wait
			while(totalBytes - delegate.position > memThreshold && delegate.canceled == NO) {
				//NSLog(@"Waiting... %llu %u - %08x", totalBytes, [delegate position], delegate);
				[NSThread sleepForTimeInterval:0.5];
			}
			
			// if canceled, stop reading
			if([delegate canceled]) {
				[self setReader:nil];
				[delegate setReader:nil];
				return;
			}
			
			// release old data 
			if(delegate.position - delegate.deleted > memThreshold) {
				[delegate.dataLock lock];
				[delegate.data replaceBytesInRange:NSMakeRange(0, memThreshold) withBytes:nil length:0];

				delegate.deleted += memThreshold;
				[delegate.dataLock unlock];
			}
        }
    }
	
    if (reader.status == AVAssetReaderStatusFailed || reader.status == AVAssetReaderStatusUnknown){
        [[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									message:@"Something went wrong while reading" 
								   delegate:nil 
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
    }
	
	NSLog(@"Completed");
	
    [self setReader:nil], [delegate setReader:nil];
	
	[delegate performSelectorOnMainThread:@selector(pause) withObject:nil waitUntilDone:NO];
}

@end
