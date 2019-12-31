//
//  AudioDevice.m
//  iSH
//
//  Created by Theo Paris on 12/29/19.
//


#include "AudioDevice.h"

@implementation ToneGenerator
+ (ToneGenerator *)instance {
    static __weak ToneGenerator *tracker;
    if (tracker == nil) {
        __block ToneGenerator *newTracker;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (tracker == nil) {
                newTracker = [ToneGenerator new];
                tracker = newTracker;
            }
        });
        return newTracker;
    }
    return tracker;
}

- (void) togglePlay {
    if(!gen) {
        gen = [[TGSineWaveToneGenerator alloc] initWithChannels:1];
        gen->_channels[0].frequency = frequency;
        gen->_channels[0].amplitude = SINE_WAVE_TONE_GENERATOR_AMPLITUDE_HIGH;
        [gen playForDuration:0.5];
    } else {
        [gen stop];
        gen = nil;
    }
}

- (instancetype)init {
    if (self = [super init]) {
        self->amplitude = 0.5;
        self->frequency = 420;
        self->sampleRate = 44100;
        
        lock_init(&_lock);
        cond_init(&_updateCond);
    }
    return self;
}
- (void)dealloc {
    gen = nil;
    cond_destroy(&_updateCond);
}

- (int)waitForUpdate {
    lock(&_lock);
    
    unlock(&_lock);
    return 0;
}

@end

@interface AudioSineFile : NSObject {
    NSData *buffer;
    size_t bufferOffset;
}

@property ToneGenerator *tracker;

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size;

@end

@implementation AudioSineFile

- (instancetype)init {
    if (self = [super init]) {
        self.tracker = [ToneGenerator instance];
        
    }
    return self;
}

- (int)waitForUpdate {
    if (buffer != nil)
        return 0;
    int err = [self.tracker waitForUpdate];
    if (err < 0)
        return err;
    NSString *output = [NSString stringWithFormat:@"Write \"toggle\" into this file to generate a sine wave tone.\n"];
    buffer = [output dataUsingEncoding:NSUTF8StringEncoding];
    bufferOffset = 0;
    return 0;
}

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size {
    @synchronized (self) {
        int err = [self waitForUpdate];
        if (err < 0)
            return err;
        size_t remaining = buffer.length - bufferOffset;
        if (size > remaining)
            size = remaining;
        [buffer getBytes:buf range:NSMakeRange(bufferOffset, size)];
        bufferOffset += size;
        if (bufferOffset == buffer.length)
            buffer = nil;
        return size;
    }
}

- (ssize_t)readFromBuffer:(void *)buf size:(size_t)size {
    @synchronized (self) {
        int err = [self waitForUpdate];
        if (err < 0)
            return err;
        buffer = [NSData dataWithBytes:buf length:size];
        NSString *output = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if(output) {
            if([output isEqualToString: @"toggle"]) {
                [[self tracker] togglePlay];
                NSLog(@"toggling");
            } else {
                NSLog(@"output: %@", output);
            }
        } else {
            NSLog(@"Error reading from buffer - not a valid string!");
            return 0;
        }
        return size;
    }
}

@end


static int audio_sine_open(int major, int minor, struct fd *fd) {
    fd->data = (void *) CFBridgingRetain([AudioSineFile new]);
    return 0;
}

static int audio_sine_close(struct fd *fd) {
    CFBridgingRelease(fd->data);
    return 0;
}

static ssize_t audio_sine_read(struct fd *fd, void *buf, size_t size) {
    AudioSineFile *file = (__bridge AudioSineFile *) fd->data;
    return [file readIntoBuffer:buf size:size];
}

static ssize_t audio_sine_write(struct fd *fd, void *buf, size_t size) {
    AudioSineFile *file = (__bridge AudioSineFile *) fd->data;
    [file readFromBuffer:buf size:size];
    
    
    return size;
}

struct dev_ops audio_sine_dev = {
    .open = audio_sine_open,
    .fd.close = audio_sine_close,
    .fd.read = audio_sine_read,
    .fd.write = audio_sine_write
};

@implementation AudioPlayer + (AudioPlayer *)instance {
    static __weak AudioPlayer *tracker;
    if (tracker == nil) {
        __block AudioPlayer *newTracker;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (tracker == nil) {
                newTracker = [AudioPlayer new];
                tracker = newTracker;
            }
        });
        return newTracker;
    }
    return tracker;
}

- (void) play {
    
}

- (void)dealloc {
    self->playerData = nil;
    
    cond_destroy(&_updateCond);
}

- (int)waitForUpdate {
    lock(&_lock);
    
    unlock(&_lock);
    return 0;
}

@end


@interface AudioFile : NSObject {
    NSData *buffer;
    size_t bufferOffset;
}

@property AudioPlayer *audioPlayer;

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size;

@end

@implementation AudioFile

- (instancetype)init {
    if (self = [super init]) {
        self.audioPlayer = [AudioPlayer instance];
        
    }
    return self;
}

- (int)waitForUpdate {
    if (buffer != nil)
        return 0;
    int err = [self.audioPlayer waitForUpdate];
    if (err < 0)
        return err;
    NSString *output = [NSString stringWithFormat:@"Pipe audio data into this file to play it.\n"];
    buffer = [output dataUsingEncoding:NSUTF8StringEncoding];
    bufferOffset = 0;
    return 0;
}

- (ssize_t)readIntoBuffer:(void *)buf size:(size_t)size {
    @synchronized (self) {
        int err = [self waitForUpdate];
        if (err < 0)
            return err;
        size_t remaining = buffer.length - bufferOffset;
        if (size > remaining)
            size = remaining;
        [buffer getBytes:buf range:NSMakeRange(bufferOffset, size)];
        bufferOffset += size;
        if (bufferOffset == buffer.length)
            buffer = nil;
        return size;
    }
}

- (ssize_t)readFromBuffer:(void *)buf size:(size_t)size {
    @synchronized (self) {
        int err = [self waitForUpdate];
        if (err < 0)
            return err;
        buffer = [NSData dataWithBytes:buf length:size];
        NSData *wave1= [NSMutableData dataWithData:buffer];
        NSMutableData *outData = generateAudioWithHeaders(wave1);
        NSError *error1;
        self.audioPlayer->player = [[AVAudioPlayer alloc] initWithData:wave1 fileTypeHint:@"wav" error:&error1];
        [self.audioPlayer->player play]; //to play
        return size;
    }
}

@end

static int audio_open(int major, int minor, struct fd *fd) {
    fd->data = (void *) CFBridgingRetain([AudioFile new]);
    return 0;
}

static int audio_close(struct fd *fd) {
    CFBridgingRelease(fd->data);
    return 0;
}

static ssize_t audio_read(struct fd *fd, void *buf, size_t size) {
    AudioFile *file = (__bridge AudioFile *) fd->data;
    return [file readIntoBuffer:buf size:size];
}

static ssize_t audio_write(struct fd *fd, void *buf, size_t size) {
    AudioFile *file = (__bridge AudioFile *) fd->data;
    [file readFromBuffer:buf size:size];
    
    
    return size;
}


struct dev_ops audio_dev = {
    .open = audio_open,
    .fd.close = audio_close,
    .fd.read = audio_read,
    .fd.write = audio_write
};
