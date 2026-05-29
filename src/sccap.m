// sccap — capture system audio + microphone to WAVs via ScreenCaptureKit (macOS 15).
//   sccap <outdir> [seconds]
//     writes <outdir>/them.wav (system audio) and <outdir>/me.wav (mic),
//     16kHz mono int16. Runs until SIGINT (or for [seconds] if given).
// Compile: clang -fobjc-arc -O2 -framework Foundation -framework ScreenCaptureKit \
//          -framework CoreMedia -framework CoreAudio sccap.m -o sccap

#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>

@interface Wav : NSObject
@property(nonatomic) NSFileHandle *fh; @property(nonatomic) uint32_t dataBytes; @property(nonatomic) uint32_t sr;
@end
@implementation Wav
- (instancetype)initWithPath:(NSString*)p sampleRate:(uint32_t)sr {
  if ((self = [super init])) {
    [[NSFileManager defaultManager] createFileAtPath:p contents:nil attributes:nil];
    _fh = [NSFileHandle fileHandleForWritingAtPath:p]; _sr = sr; _dataBytes = 0;
    uint8_t hdr[44]; memset(hdr,0,44); [_fh writeData:[NSData dataWithBytes:hdr length:44]];
  } return self;
}
- (void)appendSamples:(int16_t*)s count:(NSUInteger)n {
  @synchronized(self){ [_fh writeData:[NSData dataWithBytes:s length:n*2]]; _dataBytes += (uint32_t)(n*2); }
}
- (void)close {
  @synchronized(self){
    uint32_t sr=_sr, byteRate=sr*2, dataLen=_dataBytes, riff=36+dataLen; uint8_t h[44];
    memcpy(h,"RIFF",4); memcpy(h+4,&riff,4); memcpy(h+8,"WAVE",4); memcpy(h+12,"fmt ",4);
    uint32_t sz=16; memcpy(h+16,&sz,4); uint16_t fmt=1,ch=1,bps=16,ba=2;
    memcpy(h+20,&fmt,2); memcpy(h+22,&ch,2); memcpy(h+24,&sr,4); memcpy(h+28,&byteRate,4);
    memcpy(h+32,&ba,2); memcpy(h+34,&bps,2); memcpy(h+36,"data",4); memcpy(h+40,&dataLen,4);
    [_fh seekToFileOffset:0]; [_fh writeData:[NSData dataWithBytes:h length:44]]; [_fh closeFile];
  }
}
@end

@interface Cap : NSObject <SCStreamDelegate, SCStreamOutput>
@property(nonatomic) Wav *them; @property(nonatomic) Wav *me;
@end
@implementation Cap
- (void)writeBuf:(CMSampleBufferRef)sb to:(Wav*)w {
  CMFormatDescriptionRef fd = CMSampleBufferGetFormatDescription(sb); if(!fd) return;
  const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd); if(!asbd) return;
  if (w.sr == 0) w.sr = (uint32_t)asbd->mSampleRate;   // tag WAV with the stream's REAL rate
  AudioBufferList abl; CMBlockBufferRef block=NULL;
  if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sb,NULL,&abl,sizeof(abl),NULL,NULL,0,&block)!=noErr) return;
  BOOL isFloat = (asbd->mFormatFlags & kAudioFormatFlagIsFloat)!=0;
  uint32_t ch = asbd->mChannelsPerFrame; if (ch==0) ch=1;
  uint32_t bps = isFloat ? 4 : 2;
  AudioBuffer b = abl.mBuffers[0];
  // planar (one buffer per channel) -> use channel 0; interleaved -> stride by ch
  BOOL planar = (abl.mNumberBuffers > 1);
  NSUInteger frames = planar ? (b.mDataByteSize/bps) : (b.mDataByteSize/bps/ch);
  int16_t *out = malloc(frames*2);
  if (isFloat){
    float *f=(float*)b.mData;
    for(NSUInteger i=0;i<frames;i++){ float v = planar ? f[i] : f[i*ch]; if(v>1)v=1; if(v<-1)v=-1; out[i]=(int16_t)(v*32767.f); }
  } else {
    int16_t *p=(int16_t*)b.mData;
    for(NSUInteger i=0;i<frames;i++){ out[i] = planar ? p[i] : p[i*ch]; }
  }
  [w appendSamples:out count:frames]; free(out);
  if(block) CFRelease(block);
}
- (void)stream:(SCStream*)s didOutputSampleBuffer:(CMSampleBufferRef)sb ofType:(SCStreamOutputType)type {
  if (type==SCStreamOutputTypeAudio) [self writeBuf:sb to:self.them];
  else if (type==SCStreamOutputTypeMicrophone) [self writeBuf:sb to:self.me];
}
- (void)stream:(SCStream*)s didStopWithError:(NSError*)e { if(e) fprintf(stderr,"stopped: %s\n", e.localizedDescription.UTF8String); }
@end

static SCStream *gStream = nil; static Cap *gCap = nil;
static void finishAndExit(void) {
  dispatch_semaphore_t s = dispatch_semaphore_create(0);
  [gStream stopCaptureWithCompletionHandler:^(NSError *e){ dispatch_semaphore_signal(s); }];
  dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC));
  [gCap.them close]; [gCap.me close];
  fprintf(stderr,"done.\n"); exit(0);
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    if (argc < 2){ fprintf(stderr,"usage: sccap <outdir> [pidfile]\n"); return 1; }
    NSString *dir = @(argv[1]);
    NSString *pidfile = (argc>=3 && strcmp(argv[2],"-")!=0) ? @(argv[2]) : nil;

    __block SCShareableContent *content=nil; dispatch_semaphore_t sem=dispatch_semaphore_create(0);
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *c, NSError *e){
      if(e) fprintf(stderr,"content error: %s\n", e.localizedDescription.UTF8String); content=c; dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if(!content || content.displays.count==0){ fprintf(stderr,"no display\n"); return 1; }

    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:content.displays.firstObject excludingWindows:@[]];
    SCStreamConfiguration *cfg = [[SCStreamConfiguration alloc] init];
    cfg.capturesAudio = YES; cfg.sampleRate = 16000; cfg.channelCount = 1;
    cfg.excludesCurrentProcessAudio = YES; cfg.captureMicrophone = YES;
    cfg.width = 2; cfg.height = 2;

    gCap = [[Cap alloc] init];
    gCap.them = [[Wav alloc] initWithPath:[dir stringByAppendingPathComponent:@"them.wav"] sampleRate:0];
    gCap.me   = [[Wav alloc] initWithPath:[dir stringByAppendingPathComponent:@"me.wav"]   sampleRate:0];

    NSError *err=nil;
    gStream = [[SCStream alloc] initWithFilter:filter configuration:cfg delegate:gCap];
    dispatch_queue_t qa = dispatch_queue_create("sccap.sys", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t qm = dispatch_queue_create("sccap.mic", DISPATCH_QUEUE_SERIAL);
    if(![gStream addStreamOutput:gCap type:SCStreamOutputTypeAudio sampleHandlerQueue:qa error:&err]){
      fprintf(stderr,"add audio failed: %s\n", err.localizedDescription.UTF8String); return 1; }
    if(![gStream addStreamOutput:gCap type:SCStreamOutputTypeMicrophone sampleHandlerQueue:qm error:&err]){
      fprintf(stderr,"add mic failed: %s\n", err.localizedDescription.UTF8String); return 1; }

    __block NSError *startErr=nil;
    dispatch_semaphore_t ss=dispatch_semaphore_create(0);
    [gStream startCaptureWithCompletionHandler:^(NSError *e){ startErr=e; if(e) fprintf(stderr,"start error: %s\n", e.localizedDescription.UTF8String); dispatch_semaphore_signal(ss); }];
    dispatch_semaphore_wait(ss, DISPATCH_TIME_FOREVER);
    if (startErr) { [gCap.them close]; [gCap.me close]; exit(2); }   // permission denied etc.
    if (pidfile) [[NSString stringWithFormat:@"%d", getpid()] writeToFile:pidfile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stderr,"capturing -> %s/{them,me}.wav\n", dir.UTF8String);

    // clean stop on SIGINT
    signal(SIGINT, SIG_IGN);
    dispatch_source_t sig = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(sig, ^{ finishAndExit(); });
    dispatch_resume(sig);

    [[NSRunLoop currentRunLoop] run];   // until SIGINT (handled above)
  }
  return 0;
}
