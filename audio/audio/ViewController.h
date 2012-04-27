//
//  ViewController.h
//  audio
//
//  Created by Jong Wook Kim on 4/18/12.
//  Copyright (c) 2012 University of Michigan, Ann Arbor. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreMotion/CoreMotion.h>

#import "GCDAsyncSocket.h"
#import "GCDAsyncUdpSocket.h"

@interface ViewController : UIViewController<MPMediaPickerControllerDelegate> {
	AVAssetReader *reader;
	
	NSMutableData *data;
	NSUInteger position, deleted;
	BOOL canceled;
	BOOL paused;
	
	Float64 duration;
	NSOperationQueue *queue;
	AudioComponentInstance audioUnit;
	CMMotionManager *motionManager;
	
	IBOutlet UILabel *titleLabel, *currentTimeLabel, *durationLabel;
	IBOutlet UIProgressView *progressView;
	IBOutlet UIProgressView *azimuthView, *elevationView;
	IBOutlet UIImageView *playButtonImageView;
	
	double azimuth, elevation;
	double reference;
	
	NSString *server;
}

- (NSString *) makeTimeString:(float)seconds;
- (IBAction) selectMusic:(id)sender;
- (IBAction) resetForward:(id)sender;
- (void) updateUI;
- (void) stop;

-(void) pause;
-(void) play;

-(void) tryConnect;

@property (retain, nonatomic) AVAssetReader *reader;

@property (retain, nonatomic) NSMutableData *data;
@property (assign, atomic) NSUInteger position;
@property (assign, nonatomic) NSUInteger deleted;
@property (assign, nonatomic) BOOL canceled, paused;
@property (retain, nonatomic) NSLock *dataLock;

@property (assign, nonatomic) Float64 duration;
@property (assign, nonatomic) Float32 volume;

@property (retain, nonatomic) CMMotionManager *motionManager;
@property (retain, nonatomic) UILabel *titleLabel, *currentTimeLabel, *durationLabel;
@property (retain, nonatomic) UIProgressView *progressView;
@property (retain, nonatomic) UIProgressView *azimuthView, *elevationView;
@property (retain, nonatomic) UIImageView *playButtonImageView;

@property (retain, nonatomic) GCDAsyncSocket *musicSocket;
@property (retain, nonatomic) GCDAsyncUdpSocket *gyroSocket;
@property (retain, nonatomic) NSString *server;


@end
