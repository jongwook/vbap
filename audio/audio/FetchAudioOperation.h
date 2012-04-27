//
//  FetchAudioOperation.h
//  audio
//
//  Created by Jong Wook Kim on 4/19/12.
//  Copyright (c) 2012 University of Michigan, Ann Arbor. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ViewController.h"

@interface FetchAudioOperation : NSOperation {
	ViewController *delegate;
	AVAssetReader *reader;
	NSMutableData *data;
	UInt32 srate;
	UInt32 nChannels;
}

@property (retain, nonatomic) ViewController *delegate;
@property (retain, nonatomic) AVAssetReader *reader;
@property (retain, nonatomic) NSMutableData *data;

- (void)readAudio;
- (id)initWithDelegate:(ViewController*)controller sampleRate:(int)_srate numChannels:(int)_nChannels;

@end
