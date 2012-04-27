//
//  DelayLine.h
//  audioserver
//
//

#ifndef audioserver_DelayLine_h
#define audioserver_DelayLine_h

#include <queue>

class DelayLine {
public:
	DelayLine() : length(0) {}
	
	float push(float sample);
	int length;
	
protected:
	std::queue<float> line;
};

#endif
