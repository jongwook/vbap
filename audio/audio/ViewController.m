//
//  ViewController.m
//  audio
//
//  Created by Jong Wook Kim on 4/18/12.
//  Copyright (c) 2012 University of Michigan, Ann Arbor. All rights reserved.
//

#import "ViewController.h"
#import "FetchAudioOperation.h"

OSStatus RenderTone(void *inRefCon, 
					AudioUnitRenderActionFlags 	*ioActionFlags, 
					const AudioTimeStamp 		*inTimeStamp, 
					UInt32 						inBusNumber, 
					UInt32 						inNumberFrames, 
					AudioBufferList 			*ioData);

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState);


OSStatus RenderTone(void *inRefCon, 
					AudioUnitRenderActionFlags 	*ioActionFlags, 
					const AudioTimeStamp 		*inTimeStamp, 
					UInt32 						inBusNumber, 
					UInt32 						inNumberFrames, 
					AudioBufferList 			*ioData)

{
	// Get the tone parameters out of the view controller
	ViewController *viewController = (__bridge ViewController *)inRefCon;

	// This is a mono tone generator so we only need the first buffer
	const int channel = 0;
	SInt16 *buffer = (SInt16 *)ioData->mBuffers[channel].mData;
	
	NSUInteger length = inNumberFrames * sizeof(SInt16);
	SInt16 audio[inNumberFrames];
	
	[viewController.dataLock lock];
	NSUInteger position = viewController.position - viewController.deleted;
	
	// if there is not enough stream, just skip
	if(viewController.canceled || viewController.paused || [viewController.data length] < position + length) {
		[viewController.dataLock unlock];
		memset(buffer, 0, length);
		return noErr;
	}
	[viewController.data getBytes:(void *)audio range:NSMakeRange(position, length)];
	[viewController.dataLock unlock];
	
	// TODO: send tcp packet if connected
	
	if(viewController.musicSocket.isConnected) {
		[viewController.musicSocket writeData:[NSData dataWithBytes:audio length:length] 
								  withTimeout:-1 
										  tag:0];
	}
	
	// dont play in local device; streaming instead
	memset(buffer, 0, length);
	
	for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
		buffer[frame] = audio[frame];
	}
	
	
	viewController.position += length;
	[viewController performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
	//NSLog(@"position : %d controller:%08x", [viewController position], viewController);
	return noErr;
}

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
	ViewController *viewController = (__bridge ViewController *)inClientData;
	
	[viewController stop];
}

@implementation ViewController

@synthesize reader, data;
@synthesize dataLock;
@synthesize position, duration, deleted, canceled, paused, volume;
@synthesize titleLabel, currentTimeLabel, durationLabel;
@synthesize progressView, elevationView, azimuthView, playButtonImageView;
@synthesize motionManager;
@synthesize gyroSocket, musicSocket, server;

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	
	queue = [[NSOperationQueue alloc] init];
	
	[self createAudioUnit];
	self.paused = YES;
	
	// Stop changing parameters on the unit
	OSErr err = AudioUnitInitialize(audioUnit);
	NSAssert1(err == noErr, @"Error initializing unit: %ld", err);
	
	// Start playback
	err = AudioOutputUnitStart(audioUnit);
	NSAssert1(err == noErr, @"Error starting unit: %ld", err);
	
	// rotate elevation view
	self.elevationView.transform = CGAffineTransformMakeRotation(-M_PI_2);
	
	// init motion manager
	motionManager = [[CMMotionManager alloc] init]; 
	if (motionManager.gyroAvailable) {
		motionManager.gyroUpdateInterval = 1.0/24.0;
		[motionManager startGyroUpdates];
        CMDeviceMotionHandler motionHandler = ^ (CMDeviceMotion *motion, NSError *error) {
			CMAttitude *rotate = motion.attitude;
			
			const double rate = 0.5;
			azimuth = azimuth*rate + (-rotate.yaw)*(1-rate);
			elevation = elevation*rate + rotate.pitch*(1-rate);
			[self updateUI];
		};
		[motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue currentQueue]
										   withHandler:motionHandler];
	} else {
        NSLog(@"No gyroscope on device.");
    }
	
	
	// get volume changed notification
	[[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(volumeChanged:)
     name:@"AVSystemController_SystemVolumeDidChangeNotification"
     object:nil];
	
	// init udp socket
	self.gyroSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	
	// get the server address and connect
	self.musicSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	[self tryConnect];
	
	NSLog(@"server address : %@", self.server);	
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
	
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
	return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (NSString *) makeTimeString:(float)seconds {
	NSUInteger sec = (NSUInteger)seconds;
	NSUInteger min = sec / 60;
	sec -= min * 60;
	return [NSString stringWithFormat:@"%02d:%02d", min, sec];
}

- (void) volumeChanged:(NSNotification *)notification {
	self.volume = [[[notification userInfo]
      objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"]
     floatValue];
	
	NSLog(@"New Volume : %f", self.volume);
}

- (IBAction)selectMusic:(id)sender
{	
	[self setCanceled:YES];
	
	MPMediaPickerController *picker = [[MPMediaPickerController alloc] initWithMediaTypes: MPMediaTypeAnyAudio];   
	
	[picker setDelegate: self];
	[picker setAllowsPickingMultipleItems: NO];
	picker.prompt = NSLocalizedString (@"Select a song to play", "");
	
	[self presentModalViewController: picker animated: YES];    // 4
}

- (IBAction)resetForward:(id)sender {
	reference = azimuth;
}

- (void) updateUI {
	float currentPosition = (float)position/sizeof(SInt16)/44100;
	[self.progressView setProgress:currentPosition/duration];
	[self.currentTimeLabel setText:[self makeTimeString:currentPosition]];
	
	double relAzimuth = azimuth - reference;
	if(relAzimuth < -M_PI) relAzimuth += M_PI*2;
	if(relAzimuth > M_PI) relAzimuth -= M_PI*2;
	[self.azimuthView setProgress:(relAzimuth + M_PI)/M_PI/2];
	[self.elevationView setProgress:(elevation + M_PI_2)/M_PI];
	
	float values[2] = {relAzimuth, elevation};
	[self.gyroSocket sendData:[NSData dataWithBytes:&values length:2*sizeof(float)]
				   toHost:self.server
					 port:8192 
			  withTimeout:-1 
					  tag:0];
	
	
}

- (void) mediaPicker: (MPMediaPickerController *) mediaPicker
   didPickMediaItems: (MPMediaItemCollection *) collection {
	[self dismissModalViewControllerAnimated: YES];
	
	if([reader status] == AVAssetReaderStatusReading) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									 message:@"Still loading previous audio" 
									delegate:nil 
						   cancelButtonTitle:@"OK"
						   otherButtonTitles:nil] show];
		return;
	}
	
	NSArray *items = [collection items];
	MPMediaItem *item = [items lastObject];
	NSLog(@"Description: %@", [item valueForProperty:MPMediaItemPropertyTitle]);
	[self.titleLabel setText:[item valueForProperty:MPMediaItemPropertyTitle]];
	
	NSURL *url = [item valueForProperty: MPMediaItemPropertyAssetURL];
	NSLog(@"URL: %@", [url absoluteString]);
	
	AVURLAsset *uasset = [AVURLAsset URLAssetWithURL: url options:nil];
	if (uasset.hasProtectedContent) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									 message:@"The audio track is DRM protected." 
									delegate:nil 
						   cancelButtonTitle:@"OK"
						   otherButtonTitles:nil] show];

		NSLog(@"Error: DRM Protected");
		return;
	}
	
	// Initialize a reader with a track output
	NSError *err = nil;
	reader = [[AVAssetReader alloc] initWithAsset:uasset error:&err];
	if (!reader || err) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									 message:@"Could not create asset reader." 
									delegate:nil 
						   cancelButtonTitle:@"OK"
						   otherButtonTitles:nil] show];
		return;
	}
	
	// Check tracks for valid format. 
	// Currently we only support all MP3 and AAC types, WAV and AIFF is too large to handle
	AVAssetTrack *track = [uasset.tracks objectAtIndex:0];
	
	if (track == nil) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									 message:@"Unsupported Format." 
									delegate:nil 
						   cancelButtonTitle:@"OK"
						   otherButtonTitles:nil] show];
		
		return;
	}
	
	[self setDuration:CMTimeGetSeconds(track.timeRange.duration)];
	[self.durationLabel setText:[self makeTimeString:self.duration]];
	
	// Create an output for the found track
	NSDictionary* outputSettingsDict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kAudioFormatLinearPCM],AVFormatIDKey,
                                        [NSNumber numberWithInt:16],AVLinearPCMBitDepthKey,
                                        [NSNumber numberWithBool:NO],AVLinearPCMIsBigEndianKey,
                                        [NSNumber numberWithBool:NO],AVLinearPCMIsFloatKey,
                                        [NSNumber numberWithBool:NO],AVLinearPCMIsNonInterleaved,
                                        nil];
	
	AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:outputSettingsDict];
	[reader addOutput:output];

	UInt32 sampleRate, channelCount;
	
	NSArray* formatDesc = track.formatDescriptions;
    for(unsigned int i = 0; i < [formatDesc count]; ++i) {
        CMAudioFormatDescriptionRef item = (__bridge CMAudioFormatDescriptionRef)[formatDesc objectAtIndex:i];
        const AudioStreamBasicDescription* fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription (item);
        if(fmtDesc ) {
            sampleRate = fmtDesc->mSampleRate;
            channelCount = fmtDesc->mChannelsPerFrame;
			
            NSLog(@"channels:%lu, bytes/packet: %lu, sampleRate %f",fmtDesc->mChannelsPerFrame, fmtDesc->mBytesPerPacket,fmtDesc->mSampleRate);
        }
    }
	
	if (sampleRate != 44100) {
		[[[UIAlertView alloc] initWithTitle:@"Error opening audio" 
									 message:@"non-44100 mp3 not supported" 
									delegate:nil 
						   cancelButtonTitle:@"OK"
						   otherButtonTitles:nil] show];
	}
	
    FetchAudioOperation *operation = [[FetchAudioOperation alloc] initWithDelegate:self sampleRate:sampleRate numChannels:channelCount];
	
	[queue addOperation:operation];
	
	[self play];
}

- (void) mediaPickerDidCancel: (MPMediaPickerController *) mediaPicker {
	NSLog(@"Canceled media picking");
    [self dismissModalViewControllerAnimated: YES];
}

- (void) createAudioUnit {
	// Configure the search parameters to find the default playback output unit
	// (called the kAudioUnitSubType_RemoteIO on iOS but
	// kAudioUnitSubType_DefaultOutput on Mac OS X)
	AudioComponentDescription defaultOutputDescription;
	defaultOutputDescription.componentType = kAudioUnitType_Output;
	defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	defaultOutputDescription.componentFlags = 0;
	defaultOutputDescription.componentFlagsMask = 0;
	
	// Get the default playback output unit
	AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
	NSAssert(defaultOutput, @"Can't find default output");
	
	// Create a new unit based on this that we'll use for output
	OSErr err = AudioComponentInstanceNew(defaultOutput, &audioUnit);
	NSAssert1(audioUnit, @"Error creating unit: %ld", err);
	
	// Set our tone rendering function on the unit
	AURenderCallbackStruct input;
	input.inputProc = RenderTone;
	input.inputProcRefCon = (__bridge void*)self;
	err = AudioUnitSetProperty(audioUnit, 
							   kAudioUnitProperty_SetRenderCallback, 
							   kAudioUnitScope_Input,
							   0, 
							   &input, 
							   sizeof(input));
	NSAssert1(err == noErr, @"Error setting callback: %ld", err);
	
	//const int four_bytes_per_float = 4;
	const int two_bytes_per_short = 2;
	const int eight_bits_per_byte = 8;
	AudioStreamBasicDescription streamFormat;
	streamFormat.mSampleRate = 44100;
	streamFormat.mFormatID = kAudioFormatLinearPCM;
	streamFormat.mFormatFlags =
    kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
	streamFormat.mBytesPerPacket = two_bytes_per_short;
	streamFormat.mFramesPerPacket = 1;    
	streamFormat.mBytesPerFrame = two_bytes_per_short;        
	streamFormat.mChannelsPerFrame = 1;    
	streamFormat.mBitsPerChannel = two_bytes_per_short * eight_bits_per_byte;
	err = AudioUnitSetProperty (audioUnit,
								kAudioUnitProperty_StreamFormat,
								kAudioUnitScope_Input,
								0,
								&streamFormat,
								sizeof(AudioStreamBasicDescription));
	NSAssert1(err == noErr, @"Error setting stream format: %ld", err);
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
	NSLog(@"Connected to host %@", host);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
//	NSLog(@"Disconnected from host %@", [sock connectedHost]);
	
	[self tryConnect];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {

}

- (void)tryConnect {
	NSError *error = nil;
	self.server = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"http://nyu.lyomi.net/html/save.php"]
										   encoding:NSUTF8StringEncoding 
											  error:nil];
	if(![musicSocket connectToHost:self.server onPort:8191 withTimeout:5.0 error:&error]) {
		NSLog(@"Connect error: %@", [error description]);
	}
}

- (void)stop
{
	if (audioUnit)
	{
		AudioOutputUnitStop(audioUnit);
		AudioUnitUninitialize(audioUnit);
		AudioComponentInstanceDispose(audioUnit);
		audioUnit = nil;
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];
	CGPoint point = [touch locationInView:self.view];
	if(CGRectContainsPoint(playButtonImageView.frame, point)) {
		// touched on image
		
		if(self.paused) {
			// play
			if(reader != nil) {
				[self play];
			} else {
				// need to open a song
				[self selectMusic:nil];
			}
		} else {
			[self pause];
		}
	}
}

-(void)pause {
	self.paused = YES;
	[self.playButtonImageView setImage:[UIImage imageNamed:@"play.png"]];
}

-(void)play {
	self.paused = NO;
	[self.playButtonImageView setImage:[UIImage imageNamed:@"pause.png"]];
}

@end
