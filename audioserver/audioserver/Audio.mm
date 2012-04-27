//
//  VBAP.c
//  audioserver
//
//  Created by Jong Wook Kim on 4/22/12.
//  Copyright (c) 2012 University of Michigan, Ann Arbor. All rights reserved.
//

#import <portaudio.h>

#import "AppDelegate.h"
#import "Audio.h"

int paCallback( const void *inputBuffer, void *outputBuffer,
					  unsigned long framesPerBuffer,
					  const PaStreamCallbackTimeInfo* timeInfo,
					  PaStreamCallbackFlags statusFlags,
					  void *userData )
{
    AppDelegate *delegate = (__bridge AppDelegate *)userData;
    float *out = (float*)outputBuffer;
	
	NSUInteger length = framesPerBuffer * sizeof(Float32);
	Float32 audio[framesPerBuffer];
	
	NSUInteger position = delegate.position - delegate.deleted;
	
	// if there is not enough stream, just skip
	if([delegate.data length] < position + length) {
		[NSThread sleepForTimeInterval:0.1];
		if([delegate.data length] < position + length) {
			memset(out, 0, framesPerBuffer * sizeof(float) * numChannels);
			//NSLog(@"skipped %llu", delegate.received);
			return paContinue;
		}
	}
	
	[delegate.data getBytes:(void *)audio range:NSMakeRange(position, length)];
	
	// Generate the samples
	static float prevAmplitudes[16]={0,};
	
	for (UInt32 frame = 0; frame < framesPerBuffer; frame++) {
		float alpha = (float)frame / framesPerBuffer;
		
		for(UInt32 channel = 0; channel < numChannels; channel++) {
			*out = (timeEnabled)?delay[channel].push(audio[frame]) : audio[frame];
			if(amplitudeEnabled) *out *= prevAmplitudes[channel]*(1-alpha) + amplitudes[channel]*alpha;
			*out *= volume;
			out++;
		}
	}
	
	for(UInt32 channel = 0; channel < numChannels; channel++) {
		prevAmplitudes[channel] = amplitudes[channel];
	}
	
	delegate.position += length;
	//[delegate performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
	//NSLog(@"position : %d controller:%08x", [viewController position], viewController);
	
	(void) timeInfo; /* Prevent unused variable warnings. */
    (void) statusFlags;
    (void) inputBuffer;
    
	return paContinue;
}