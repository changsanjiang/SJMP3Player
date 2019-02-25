//
//  SJMP3Player.m
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "SJMP3Player.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import "NSTimer+SJMP3PlayerAdd.h"
#import "SJMP3PlayerPrefetcher.h"
#import "SJMP3FileManager.h"
#import "SJMP3DurationLoader.h"

#if __has_include(<SJObserverHelper/NSObject+SJObserverHelper.h>)
#import <SJObserverHelper/NSObject+SJObserverHelper.h>
#import <SJDownloadDataTask/SJDownloadDataTask.h>
#else
#import "NSObject+SJObserverHelper.h"
#import "SJDownloadDataTask.h"
#endif

NS_ASSUME_NONNULL_BEGIN
#define SJMP3Player_SafeExeMethod(__obj__) \
if ( [NSThread currentThread] != _onThread ) { \
    [self performSelector:_cmd onThread:_onThread withObject:__obj__ waitUntilDone:NO]; \
    return; \
}

/// 文件来源
///
/// - SJMP3PlayerFileSourceUnknown:         未知
/// - SJMP3PlayerFileSourceLocal:           本地文件
/// - SJMP3PlayerFileSourceCache:           缓存文件(cache目录)
/// - SJMP3PlayerFileSourceTmpCache:        临时缓存文件(tmp目录)
///
typedef NS_ENUM(NSUInteger, SJMP3PlayerFileSource) {
    SJMP3PlayerFileSourceUnknown,
    SJMP3PlayerFileSourceLocal,
    SJMP3PlayerFileSourceCache,
    SJMP3PlayerFileSourceTmpCache,
};

#pragma mark
@interface SJMP3Player()<AVAudioPlayerDelegate>
// - player
@property (strong, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic) BOOL userClickedPause;
@property (nonatomic) BOOL isCheckingCurrentAudioIsFinishedPlaying;

// - task
@property (nonatomic, strong, nullable) SJMP3DurationLoader *durationLoader;
@property (nonatomic, strong, nullable) SJMP3FileManager *fileManager;
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property (strong, nullable) NSURL *currentURL;
@property (nonatomic) BOOL needDownload;
@property float downloadProgress;

// - timer
@property (nonatomic, strong, nullable) NSTimer *refreshTimeTimer;
@property (nonatomic, strong, nullable) NSTimer *tryToPlayTimer;

// - prefetcher
@property (nonatomic, strong, nullable) SJMP3FileManager *prefetcherFileManager;
@property (nonatomic, strong, readonly) SJMP3PlayerPrefetcher *prefetcher;

@property (nonatomic) SJMP3PlayerFileSource fileOrigin;
@property (nonatomic, strong, readonly) NSThread *onThread;
@end

@implementation SJMP3Player
+ (instancetype)player {
    return [self new];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_task cancel];
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _onThread = [SJMP3Player onThread];
    _rate = 1;
    _volume = 1;
    _prefetcher = [SJMP3PlayerPrefetcher new];

    [self _initializeRemoteCommandHandler];
    [self _activateAudioSession];
    [self _observerInterruptionNotification];
    return self;
}

- (void)_initializeRemoteCommandHandler {
    _remoteCommandHandler = [SJRemoteCommandHandler new];
    __weak typeof(self) _self = self;
    _remoteCommandHandler.pauseCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self pause];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] )
            [self.delegate remoteEventPausedForAudioPlayer:self];
    };
    _remoteCommandHandler.playCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self resume];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPlayedForAudioPlayer:)] )
            [self.delegate remoteEventPlayedForAudioPlayer:self];
    };
    _remoteCommandHandler.previousCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( [self.delegate respondsToSelector:@selector(remoteEvent_PreWithAudioPlayer:)] )
            [self.delegate remoteEvent_PreWithAudioPlayer:self];
    };
    _remoteCommandHandler.nextCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( [self.delegate respondsToSelector:@selector(remoteEvent_NextWithAudioPlayer:)] )
            [self.delegate remoteEvent_NextWithAudioPlayer:self];
    };
    _remoteCommandHandler.seekToTimeCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler, NSTimeInterval secs) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self seekToTime:secs];
    };
}

- (void)_observerInterruptionNotification {
    SJMP3Player_SafeExeMethod(nil);
    [self sj_observeWithNotification:AVAudioSessionInterruptionNotification target:AVAudioSession.sharedInstance usingBlock:^(SJMP3Player * _Nonnull self, NSNotification * _Nonnull note) {
        NSDictionary *info = note.userInfo;
        if( (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan ) {
            [self pause];
            if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] )
                [self.delegate remoteEventPausedForAudioPlayer:self];
        }
    }];
}

- (void)_activateAudioSession {
    SJMP3Player_SafeExeMethod(nil);
    NSError *error = NULL;
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Failed to set active audio session! error: %@", error);
    }
    
    if ( AVAudioSession.sharedInstance.category != AVAudioSessionCategoryPlayback ||
         AVAudioSession.sharedInstance.category != AVAudioSessionCategoryPlayAndRecord ) {
        NSError *error = nil;
        // 使播放器在静音状态下也能放出声音
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        if ( error ) NSLog(@"%@", error.userInfo);
    }
}

#pragma mark -
@synthesize mute = _mute;
- (void)setMute:(BOOL)mute {
    @synchronized (self) {
        _mute = mute;
    }
    self.audioPlayer.volume = mute?0.001:self.volume;
}
- (BOOL)mute {
    @synchronized (self) {
        return _mute;
    }
}

@synthesize volume = _volume;
- (void)setVolume:(float)volume {
    @synchronized (self) {
        _volume = volume;
    }

    self.audioPlayer.volume = volume;
}
- (float)volume {
    @synchronized (self) {
        return _volume;
    }
}

@synthesize rate = _rate;
- (void)setRate:(float)rate {
    if ( isnan(rate) ) return;
    _rate = rate;
    if ( [self.audioPlayer prepareToPlay] ) self.audioPlayer.rate = rate;
}
- (float)rate {
    @synchronized (self) {
        return _rate;
    }
}

- (NSTimeInterval)currentTime {
    return self.audioPlayer.currentTime;
}

- (NSTimeInterval)duration {
    return self.audioPlayer.duration;
}

- (BOOL)isPlaying {
    return self.audioPlayer.isPlaying;
}

- (void)seekToTime:(NSTimeInterval)secs {
    [self _seekToTime:@(secs)];
}

- (void)_seekToTime:(NSNumber *)s {
    SJMP3Player_SafeExeMethod(s);
    NSTimeInterval secs = [s doubleValue];
    if ( isnan(secs) ) return;
    if ( ![self.audioPlayer prepareToPlay] ) return;
    if ( self.audioPlayer.duration == 0 ) return;
    if ( self.needDownload && (secs / self.audioPlayer.duration > self.downloadProgress) ) return;
    self.audioPlayer.currentTime = secs;
    [self resume];
}

- (void)pause {
    SJMP3Player_SafeExeMethod(nil);
    self.userClickedPause =  YES;
    [self.audioPlayer pause];
    [self _clearRefreshTimeTimer];
    [self _clearPlayTmpFileTimer];
}

- (void)resume {
    SJMP3Player_SafeExeMethod(nil);
    AVAudioPlayer *player = self.audioPlayer;
    [player play];
    player.rate = self.rate;
    player.volume = self.mute?0:self.volume;
    self.userClickedPause = NO;
    [self _setPlayInfo];
    [self _activateRefreshTimeTimer];
}

- (void)stop {
    SJMP3Player_SafeExeMethod(nil);
    self.fileManager = nil;
    self.durationLoader = nil;

    if ( self.audioPlayer ) {
        [self.audioPlayer stop];
        self.audioPlayer = nil;
    }
    self.userClickedPause = NO;
    if ( self.task ) {
        [self.task cancel];
        self.task = nil;
    }
    self.needDownload = NO;
    self.downloadProgress = 0;
    self.fileOrigin = SJMP3PlayerFileSourceUnknown;
    [self _clearRefreshTimeTimer];
    [self _clearPlayTmpFileTimer];
    [self _playbackTimeDidChange];
}

- (void)clearDiskAudioCache {
    SJMP3Player_SafeExeMethod(nil);
    if ( self.isPlaying ) [self stop];
    [SJMP3FileManager clear];
}

- (long long)diskAudioCacheSize {
    return [SJMP3FileManager size];
}

/*!
 *  查看音乐是否已缓存 */
- (BOOL)isCached:(NSURL *)URL {
    return [SJMP3FileManager fileExistsForURL:URL];
}

#pragma mark

- (void)playWithURL:(NSURL *)URL {
    SJMP3Player_SafeExeMethod(URL);
    [self stop];
    if ( !URL ) return;
    self.currentURL = URL;
    self.fileManager = [[SJMP3FileManager alloc] initWithURL:URL];
    
    if ( URL.isFileURL ) {
        self.durationLoader = [[SJMP3DurationLoader alloc] initWithURL:URL];
        [self _play:[NSData dataWithContentsOfURL:URL] source:SJMP3PlayerFileSourceLocal];
        [self _downloadIsFinished];
        [self _tryToPrefetchNextAudio];
    }
    else if ( [SJMP3FileManager fileExistsForURL:URL] ) {
        NSURL *fileURL = [NSURL fileURLWithPath:[SJMP3FileManager filePathForURL:URL]];
        self.durationLoader = [[SJMP3DurationLoader alloc] initWithURL:fileURL];
        [self _play:[NSData dataWithContentsOfURL:fileURL] source:SJMP3PlayerFileSourceCache];
        [self _downloadIsFinished];
        [self _tryToPrefetchNextAudio];
    }
    else {
        self.needDownload = YES;
        self.durationLoader = [[SJMP3DurationLoader alloc] initWithURL:URL];
        [self _needDownloadCurrentAudio];
    }
}

#pragma mark downlaod

- (void)_needDownloadCurrentAudio {
    SJMP3Player_SafeExeMethod(nil);
    NSURL *_Nullable URL = self.fileManager.URL;
    NSURL *_Nullable tmpURL = self.fileManager.tmpURL;
    
    if ( !URL || !tmpURL )
        return;
    
    __weak typeof(self) _self = self;
    // 取消预缓存, 等待当前任务下载完成
    [self _cancelPrefetch];
    self.task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:tmpURL append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
        _self.downloadProgress = progress;
    } success:^(SJDownloadDataTask * _Nonnull dataTask) {
        [_self _downloadIsFinished];
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        [_self _downloadIsFailure];
    }];

    #ifdef DEBUG
    printf("\n- SJMP3Player: 准备缓存, URL: %s, 临时缓存地址: %s \n", URL.description.UTF8String, tmpURL.description.UTF8String);
    #endif
    
    [self _activatePlayTmpFileTimer];
}

@synthesize downloadProgress = _downloadProgress;
- (void)setDownloadProgress:(float)progress {
    @synchronized (self) {
        _downloadProgress = progress;
    }
    
    __weak typeof(self) _self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] )
            [self.delegate audioPlayer:self audioDownloadProgress:progress];
    });
}
- (float)downloadProgress {
    @synchronized (self) {
        return _downloadProgress;
    }
}

- (void)_downloadIsFinished {
    SJMP3Player_SafeExeMethod(nil);
    [self _clearPlayTmpFileTimer];
    self.downloadProgress = 1;
    [self.fileManager saveTmpItemToFilePath];
    // check data length
    if ( self.task.totalSize != self.audioPlayer.data.length ) {
        #ifdef DEBUG
        printf("\n- SJMP3Player: 下载完毕, 即将重新初始化播放器");
        #endif
        [self _play:self.fileManager.fileData
             source:SJMP3PlayerFileSourceCache
        currentTime:self.audioPlayer.currentTime];
    }

    self.task = nil;
    [self _tryToPrefetchNextAudio];
}

- (void)_downloadIsFailure {
    SJMP3Player_SafeExeMethod(nil);
    #ifdef DEBUG
    printf("\n- SJMP3Player: 下载失败, 将会在3秒后重启下载. URL: %s \n", self.task.URLStr.UTF8String);
    #endif
    
    SJDownloadDataTaskIdentitifer iden = self.task.identifier;
    // restart after 3 secs
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( self.task.identifier == iden ) [self.task restart];
    });
}

- (BOOL)isDownloaded {
    return [SJMP3FileManager fileExistsForURL:self.currentURL];
}

- (void)_cancelPrefetch {
    SJMP3Player_SafeExeMethod(nil);
    _prefetcherFileManager = nil;
    [_prefetcher cancel];
}

- (void)_tryToPrefetchNextAudio {
    SJMP3Player_SafeExeMethod(nil);
    NSURL *previousURL = nil, *nextURL = nil, *preURL = nil;

    if ( [self.delegate respondsToSelector:@selector(prefetchURLOfPreviousAudio)] ) {
        previousURL = self.delegate.prefetchURLOfPreviousAudio;
    }
    
    if ( [self.delegate respondsToSelector:@selector(prefetchURLOfNextAudio)] ) {
        nextURL = self.delegate.prefetchURLOfNextAudio;
    }
    
    if ( nextURL && !nextURL.isFileURL && ![SJMP3FileManager fileExistsForURL:nextURL] ) {
        preURL = nextURL;
    }
    else if ( previousURL && !previousURL.isFileURL && ![SJMP3FileManager fileExistsForURL:previousURL] ) {
        preURL = previousURL;
    }
    
    if ( !preURL ) return;
    
    _prefetcherFileManager = [[SJMP3FileManager alloc] initWithURL:preURL];
    NSURL *tmpURL = _prefetcherFileManager.tmpURL;
    #ifdef DEBUG
    printf("\n- SJMP3Player: 准备进行预缓存: URL: %s, 临时缓存地址: %s \n", preURL.description.UTF8String, tmpURL.description.UTF8String);
    #endif
    
    __weak typeof(self) _self = self;
    [_prefetcher prefetchAudioForURL:preURL toPath:tmpURL completionHandler:^(SJMP3PlayerPrefetcher * _Nonnull prefetcher, BOOL finished) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( finished ) {
            [self _prefetchIsFinished];
        }
        else {
            [self _prefetchIsFailure];
        }
    }];
}

- (void)_prefetchIsFinished {
    SJMP3Player_SafeExeMethod(nil);
    #ifdef DEBUG
    printf("\n- SJMP3Player: 预加载成功: URL: %s, tmp地址: %s \n", _prefetcherFileManager.URL.description.UTF8String, _prefetcherFileManager.tmpPath.description.UTF8String);
    #endif
    [_prefetcherFileManager saveTmpItemToFilePath];
    [self _tryToPrefetchNextAudio];
}

- (void)_prefetchIsFailure {
    SJMP3Player_SafeExeMethod(nil);
    NSURL *URL = self.prefetcherFileManager.URL;
    #ifdef DEBUG
    printf("\n- SJMP3Player: 预加载失败: URL: %s, 将会在3秒后重启下载 \n", URL.description.UTF8String);
    #endif
    __weak typeof(self) _self = self;
    // restart after 3 secs
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( [self.prefetcherFileManager.URL isEqual:URL] )
            [self.prefetcher restart];
    });
}

#pragma mark play file
/// 清除播放临时文件的timer
- (void)_clearPlayTmpFileTimer {
    SJMP3Player_SafeExeMethod(nil);
    if ( _tryToPlayTimer ) {
        [_tryToPlayTimer invalidate];
        _tryToPlayTimer = nil;
    }
}

/// 激活播放临时文件的Timer
- (void)_activatePlayTmpFileTimer {
    SJMP3Player_SafeExeMethod(nil);
    if ( !_tryToPlayTimer ) {
        __weak typeof(self) _self = self;
        _tryToPlayTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.5 block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return ;
            }
            [self _playTmpFileIfNeeded];
        } repeats:YES];
        [_tryToPlayTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_tryToPlayTimer.timeInterval]];
        [NSRunLoop.mainRunLoop addTimer:_tryToPlayTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)_playTmpFileIfNeeded {
    SJMP3Player_SafeExeMethod(nil);
    if ( self.audioPlayer.isPlaying ) {
        [self _clearPlayTmpFileTimer];
        return;
    }
    
    if ( self.userClickedPause ) {
        return;
    }
    
    if ( self.task.wroteSize < 1024 * 500 ) {
        return;
    }
    
    #ifdef DEBUG
    printf("\n- SJMP3Player: 尝试播放临时文件 \n");
    #endif
    [self _play:self.fileManager.tmpData source:SJMP3PlayerFileSourceTmpCache];
}

- (void)_play:(NSData *)data source:(SJMP3PlayerFileSource)origin {
    [self _play:data source:origin currentTime:0];
}
- (void)_play:(NSData *)data source:(SJMP3PlayerFileSource)origin currentTime:(NSTimeInterval)currentTime {
    if ( !data )
        return;
    
    if ( isinf(currentTime) || isnan(currentTime) ) {
        currentTime = 0;
    }
    
    self.audioPlayer = nil;
    #ifdef DEBUG
    switch ( origin ) {
        case SJMP3PlayerFileSourceUnknown: break;
        case SJMP3PlayerFileSourceLocal:
            printf("\n- SJMP3Player: 此次将播放`本地文件`, URL: %s\n", self.currentURL.description.UTF8String);
            break;
        case SJMP3PlayerFileSourceCache:
            printf("\n- SJMP3Player: 此次将播放`缓存文件`, URL: %s\n", self.currentURL.description.UTF8String);
            break;
        case SJMP3PlayerFileSourceTmpCache:
            printf("\n- SJMP3Player: 此次将播放`临时缓存文件`, URL: %s\n", self.currentURL.description.UTF8String);
            break;
    }
    #endif
    
    self.fileOrigin = origin;
    NSError *error = nil;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithData:data fileTypeHint:AVFileTypeMPEGLayer3 error:&error];
 
    if ( error ) {
        if ( [SJMP3FileManager fileExistsForURL:self.currentURL] ) {
            [SJMP3FileManager deleteForURL:self.currentURL];
            #ifdef DEBUG
            printf("\n- SJMP3Player: 播放失败, 已删除下载的文件 \n");
            #endif
        }
        
        #ifdef DEBUG
        printf("\n- SJMP3Player: 播放器初始化失败, Error: %s \n", error.description.UTF8String);
        #endif
        return;
    }
    audioPlayer.enableRate = YES;
    if ( !audioPlayer || ![audioPlayer prepareToPlay] ) {
        return;
    }
    audioPlayer.delegate = self;
    self.audioPlayer = audioPlayer;
    if ( !self.userClickedPause ) {
        [self resume];
        
        #ifdef DEBUG
        printf("\n- SJMP3Player: 开始播放: 当前时间: %f 秒 - %s, 持续时间: %f 秒 \n", currentTime, audioPlayer.description.UTF8String, audioPlayer.duration);
        if ( @available(ios 10, *) ) printf("\n- SJMP3Player: 格式%s \n", audioPlayer.format.description.UTF8String);
        printf("\n ------------------------------------ \n");
        #endif
    }
    else {
        [self pause];
    }
    audioPlayer.currentTime = currentTime;
    [self _clearPlayTmpFileTimer];
}

#pragma mark - delegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self _checkCurrentAudioIsFinishedPlaying];
}

- (void)_checkCurrentAudioIsFinishedPlaying {
    SJMP3Player_SafeExeMethod(nil);
    #ifdef DEBUG
    printf("\n- SJMP3Player: 正在确认音乐是否播放完毕 \n");
    #endif
    // checking
    self.isCheckingCurrentAudioIsFinishedPlaying = YES;

    [self _clearRefreshTimeTimer];
    AVAudioPlayer *player = self.audioPlayer;
    if ( self.task.totalSize == player.data.length ||
         self.fileOrigin != SJMP3PlayerFileSourceTmpCache ) {
        #ifdef DEBUG
        printf("\n- SJMP3Player: 已确认播放完毕, 播放地址:%s \n ", self.currentURL.description.UTF8String);
        #endif
        [self _playerDidFinishedPlaying];
    }
    else {
        #ifdef DEBUG
        printf("\n- SJMP3Player: 监测到音乐未播放完毕, 将重新初始化播放器 \n");
        #endif
        [self _play:self.fileManager.tmpData
             source:SJMP3PlayerFileSourceTmpCache
        currentTime:1.0 * player.data.length / self.task.totalSize * player.duration];
    }
    self.isCheckingCurrentAudioIsFinishedPlaying = NO;
}

- (void)_playerDidFinishedPlaying {
    if ( [self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:)] ) {
        __weak typeof(self) _self = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            [self.delegate audioPlayerDidFinishPlaying:self];
        });
    }
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
#ifdef DEBUG
    NSLog(@"SJMP3Player: %@", error);
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif
}


#pragma mark

- (void)_clearRefreshTimeTimer {
    SJMP3Player_SafeExeMethod(nil);
    if ( _refreshTimeTimer ) {
        [_refreshTimeTimer invalidate];
        _refreshTimeTimer = nil;
    }
}

- (void)_activateRefreshTimeTimer {
    SJMP3Player_SafeExeMethod(nil);
    if ( !_refreshTimeTimer ) {
        __weak typeof(self) _self = self;
        _refreshTimeTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.2 block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return ;
            }
            [self _playbackTimeDidChange];
        } repeats:YES];
        [_refreshTimeTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_refreshTimeTimer.timeInterval]];
        [[NSRunLoop mainRunLoop] addTimer:_refreshTimeTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)_setPlayInfo {
    SJMP3Player_SafeExeMethod(nil);
    if ( !self.audioPlayer ) return;
    if ( ![self.delegate respondsToSelector:@selector(playInfo)] ) return;
    SJMP3Info *info = [self.delegate playInfo];
    if ( !info ) return;
    NSMutableDictionary *mediaDict =
    @{
      MPMediaItemPropertyTitle:info.title?:@"",
      MPMediaItemPropertyMediaType:@(MPMediaTypeAnyAudio),
      MPMediaItemPropertyPlaybackDuration:@(self.audioPlayer.duration),
      MPNowPlayingInfoPropertyPlaybackRate:@(self.audioPlayer.rate),
      MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.audioPlayer.currentTime),
      MPMediaItemPropertyArtist:info.artist?:@"",
      MPMediaItemPropertyAlbumArtist:info.artist?:@"",
      }.mutableCopy;
    if ( info.cover ) {
        [mediaDict setValue:[[MPMediaItemArtwork alloc] initWithImage:info.cover]
                     forKey:MPMediaItemPropertyArtwork];
    }
    
    [MPNowPlayingInfoCenter.defaultCenter performSelectorOnMainThread:@selector(setNowPlayingInfo:) withObject:mediaDict waitUntilDone:NO];
}

- (void)_playbackTimeDidChange {
    SJMP3Player_SafeExeMethod(nil);
    if ( self.userClickedPause ) {
        [self _clearRefreshTimeTimer];
        return;
    }
    
    NSTimeInterval currentTime = self.audioPlayer.currentTime;
    NSTimeInterval totalTime = self.audioPlayer.duration;
    NSTimeInterval reachableTime = self.audioPlayer.duration * self.downloadProgress;
    __weak typeof(self) _self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( self.isCheckingCurrentAudioIsFinishedPlaying ) {
            return;
        }
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
            [self.delegate audioPlayer:self currentTime:currentTime reachableTime:reachableTime totalTime:totalTime];
        }
    });
}

#pragma mark -
/// refresh thread entry point.
+ (void)_onThreadMain:(id _Nullable)object {
    @autoreleasepool {
        NSThread *thread = [NSThread currentThread];
        [thread setName:@"com.SJMP3Player.workerThread"];
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSRunLoopCommonModes];
        [runLoop run];
    }
}

+ (NSThread *)onThread {
    static NSThread *thread;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thread = [[NSThread alloc] initWithTarget:self selector:@selector(_onThreadMain:) object:nil];
        thread.qualityOfService = NSQualityOfServiceUserInteractive;
        [thread start];
    });
    return thread;
}

#pragma mark - player properties
@end


@implementation SJMP3Info
- (instancetype)initWithTitle:(NSString *)title artist:(NSString *)artist cover:(UIImage *)cover {
    self = [super init];
    if ( !self ) return nil;
    _title = title;
    _artist = artist;
    _cover = cover;
    return self;
}
@end

NS_ASSUME_NONNULL_END
