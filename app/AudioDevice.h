//
//  AudioDevice.h
//  iSH
//
//  Created by Theo Paris on 12/29/19.
//
#import <AudioUnit/AudioUnit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#include "kernel/fs.h"
#include "fs/dev.h"
#include "util/sync.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import "TGSineWaveToneGenerator.h"
@interface ToneGenerator : NSObject
{
    @public AudioComponentInstance toneUnit;
    @public double amplitude;
    @public Float32 *buffer;
    @public double frequency;
    @public double theta;
    @public double sampleRate;
    @public TGSineWaveToneGenerator *gen;
}

@property lock_t lock;
@property cond_t updateCond;
- (int)waitForUpdate;
+ (ToneGenerator *)instance;

@end

@interface AudioPlayer : NSObject {
    @public AVAudioPlayer *player;
    @public NSMutableData *playerData;
}
@property lock_t lock;
@property cond_t updateCond;
- (int)waitForUpdate;
+ (AudioPlayer *)instance;

@end

static NSMutableData* generateAudioWithHeaders(NSData* wave1) {

    unsigned long totalAudioLen=[wave1 length];
    unsigned long totalDataLen = totalAudioLen + 44;
    unsigned long longSampleRate = 4*11025.0;
    unsigned int channels = 1;
    unsigned long byteRate = (16 * longSampleRate * channels)/8;

    Byte *header = (Byte*)malloc(44);
    header[0] = 'R';  // RIFF/WAVE header
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    header[4] = (Byte) (totalDataLen & 0xff);
    header[5] = (Byte) ((totalDataLen >> 8) & 0xff);
    header[6] = (Byte) ((totalDataLen >> 16) & 0xff);
    header[7] = (Byte) ((totalDataLen >> 24) & 0xff);
    header[8] = 'W';
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
    header[12] = 'f';  // 'fmt ' chunk
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
    header[16] = 16;  // 4 bytes: size of 'fmt ' chunk
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    header[20] = 1;  // format = 1 for pcm and 2 for byte integer
    header[21] = 0;
    header[22] = (Byte) channels;
    header[23] = 0;
    header[24] = (Byte) (longSampleRate & 0xff);
    header[25] = (Byte) ((longSampleRate >> 8) & 0xff);
    header[26] = (Byte) ((longSampleRate >> 16) & 0xff);
    header[27] = (Byte) ((longSampleRate >> 24) & 0xff);
    header[28] = (Byte) (byteRate & 0xff);
    header[29] = (Byte) ((byteRate >> 8) & 0xff);
    header[30] = (Byte) ((byteRate >> 16) & 0xff);
    header[31] = (Byte) ((byteRate >> 24) & 0xff);
    header[32] = (Byte) (16*1)/8;  // block align
    header[33] = 0;
    header[34] = 16;  // bits per sample
    header[35] = 0;
    header[36] = 'd';
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
    header[40] = (Byte) (totalAudioLen & 0xff);
    header[41] = (Byte) ((totalAudioLen >> 8) & 0xff);
    header[42] = (Byte) ((totalAudioLen >> 16) & 0xff);
    header[43] = (Byte) ((totalAudioLen >> 24) & 0xff);

    NSData *headerData = [NSData dataWithBytes:header length:44];
    NSMutableData * soundFileData1 = [NSMutableData alloc];
    [soundFileData1 appendData:headerData];
    [soundFileData1 appendData:wave1];
    return soundFileData1;
}

extern struct dev_ops audio_sine_dev;
extern struct dev_ops audio_dev;
