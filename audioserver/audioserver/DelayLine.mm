//
//  DelayLine.cpp
//  audioserver
//
//

#include "DelayLine.h"

float DelayLine::push(float sample) {
	line.push(sample);
	
	if(line.size()-1 == length) {
		// no need to change the delay
		float result = line.front();
		line.pop();
		return result;
	}
	
	static int spincnt = 0;
	spincnt = (spincnt++)%100;
	if(spincnt != 0) {
		float result = line.front();
		line.pop();
		return result;
	}
	
	if(line.size()-1 > length) {
		// we have too much data; 
		float result1 = line.front();
		line.pop();
		float result2 = line.front();
		line.pop();
		return (result1 + result2)/2;
	} else {
		// we have too little data; retain this output 
		return line.front();
	}
}