//
//  AppDelegate.h
//  audioserver
//
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AudioUnit/AudioUnit.h>

#import "GCDAsyncSocket.h"
#import "GCDAsyncUdpSocket.h"

#import "VBAP.h"
#import "DelayLine.h"

extern int numChannels;
extern float amplitudes[16];
extern float volume;
extern DelayLine delay[16];
extern BOOL amplitudeEnabled, timeEnabled, stereoEnabled;

typedef void PaStream;

@interface AppDelegate : NSObject <NSApplicationDelegate, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate> {
	AudioComponentInstance audioUnit;
	
	NSMutableData *data;
	NSUInteger position, deleted;
	Float32 azimuth, elevation;
	UInt64 received;
	
	PaStream *stream;
}

- (void) initAudio;
- (void) updateUI;
- (void) stop;
- (void) calculateAmplitudes;

@property (assign) IBOutlet NSWindow *window;
@property (retain, nonatomic) GCDAsyncSocket *musicServerSocket, *musicSocket;
@property (retain, nonatomic) GCDAsyncUdpSocket *gyroSocket;
@property (retain, nonatomic) NSMutableData *data;

@property (assign, nonatomic) NSUInteger position, deleted;
@property (assign, nonatomic) UInt64 received;
@property (assign, nonatomic) Float32 azimuth, elevation;

@property (retain, nonatomic) IBOutlet NSTextFieldCell *statusLabel, *azimuthLabel, *elevationLabel;
@property (retain, nonatomic) IBOutlet NSSlider *volumeSlider;
@property (retain, nonatomic) IBOutlet NSTextFieldCell *channelsText, *delaysText;
@property (retain, nonatomic) IBOutlet NSButton *amplitudeCheckBox, *timeCheckBox, *stereoCheckBox;

@end
