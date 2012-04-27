//
//  VBAP.h
//  audioserver
//
//

#ifndef audioserver_VBAP_h
#define audioserver_VBAP_h

#include "portaudio.h"

int paCallback( const void *inputBuffer, void *outputBuffer,
					  unsigned long framesPerBuffer,
					  const PaStreamCallbackTimeInfo* timeInfo,
					  PaStreamCallbackFlags statusFlags,
					  void *userData );

#endif
