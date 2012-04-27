//
//  AppDelegate.m
//  audioserver
//
//

#import <sys/time.h>
#import "portaudio.h"

#import "AppDelegate.h"
#import "Audio.h"
#import "VBAP.h"

int numChannels = 2;
float amplitudes[16];
float volume = 1.0;
DelayLine delay[16];
BOOL amplitudeEnabled = YES, timeEnabled = YES, stereoEnabled = NO;

int paCallback(const void*, void*, unsigned long, const PaStreamCallbackTimeInfo*, PaStreamCallbackFlags, void*);

@implementation AppDelegate

@synthesize window = _window;
@synthesize musicServerSocket, musicSocket, gyroSocket;
@synthesize data, position, deleted;
@synthesize azimuth, elevation;
@synthesize received;
@synthesize statusLabel, azimuthLabel, elevationLabel, channelsText, delaysText;
@synthesize volumeSlider;
@synthesize amplitudeCheckBox, timeCheckBox, stereoCheckBox;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Listen at gyroscope server, mp3 server
	
	self.musicServerSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	self.gyroSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
	
	NSError *error = nil;
	[self.musicServerSocket acceptOnPort:8191 error:&error];
	
	[self.gyroSocket bindToPort:8192 error:&error];
	if(error != nil) {
		NSLog(@"error : %@", [error description]);
	}
	[self.gyroSocket beginReceiving:&error];

	data = [NSMutableData new];
	
	NSString *address;
	for (NSString *anAddress in [[NSHost currentHost] addresses]) {
		if (![anAddress hasPrefix:@"127"] && [[anAddress componentsSeparatedByString:@"."] count] == 4) {
			address = anAddress;	
			NSLog(@"my address : %@", address);
			NSString *upload = [NSString stringWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://nyu.lyomi.net/html/save.php?data=%@", address]] encoding:NSUTF8StringEncoding error:nil];
			NSLog(@"uploaded address : %@", upload);			
			break;
		} else {
			NSLog(@"IPv4 address not available");
		}
	}
	
	[NSTimer scheduledTimerWithTimeInterval:0.1
									 target:self
								   selector:@selector(calculateAmplitudes)
								   userInfo:nil
									repeats:YES];
	
	[self initAudio];
}

- (void) calculateAmplitudes {
	if(stereoEnabled == NO) {
		// 16-channel VBAP
		calculateVBAP(self.azimuth, self.elevation);
	} else {
		// stereo setting
		amplitudes[0] = (0.0 + 4*fabs(cosf((self.azimuth+M_PI/2.0)/2.0)))/4.0;
		amplitudes[1] = (0.0 + 4*fabs(cosf((self.azimuth-M_PI/2.0)/2.0)))/4.0;
		
		delay[0].length = (1.0 + sinf(self.azimuth))*22.05;
		delay[1].length = (1.0 - sinf(self.azimuth))*22.05;
		
		int onLeft[] = {5, 6, 7, 10, 11, 14, 15};
		int onRight[] = {2, 3, 4, 8, 9, 12, 13};
		for(int i=0; i<7; i++) {
			amplitudes[onLeft[i]] = amplitudes[0];
			amplitudes[onRight[i]] = amplitudes[1];
			delay[onLeft[i]].length = delay[0].length;
			delay[onRight[i]].length = delay[1].length;
		}
	}
}

- (void) initAudio {
	PaStreamParameters outputParameters;
	PaError err;
	
	err = Pa_Initialize();
	if( err != paNoError ) {
		Pa_Terminate();
		return;
	}	
	
	// find audio device
	int numDevices;

	numDevices = Pa_GetDeviceCount();
	if( numDevices < 0 ) {
		Pa_Terminate();
		NSLog(@"ERROR: Pa_CountDevices returned 0x%x\n", numDevices );
		return;
	}
	const   PaDeviceInfo *deviceInfo;
	
    for(int i=0; i<numDevices; i++ ) {
        deviceInfo = Pa_GetDeviceInfo( i );
        NSLog(@"device %d: %s", i, deviceInfo->name);
    }
	
	outputParameters.device = Pa_GetDefaultOutputDevice(); /* default output device */
    if (outputParameters.device == paNoDevice) {
		Pa_Terminate();
		fprintf(stderr,"Error: No default output device.\n");
		return;
    }

	NSLog(@"default device index: %d", outputParameters.device);
	deviceInfo = Pa_GetDeviceInfo(outputParameters.device);
	
	NSLog(@"max output channels: %d", deviceInfo->maxOutputChannels);
	numChannels = MIN(deviceInfo->maxOutputChannels, 16);
	
	if(numChannels < 16) {
		[self.stereoCheckBox setState:NSOnState];
		stereoEnabled = YES;
	}
	
	outputParameters.device = Pa_GetDefaultOutputDevice(); /* default output device */
    if (outputParameters.device == paNoDevice) {
		Pa_Terminate();
		fprintf(stderr,"Error: No default output device.\n");
		return;
    }
	
	outputParameters.channelCount = numChannels;       /* stereo output */
    outputParameters.sampleFormat = paFloat32; /* 32 bit floating point output */
    outputParameters.suggestedLatency = deviceInfo->defaultLowOutputLatency;
    outputParameters.hostApiSpecificStreamInfo = NULL;
	
	int sampleRate = 44100;
	int FRAMES_PER_BUFFER = 64;
	
	err = Pa_OpenStream(
						&stream,
						NULL, /* no input */
						&outputParameters,
						sampleRate,
						FRAMES_PER_BUFFER,
						paClipOff,      /* we won't output out of range samples so don't bother clipping them */
						paCallback,
						(__bridge void *)self );
    if( err != paNoError ) {
		Pa_Terminate();
		return;
	}
	
    err = Pa_StartStream( stream );
    if( err != paNoError ) {
		Pa_Terminate();
		return;
	}
	
	
    return;
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)_data
	  fromAddress:(NSData *)address
withFilterContext:(id)filterContext {

	if([_data length] != 8) {
		return;
	}
	
	Float32 values[2];
	[_data getBytes:&values length:2 * sizeof(Float32)];
	azimuth = values[0];
	elevation = values[1];
	
	[self updateUI];
	
	return;
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
	if(self.musicSocket != nil) {
		NSLog(@"Rejecting connection from %@", [newSocket connectedHost]);
		return;
	}
	NSLog(@"connected to %@", [newSocket connectedHost]);
	self.musicSocket = newSocket;
	[self.musicSocket setDelegate:self];
	[self.musicSocket readDataToLength:8192 withTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)_data withTag:(long)tag {
	size_t length = [_data length]/sizeof(SInt16);
	self.received += length;
	
	SInt16 samples[length];
	[_data getBytes:samples];
	for(int i=0; i<length; i++) {
		Float32 sample = (Float32)samples[i] / (1<<15);
		[self.data appendBytes:&sample length:sizeof(Float32)];
	}
	
	// release old data 
	NSUInteger memThreshold = (1 << 20);
	if(self.position - self.deleted > memThreshold) {
		[self.data replaceBytesInRange:NSMakeRange(0, memThreshold) withBytes:nil length:0];
		
		self.deleted += memThreshold;
	}
	
	static int cnt = 0;
	cnt += [_data length]/4;
	if(cnt > 5000) {
		[self updateUI];
		cnt -= 5000;
	}
	
	[self.musicSocket readDataToLength:8192 withTimeout:-1 tag:0];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
	if(self.musicSocket == sock) {
		NSLog(@"client %@ disconnected", [sock connectedHost]);
		self.musicSocket = nil;
	}
}

- (void)updateUI {
	[self.statusLabel setTitle:[NSString stringWithFormat:@"Received Samples : %llu", self.received]];
	[self.azimuthLabel setTitle:[NSString stringWithFormat:@"Azimuth : %.2f deg", (180*self.azimuth/M_PI)]];
	[self.elevationLabel setTitle:[NSString stringWithFormat:@"Elevation : %.2f deg", (180*self.elevation/M_PI)]];
	
	volume = [volumeSlider intValue]/50.0;
	volume *= volume;
	
	NSString *text = @"Amplitudes\n";
	for(int i=0; i<16; i++) {
		text = [NSString stringWithFormat:@"%@Ch%02d %8.3f%c", text, i+1, amplitudes[i], (i%4==3?'\n':'\t')];
	}
	[self.channelsText setTitle:text];
	
	text = @"Time Delays (ms)\n";
	for(int i=0; i<16; i++) {
		text = [NSString stringWithFormat:@"%@Ch%02d %8.3f%c", text, i+1, delay[i].length/44.100, (i%4==3?'\n':'\t')];
	}
	[self.delaysText setTitle:text];
	
	amplitudeEnabled = ([self.amplitudeCheckBox state] == NSOnState);
	timeEnabled = ([self.timeCheckBox state] == NSOnState);
	stereoEnabled = ([self.stereoCheckBox state] == NSOnState);
}

- (void)stop {
	PaError err;
	
    err = Pa_StopStream( stream );
    if( err != paNoError ) goto error;
	
    err = Pa_CloseStream( stream );
    if( err != paNoError ) goto error;
	
    Pa_Terminate();
	
	stream = nil;
    printf("Test finished.\n");
	
	return;
	
error:
	Pa_Terminate();
	fprintf( stderr, "An error occured while using the portaudio stream\n" );
	fprintf( stderr, "Error number: %d\n", err );
	fprintf( stderr, "Error message: %s\n", Pa_GetErrorText( err ) );
	return;
}

@end
