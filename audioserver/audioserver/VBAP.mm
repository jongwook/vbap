//
//  VBAP.c
//  audioserver
//
//

#import <math.h>

#import "AppDelegate.h"
#import "VBAP.h"
#import "DelayLine.h"

// coordinates of 16 speakers
static float speakers[16][3] = {
	{0.000000, 1.000000, 0.000000},
	{0.707107, 0.707107, 0.000000},
	{1.000000, -0.000000, 0.000000},
	{0.707107, -0.707107, 0.000000},
	{-0.000000, -1.000000, 0.000000},
	{-0.707107, -0.707107, 0.000000},
	{-1.000000, 0.000000, 0.000000},
	{-0.707107, 0.707107, 0.000000},
	{0.500000, -0.500000, 0.707107},
	{0.500000, 0.500000, 0.707107},
	{-0.500000, -0.500000, 0.707107},
	{-0.500000, 0.500000, 0.707107},
	{0.500000, -0.500000, -0.707107},
	{0.500000, 0.500000, -0.707107},
	{-0.500000, -0.500000, -0.707107},
	{-0.500000, 0.500000, -0.707107},
};

// indices of triangles; all facing outward
static int triangles[28][3] = {
	// az 225-45 el 0-90
	{0, 9, 1},	{9, 11, 10},{5, 10, 6},	{6, 10, 11},{6, 11, 7},	{7, 11, 0},	{0, 11, 9},
	
	// az 45-225 el 0-90
	{1, 9, 2},	{2, 9, 8},	{2, 8, 3},	{3, 8, 4},	{4, 8, 10},	{4, 10, 5},	{8, 9, 10},
	
	// az 225-45 el -90-0
	{0, 1, 13},	{13, 14, 15},{5, 6, 14},{6, 15, 14},{6, 7, 15},	{7, 0, 15},	{0, 13, 15},
	
	// az 45-225 el -90-0
	{1, 2, 13},	{2, 12, 13},{2, 3, 12},	{3, 4, 12},	{4, 14, 12},{4, 5, 14},	{12, 14, 13},
};

static float dot(float *x, float*y) {
	return x[0]*y[0] + x[1]*y[1] + x[2]*y[2];
}

static void cross(float *x, float *y, float *result) {
	result[0] = x[1]*y[2] - x[2]*y[1];
	result[1] = x[2]*y[0] - x[0]*y[2];
	result[2] = x[0]*y[1] - x[1]*y[0];
}

static void add(float *x, float *y, float *result) {
	result[0] = x[0] + y[0];
	result[1] = x[1] + y[1];
	result[2] = x[2] + y[2];
}

static void subtract(float *x, float *y, float *result) {
	result[0] = x[0] - y[0];
	result[1] = x[1] - y[1];
	result[2] = x[2] - y[2];
}

static void inverse(float *m, float *result) {
	float det = m[0]*m[4]*m[8] - m[0]*m[5]*m[7] - m[3]*m[1]*m[8] + m[3]*m[2]*m[7] + m[6]*m[1]*m[5] - m[6]*m[2]*m[4];
	result[0] = (m[4]*m[8] - m[5]*m[7]) / det;
	result[1] = (m[2]*m[7] - m[1]*m[8]) / det;
	result[2] = (m[1]*m[5] - m[2]*m[4]) / det;
	result[3] = (m[5]*m[6] - m[3]*m[8]) / det;
	result[4] = (m[0]*m[8] - m[2]*m[6]) / det;
	result[5] = (m[2]*m[3] - m[0]*m[5]) / det;
	result[6] = (m[3]*m[7] - m[4]*m[6]) / det;
	result[7] = (m[1]*m[6] - m[0]*m[7]) / det;
	result[8] = (m[0]*m[4] - m[1]*m[3]) / det;
}

static void product(float *v, float *m, float *result) {
	result[0] = v[0]*m[0] + v[1]*m[3] + v[2]*m[6];
	result[1] = v[0]*m[1] + v[1]*m[4] + v[2]*m[7];
	result[2] = v[0]*m[2] + v[1]*m[5] + v[2]*m[8];
}

void calculateVBAP(float azimuth, float elevation) {
	float x[3];
	x[0] = cos(elevation) * sin(azimuth);
	x[1] = cos(elevation) * cos(azimuth);
	x[2] = sin(elevation);
	
	int half = (elevation > 0)?0:1;
	
	
	// the triangle index
	int t = -1;
	for(int i=half*14; i < (half+1)*14; i++) {
		float ab[3], bc[3], ca[3];
		
		cross(speakers[triangles[i][0]], speakers[triangles[i][1]], ab);
		cross(speakers[triangles[i][1]], speakers[triangles[i][2]], bc);
		cross(speakers[triangles[i][2]], speakers[triangles[i][0]], ca);
		
		if(dot(ab, x) >= 0 && dot(bc, x) >= 0 && dot(ca, x) >= 0) {
			t = i;
			break;
		}
	}
	
	//NSLog(@"Found triangle : %d, %d, %d", triangles[t][0], triangles[t][1], triangles[t][2]);
	
	float matrix[9] = {
		speakers[triangles[t][0]][0], speakers[triangles[t][0]][1], speakers[triangles[t][0]][2], 
		speakers[triangles[t][1]][0], speakers[triangles[t][1]][1], speakers[triangles[t][1]][2], 
		speakers[triangles[t][2]][0], speakers[triangles[t][2]][1], speakers[triangles[t][2]][2] };
	
	float inv[9];
	inverse(matrix, inv);
	
	float gain[3];
	product(x, inv, gain);
	//NSLog(@"gain : %f, %f, %f", gain[0], gain[1], gain[2]);
	
	float amp = sqrt(gain[0]*gain[0] + gain[1]*gain[1] + gain[2]*gain[2]);
	gain[0] /= amp;
	gain[1] /= amp;
	gain[2] /= amp;
	
	for(int i=0; i<16; i++) {
		amplitudes[i] = 0;
		delay[i].length = 0;
	}
	for(int i=0; i<3; i++) {
		amplitudes[triangles[t][i]] = gain[i];
		delay[triangles[t][i]].length = (1.0-gain[i]) * 44.1;
	}
}
