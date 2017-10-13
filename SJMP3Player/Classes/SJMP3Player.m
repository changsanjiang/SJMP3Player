//
//  SJMP3Player.m
//  SJMP3PlayWhileDownloadingProject
//
//  Created by BlueDancer on 2017/6/21.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import "SJMP3Player.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

NSString *const SJMP3PlayerDownloadAudioIdentifier = @"com.dancebaby.lanwuzhe.audioCacheSession";


/**
 *  0.00 - 1.00
 *  If it's 1.00, play after download. */
#define SJAudioWhenToStartPlaying   (0.1)

/*!
 *  网路环境差 导致的停止播放 延迟多少秒继续播放 */
#define SJAudioDelayTime (2)


// MARK: File Path

/*!
 *  查看某个目录是否存在 */
inline static BOOL _SJFolderExists(NSString *path) { return [[NSFileManager defaultManager] fileExistsAtPath:path];}

inline static NSString *_SJHashStr(NSString *URLStr) {
    if ( !URLStr ) return nil;
    return [NSString stringWithFormat:@"%zd", [URLStr hash]];
}

/**
 *  缓存根目录
 *  ../com.dancebaby.lanwuzhe.audioCacheFolder/ */
inline static NSString *_SJAudioCacheRootFolder() {
    NSString *sCachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
    NSString *folderPath = [sCachePath stringByAppendingPathComponent:@"com.dancebaby.lanwuzhe.audioCacheFolder"];
    return folderPath;
}

/*!
 *  临时缓存目录
 *  tmp/audioTmpFolder */
inline static NSString *_SJAudioDownloadingTmpFolder() {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"audioTmpFolder"];
}

/*!
 *  临时缓存路径
 * tmp/audioTmpFolder/urlStrHash */
inline static NSString *_SJAudioDownloadingTmpPath(NSString *URLStr) {
    return [_SJAudioDownloadingTmpFolder() stringByAppendingPathComponent:_SJHashStr(URLStr)];
}

/*!
 *  缓存目录
 *  ../com.dancebaby.lanwuzhe.audioCacheFolder/cache */
inline static NSString *_SJAudioCacheFolderPath() { return [_SJAudioCacheRootFolder() stringByAppendingPathComponent:@"cache"];}

/**
 *  /var/../com.dancebaby.lanwuzhe.audioCacheFolder/cache/StrHash */
inline static NSString *_SJAudioCachePathWithURLStr(NSString *URLStr) {
    NSString *cacheName = [_SJHashStr(URLStr) stringByAppendingString:@".mp3"];
    NSString *cachePath = [_SJAudioCacheFolderPath() stringByAppendingPathComponent:cacheName];
    if ( cachePath ) return cachePath;
    return @"";
}

/*!
 *  查看缓存是否存在 */
inline static BOOL _SJAudioCacheExistsWithURLStr(NSString *URLStr) { return [[NSFileManager defaultManager] fileExistsAtPath:_SJAudioCachePathWithURLStr(URLStr)];}

/*!
 *  根据文件路径查看缓存是否存在 */
inline static BOOL _SJCacheExistsWithFileURLStr(NSString *fileURLStr) {
    if ( [fileURLStr hasPrefix:@"file://"] ) fileURLStr = [fileURLStr substringFromIndex:7];
    NSString *dataName = fileURLStr.lastPathComponent;
    if ( !dataName ) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:[_SJAudioCacheFolderPath() stringByAppendingPathComponent:dataName]];
}

/**
 *  Root Folder */
inline static void _SJCreateFolder() {
    
    NSString *cacheFolder = _SJAudioCacheFolderPath();
    if ( !_SJFolderExists(cacheFolder) ) [[NSFileManager defaultManager] createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *tmpFolder = _SJAudioDownloadingTmpFolder();
    if ( !_SJFolderExists(tmpFolder) ) [[NSFileManager defaultManager] createDirectoryAtPath:tmpFolder withIntermediateDirectories:YES attributes:nil error:nil];
}

inline static NSArray<NSString *> *_SJContentsOfPath(NSString *path) {
    NSArray *paths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    NSMutableArray<NSString *> *itemPaths = [NSMutableArray new];
    [paths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [itemPaths addObject:[path stringByAppendingPathComponent:obj]];
    }];
    return itemPaths;
}

inline static NSArray<NSString *> *_SJCacheItemPaths() { return _SJContentsOfPath(_SJAudioCacheFolderPath());}




#pragma mark -

@interface NSURLSessionTask (SJMP3PlayerAdd)

@property (nonatomic, strong, readwrite) NSOutputStream *outputStream;
@property (nonatomic, strong, readonly) NSString *requestURLStr;
@property (nonatomic, strong, readonly) NSString *tmpPath;
@property (nonatomic, assign, readwrite) long long totalSize;
@property (nonatomic, assign, readwrite) long long downloadSize;
@property (nonatomic, assign, readonly) float downloadProgress;

@end

@implementation NSURLSessionTask (SJMP3PlayerAdd)

- (void)setOutputStream:(NSOutputStream *)outputStream {
    objc_setAssociatedObject(self, @selector(outputStream), outputStream, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSOutputStream *)outputStream {
    return objc_getAssociatedObject(self, _cmd);
}

- (NSString *)requestURLStr {
    return [self.currentRequest.URL absoluteString];
}

- (NSString *)tmpPath {
    return _SJAudioDownloadingTmpPath([self requestURLStr]);
}

- (long long)totalSize {
    return [objc_getAssociatedObject(self, _cmd) longLongValue];
}

- (void)setTotalSize:(long long)totalSize {
    objc_setAssociatedObject(self, @selector(totalSize), @(totalSize), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (long long)downloadSize {
    return [objc_getAssociatedObject(self, _cmd) longLongValue];
}

- (void)setDownloadSize:(long long)downloadSize {
    objc_setAssociatedObject(self, @selector(downloadSize), @(downloadSize), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (float)downloadProgress {
    if ( 0 == self.totalSize ) return 0;
    return self.downloadSize * 1.0f / self.totalSize;
}

@end





#pragma mark -









@interface NSTimer (SJMP3PlayerAdd)

+ (NSTimer *)SJMP3Player_scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer * _Nonnull timer))block;

@end

@implementation NSTimer (SJMP3PlayerAdd)

+ (NSTimer *)SJMP3Player_scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer * _Nonnull))block {
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(SJMP3Player_exeBlock:) userInfo:[block copy] repeats:repeats];
    return timer;
}

+ (void)SJMP3Player_exeBlock:(NSTimer *)timer {
    void (^block)(NSTimer * _Nonnull block) = timer.userInfo;
    if ( block ) block(timer);
}

@end




#pragma mark -


@interface SJMP3Player (NSURLSessionDelegateMethos) <NSURLSessionDelegate>

/*!
 *  到达播放点 */
@property (nonatomic, assign, readwrite) BOOL isStartPlaying;

/*!
 *  下载完毕 */
@property (nonatomic, assign, readwrite) BOOL isDownloaded;

@end


#pragma mark -

@interface SJMP3Player (AVAudioPlayerDelegateMethods) <AVAudioPlayerDelegate>
@end



#pragma mark -


@interface SJMP3Player ()

@property (nonatomic, strong, readwrite) AVAudioPlayer *audioPlayer;

@property (nonatomic, strong, readonly)  NSURLSession *audioCacheSession;

@property (nonatomic, strong, readonly) NSTimer *checkAudioTimeTimer;

@property (nonatomic, strong, readonly) NSTimer *checkAudioIsPlayingTimer;

@property (nonatomic, assign, readwrite) BOOL userClickedPause;

@property (nonatomic, strong, readonly) NSOperationQueue *oprationQueue;

@property (nonatomic, strong, readwrite) NSString *currentPlayingURLStr;

@property (nonatomic, strong, readwrite) NSURLSessionDataTask *currentTask;

@end





@implementation SJMP3Player

@synthesize audioCacheSession = _audioCacheSession;
@synthesize checkAudioTimeTimer = _checkAudioTimeTimer;
@synthesize oprationQueue = _oprationQueue;
@synthesize checkAudioIsPlayingTimer = _checkAudioIsPlayingTimer;

// MARK: Init

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    [self _SJMP3PlayerInitialize];
    [self _SJMP3PlayerAddObservers];
    return self;
}

- (void)dealloc {
    [self _SJRemoveObservers];
    [self _SJClearTimer];
}

// MARK: Public

/**
 *  播放状态
 */
- (BOOL)playStatus {
    return self.audioPlayer.isPlaying;
}


/**
 *  初始化
 */
+ (instancetype)player {
    return [self new];
}

/**
 *  播放
 */
- (void)playAudioWithPlayURL:(NSString *)playURL {
    if ( nil == playURL || 0 == playURL.length ) return;
    __weak typeof(self) _self = self;
    [self.oprationQueue addOperationWithBlock:^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) [self.delegate audioPlayer:self currentTime:0 reachableTime:0 totalTime:0];
        });
        
        [self stop];
        
        self.userClickedPause = NO;
        
        self.currentPlayingURLStr = playURL;
        
        self.isStartPlaying = NO;
        
        if ( _SJAudioCacheExistsWithURLStr(playURL) || [[NSURL URLWithString:playURL] isFileURL] ) {
            [self _SJPlayLocalCacheWithURLStr:playURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( ![self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] ) return;
                [self.delegate audioPlayer:self audioDownloadProgress:1];
            });
        }
        else {
            [self _SJStartDownloadWithURLStr:playURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( ![self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] ) return;
                [self.delegate audioPlayer:self audioDownloadProgress:0];
            });
        }
    }];
}

/**
 *  从指定的进度播放
 */
- (void)setPlayProgress:(float)progress {
    if ( !self.audioPlayer ) return;
    
    NSTimeInterval reachableTime = 0;
    if ( self.currentTask ) reachableTime = self.audioPlayer.duration * self.currentTask.downloadProgress;
    else reachableTime = self.audioPlayer.duration;
    
    if ( self.audioPlayer.duration * progress <= reachableTime ) self.audioPlayer.currentTime = self.audioPlayer.duration * progress;
    
    [self _SJEnableTimer];
}

/**
 *  暂停
 */
- (void)pause {
    
    self.userClickedPause = YES;
    
    [self.audioPlayer pause];
    
    [self _SJClearTimer];
}

/**
 *  恢复播放
 */
- (void)resume {
    
    self.userClickedPause = NO;
    
    if ( self.audioPlayer.isPlaying ) return;
    
    if ( nil == self.audioPlayer ) {
        [self playAudioWithPlayURL:self.currentPlayingURLStr];
    }
    else {
        if ( ![self.audioPlayer prepareToPlay] ) return;
        [self.audioPlayer play];
    }
    [self _SJEnableTimer];
}

/**
 *  停止播放, 停止缓存
 */
- (void)stop {
    self.userClickedPause = YES;
    self.isStartPlaying = NO;
    [self _SJClearMemoryCache];
    [self _SJClearTimer];
    [_audioPlayer stop];
    _audioPlayer = nil;
}

/**
 *  清除本地缓存
 */
- (void)clearDiskAudioCache {
    if ( self.audioPlayer ) [self stop];
    
    if ( _SJAudioCacheFolderPath() )
        [_SJCacheItemPaths() enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [[NSFileManager defaultManager] removeItemAtPath:obj error:nil];
        }];
}

/**
 *  已缓存的大小
 */
- (NSInteger)diskAudioCacheSize {
    
    __block NSInteger size = 0;
    if ( _SJAudioCacheFolderPath() ) {
        [_SJCacheItemPaths() enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary<NSFileAttributeKey, id> *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:obj error:nil];
            size += [dict[NSFileSize] integerValue] / 1000 / 1000;
        }];
    }
    return size;
}

/*!
 *  查看音乐是否已缓存
 */
- (BOOL)checkMusicHasBeenCachedWithPlayURL:(NSString *)playURL {
    return _SJAudioCacheExistsWithURLStr(playURL);
}

// MARK: Observers

- (void)_SJMP3PlayerAddObservers {
    [self addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)_SJRemoveObservers {
    [self removeObserver:self forKeyPath:@"rate"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if ( object != self ) { return;}
    
    if ( [keyPath isEqualToString:@"rate"] ) self.audioPlayer.rate = self.rate;
}

// MARK: Private

- (void)_SJClearTimer {
    [_checkAudioTimeTimer invalidate];
    _checkAudioTimeTimer = nil;
    [_checkAudioIsPlayingTimer invalidate];
    _checkAudioIsPlayingTimer = nil;
}

- (void)_SJEnableTimer {
    [self checkAudioTimeTimer];
    [self checkAudioIsPlayingTimer];
}

- (void)_SJMP3PlayerInitialize {
    
    _SJCreateFolder();
    
    self.rate = 1;
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive: YES error: nil];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
}

/**
 *  定时器事件
 */
- (void)_SJCheckAudioTime {
    if ( !_audioPlayer.isPlaying ) return;
    NSTimeInterval currentTime = _audioPlayer.currentTime;
    NSTimeInterval totalTime = _audioPlayer.duration;
    NSTimeInterval reachableTime = _audioPlayer.duration * self.currentTask.downloadProgress;
    if ( ![_delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate audioPlayer:self currentTime:currentTime reachableTime:reachableTime totalTime:totalTime];
    });
}

// MARK: 因为网络环境差 而导致的暂停播放 处理
static BOOL delay;
- (void)_SJCheckAudioIsPlayingTimer {
    if ( self.userClickedPause ) return;
    if ( self.audioPlayer.isPlaying ) return;
    if ( delay ) return;
    delay = YES;
    // 如果暂停,  ? 秒后 再次初始化
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SJAudioDelayTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        delay = NO;
        if ( self.userClickedPause ) return;
        if ( self.audioPlayer.isPlaying ) return;
        /*!
         *  再次初始化 */
        NSString *itemTmpPath = self.currentTask.tmpPath;
        NSURL *filePathURL = nil;
        
        if ( itemTmpPath ) filePathURL = [NSURL fileURLWithPath:itemTmpPath];
        
        if ( filePathURL ) [self _SJPlayWithFileURL:filePathURL];
    });
}

- (void)_SJPlayLocalCacheWithURLStr:(NSString *)URLStr {
    self.isDownloaded = YES;
    NSURL *contentsURL = nil;
    if ( [URLStr hasPrefix:@"file"] )
        contentsURL = [NSURL URLWithString:URLStr];
    else contentsURL = [NSURL fileURLWithPath:_SJAudioCachePathWithURLStr(URLStr)];
    [self _SJPlayWithFileURL:contentsURL];
}

// MARK:  播放缓存音乐

- (void)_SJPlayWithFileURL:(NSURL *)fileURL {
    
    @synchronized (self) {
        
        NSError *error = nil;
        
        NSTimeInterval currentTime = self.audioPlayer.currentTime;
        
        AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL fileTypeHint:AVFileTypeMPEGLayer3 error:&error];
        
        if ( error ) {
            
            if ( self.enableDBUG ) {
                NSLog(@"\n-播放器初始化失败-%@-%@ \n", error, fileURL);
            }
            NSString *fileURLStr = fileURL.absoluteString;
            if ( [fileURLStr hasPrefix:@"file://"] ) fileURLStr = [fileURLStr substringFromIndex:7];
            if ( _SJCacheExistsWithFileURLStr(fileURLStr) ) {
                if ( [[NSFileManager defaultManager] removeItemAtPath:fileURLStr error:nil] ) {
                    if ( self.enableDBUG ) {
                        NSLog(@"\n-播放失败, 已删除下载文件-%@ \n", fileURLStr);
                    }
                }
            }
            return;
        }
        
        if ( !audioPlayer ) return;
        
        audioPlayer.enableRate = YES;
        
        if ( ![audioPlayer prepareToPlay] ) return;
        
        audioPlayer.delegate = self;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _SJEnableTimer];
        });
        
        if ( !self.isDownloaded && audioPlayer.duration < 5 ) return;
        
        [audioPlayer play];
        if ( 0 != currentTime ) audioPlayer.currentTime = currentTime;
        audioPlayer.rate = self.rate;
        self.audioPlayer = audioPlayer;
        self.isStartPlaying = YES;
        
        if ( self.enableDBUG ) {
            NSLog(@"\n-开始播放\n-持续时间: %f 秒\n-播放地址为: %@ ",
                  audioPlayer.duration,
                  fileURL);
            NSLog(@"\n-线程: %@", [NSThread currentThread]);
            if ( [[UIDevice currentDevice].systemVersion integerValue] >= 10 ) {
                NSLog(@"\n-格式%@", audioPlayer.format);
            }
        }
    }
}

// MARK: 下载任务初始化

- (void)_SJStartDownloadWithURLStr:(NSString *)URLStr {
    
    if ( !URLStr ) return;
    
    NSURL *URL = [NSURL URLWithString:URLStr];
    
    if ( !URL ) return;
    
    [self _SJClearBeforeDownloadTask];
    
    NSURLSessionDataTask *task = [self.audioCacheSession dataTaskWithRequest:[NSURLRequest requestWithURL:URL]];;
    
    if ( !task ) return;
    
    _currentTask = task;
    
    [task resume];
    
    if ( self.enableDBUG ) {
        NSLog(@"\n准备下载: %@ \n" , URLStr);
    }
    self.isDownloaded = NO;
}

- (void)_SJClearBeforeDownloadTask {
    [_currentTask.outputStream close];
    _currentTask.outputStream = nil;
    [_currentTask cancel];
    _currentTask = nil;
}


/*!
 *  获取当前的下载路径 */
- (NSString *)_SJMP3PlayerCurrentTmpItemPath {
    return objc_getAssociatedObject(self.currentTask, [NSString stringWithFormat:@"%zd", self.currentTask.taskIdentifier].UTF8String);
}

- (void)_SJClearMemoryCache {
    [_currentTask cancel];
    _currentTask = nil;
    _currentPlayingURLStr = nil;
}

// MARK: Getter

- (NSURLSession *)audioCacheSession {
    if ( nil == _audioCacheSession ) {
        NSURLSessionConfiguration *cofig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:SJMP3PlayerDownloadAudioIdentifier];
        _audioCacheSession = [NSURLSession sessionWithConfiguration:cofig delegate:self delegateQueue:self.oprationQueue];
    }
    return _audioCacheSession;
}

- (NSOperationQueue *)oprationQueue {
    if ( nil == _oprationQueue ) {
        _oprationQueue = [NSOperationQueue new];
        _oprationQueue.maxConcurrentOperationCount = 1;
        _oprationQueue.name = @"com.dancebaby.lanwuzhe.audioCacheSessionOprationQueue";
    }
    return _oprationQueue;
}

- (NSTimer *)checkAudioTimeTimer {
    if ( nil == _checkAudioTimeTimer) {
        __weak typeof(self) _self = self;
        _checkAudioTimeTimer = [NSTimer SJMP3Player_scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [self _SJCheckAudioTime];
        }];
        [_checkAudioTimeTimer fire];
    }
    return _checkAudioTimeTimer;
}

- (NSTimer *)checkAudioIsPlayingTimer {
    if ( _checkAudioIsPlayingTimer ) return _checkAudioIsPlayingTimer;
    __weak typeof(self) _self = self;
    _checkAudioIsPlayingTimer = [NSTimer SJMP3Player_scheduledTimerWithTimeInterval:SJAudioDelayTime repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self _SJCheckAudioIsPlayingTimer];
    }];
    [_checkAudioIsPlayingTimer fire];
    return _checkAudioIsPlayingTimer;
}

@end



// MARK: Session Delegate
/* 保持只有一个任务在下载 */
@implementation SJMP3Player (NSURLSessionDelegateMethos)

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    self.isDownloaded = NO;
    dataTask.outputStream = [NSOutputStream outputStreamToFileAtPath:dataTask.tmpPath append:NO];
    [dataTask.outputStream open];
    dataTask.totalSize = response.expectedContentLength;
    dataTask.downloadSize = 0;
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if ( 0 == data.length ) return;
    dataTask.downloadSize += data.length;
    [dataTask.outputStream write:data.bytes maxLength:data.length];
    
    if ( self.enableDBUG ) {
        NSLog(@"\n-%@\n-写入大小: %zd - 文件大小: %zd - 下载进度: %f \n",
              dataTask.requestURLStr,
              dataTask.totalSize,
              dataTask.downloadSize,
              dataTask.downloadProgress);
    }
    
    if ( [self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] )
        [self.delegate audioPlayer:self audioDownloadProgress:dataTask.downloadProgress];
    
    if ( self.userClickedPause ) return;
    
    if ( !self.isStartPlaying && (dataTask.downloadProgress > SJAudioWhenToStartPlaying) ) {
        [self _SJReadyPlayDownloadingAudio:dataTask];
    }
    
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask didCompleteWithError:(NSError *)error {
    
    if ( self.enableDBUG ) {
        if ( error.code == NSURLErrorCancelled ) {
            NSLog(@"下载被取消");
            return;
        }
        
        if ( error ) {
            NSLog(@"\n-下载报错: %@", error);
            return;
        }
    }
    
    NSString *URLStr = dataTask.currentRequest.URL.absoluteString;
    
    if ( self.enableDBUG ) {
        NSLog(@"\n-下载完成: %@", URLStr);
    }
    
    self.isDownloaded = YES;
    
    NSString *cachePath = _SJAudioCachePathWithURLStr(URLStr);
    
    if ( !cachePath ) return;
    
    BOOL copyResult = [[NSFileManager defaultManager] copyItemAtPath:dataTask.tmpPath toPath:cachePath error:nil];
    
    if ( !copyResult ) return;
    
    if ( self.audioPlayer.isPlaying ) return;
    
    if ( self.userClickedPause ) return;
    
    NSURL *fileURL = [NSURL fileURLWithPath:cachePath];
    
    if ( !fileURL ) return;
    
    [self _SJPlayWithFileURL:fileURL];
}




#pragma mark -

// MARK: 记录 到达播放点

- (BOOL)isStartPlaying {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setIsStartPlaying:(BOOL)isStartPlaying {
    objc_setAssociatedObject(self, @selector(isStartPlaying), @(isStartPlaying), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)isDownloaded {
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setIsDownloaded:(BOOL)isDownloaded {
    objc_setAssociatedObject(self, @selector(isDownloaded), @(isDownloaded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// MARK: 准备播放

- (void)_SJReadyPlayDownloadingAudio:(NSURLSessionDataTask *)task {
    
    if ( self.audioPlayer.isPlaying ) return;
    
    NSString *ItemPath = task.tmpPath;
    
    if ( !ItemPath ) return;
    
    NSURL *fileURL = [NSURL fileURLWithPath:ItemPath];
    
    if ( !fileURL ) return;
    
    if ( self.enableDBUG ) {
        NSLog(@"\n-准备完毕 开始播放 \n-%@ \n", task.response.URL);
    }
    
    [self _SJPlayWithFileURL:fileURL];
}

@end

// MARK: 播放完毕

@implementation SJMP3Player (AVAudioPlayerDelegateMethods)

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    
    if ( [self.currentPlayingURLStr hasPrefix:@"http"] ) {
        /*!
         *  如果未下载完毕 */
        if ( !self.isDownloaded ) return;
    }
    
    if ( self.enableDBUG ) {
        NSLog(@"\n-播放完毕\n-播放地址:%@", player.url);
    }
    
    [self _SJClearMemoryCache];
    
    if ( ![self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:)] ) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate audioPlayerDidFinishPlaying:self];
    });
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player {
    if ( self.audioPlayer.isPlaying ) [self pause];
}

-(void)audioPlayerEndInterruption:(AVAudioPlayer *)player withOptions:(NSUInteger)flags {
    
    if ( ![self.audioPlayer prepareToPlay] ) return;
    
    [self.audioPlayer play];
}

@end

