//
//  SJMP3Player.m
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "SJMP3Player.h"
#import <SJDownloadDataTask/SJDownloadDataTask.h>
#import <AVFoundation/AVFoundation.h>
#import "NSTimer+SJMP3PlayerAdd.h"
#import <objc/message.h>
#import <MediaPlayer/MediaPlayer.h>
#import "SJMP3PlayerFileManager.h"
#import "SJMP3PlayerPrefetcher.h"

NS_ASSUME_NONNULL_BEGIN
#define SJMP3PlayerLock()   dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
#define SJMP3PlayerUnlock() dispatch_semaphore_signal(self->_lock);

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

@interface _SJMP3PlayerGetFileDuration: NSObject
- (instancetype)initWithURL:(NSURL *)fileURL loadDurationCallBlock:(void(^)(NSTimeInterval secs))block;
@end

@interface _SJMP3PlayerGetFileDuration()
@property (nonatomic, strong, readonly) AVAsset *asset;
@end
@implementation _SJMP3PlayerGetFileDuration
- (instancetype)initWithURL:(NSURL *)fileURL loadDurationCallBlock:(void(^)(NSTimeInterval secs))block {
    self = [super init];
    if ( !self ) return nil;
    _asset = [[AVURLAsset alloc] initWithURL:fileURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)}];
    __weak typeof(self) _self = self;
    [_asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( block ) block(CMTimeGetSeconds(self.asset.duration));
    }];
    return self;
}
- (void)dealloc {
    [_asset cancelLoading];
}
@end

#pragma mark

@interface SJMP3Player()<AVAudioPlayerDelegate>
@property (nonatomic, strong, readonly) SJMP3PlayerFileManager *fileManager;
@property (nonatomic, readonly) dispatch_queue_t serialQueue;
@property (nonatomic, readonly) BOOL isNeedToPlay;

@property (nonatomic, strong, nullable) NSTimer *refreshTimeTimer;
@property (nonatomic, strong, nullable) NSTimer *tryToPlayTimer;
@property (strong, nullable) AVAudioPlayer *audioPlayer;
@property (nonatomic) NSTimeInterval duration;

#pragma mark
@property (nonatomic, strong, nullable) _SJMP3PlayerGetFileDuration *durationLoader;
@property (nonatomic, strong, readonly) SJMP3PlayerPrefetcher *prefetcher;
@property (nonatomic, strong, readonly) SJMP3PlayerFileManager *prefetcherFileManager;
@property (nonatomic) SJMP3PlayerFileSource fileOrigin;
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property BOOL userClickedPause;
@property (nonatomic) BOOL needDownload;

// current task
@property float downloadProgress;

@end

@implementation SJMP3Player {
    id _pauseToken;
    id _playToken;
    id _previousToken;
    id _nextToken;
    id _changePlaybackPositionToken;
    dispatch_semaphore_t _lock;
}

+ (instancetype)player {
    return [self new];
}

- (BOOL)enableDBUG {
#ifdef DEBUG
    return _enableDBUG;
#else
    return NO;
#endif
}

- (void)dealloc {
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.pauseCommand removeTarget:_pauseToken];
    [commandCenter.playCommand removeTarget:_playToken];
    [commandCenter.previousTrackCommand removeTarget:_previousToken];
    [commandCenter.nextTrackCommand removeTarget:_nextToken];
    if (@available(iOS 9.1, *)) {
        [commandCenter.changePlaybackPositionCommand removeTarget:_changePlaybackPositionToken];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if ( _task ) [_task cancel];
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _rate = 1;
    _lock = dispatch_semaphore_create(1);
    
    __weak typeof(self) _self = self;
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    _pauseToken = [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(_self) self = _self;
        if ( !self ) return MPRemoteCommandHandlerStatusSuccess;
        [self pause];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] ) [self.delegate remoteEventPausedForAudioPlayer:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    _playToken = [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(_self) self = _self;
        if ( !self ) return MPRemoteCommandHandlerStatusSuccess;
        [self resume];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPlayedForAudioPlayer:)] ) [self.delegate remoteEventPlayedForAudioPlayer:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    _previousToken = [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(_self) self = _self;
        if ( !self ) return MPRemoteCommandHandlerStatusSuccess;
        [self.delegate remoteEvent_PreWithAudioPlayer:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    _nextToken = [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        __strong typeof(_self) self = _self;
        if ( !self ) return MPRemoteCommandHandlerStatusSuccess;
        [self.delegate remoteEvent_NextWithAudioPlayer:self];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    if (@available(iOS 9.1, *)) {
        _changePlaybackPositionToken = [commandCenter.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
            __strong typeof(_self) self = _self;
            if ( !self ) return MPRemoteCommandHandlerStatusSuccess;
            MPChangePlaybackPositionCommandEvent * playbackPositionEvent = (MPChangePlaybackPositionCommandEvent *)event;
            [self seekToTime:playbackPositionEvent.positionTime];
            return MPRemoteCommandHandlerStatusSuccess;
        }];
    }
    
    static dispatch_queue_t serialQueue = NULL;
    if ( !serialQueue ) {
        serialQueue = dispatch_queue_create("com.sjmp3player.audioQueue", DISPATCH_QUEUE_SERIAL);
    }
    _serialQueue = serialQueue;
    
    _fileManager = [SJMP3PlayerFileManager new];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_activateAudioSession) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}

- (void)_activateAudioSession {
    NSError *error = NULL;
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
        NSLog(@"Failed to set active audio session! error: %@", error);
    }
    
    // 默认情况下为 AVAudioSessionCategorySoloAmbient,
    // 这种类型可以确保当应用开始时关闭其他的音频, 并且当屏幕锁定或者设备切换为静音模式时应用能够自动保持静音,
    // 当屏幕锁定或其他应用置于前台时, 音频将会停止, AVAudioSession会停止工作.
    // 设置为AVAudioSessionCategoryPlayback, 可以实现当应用置于后台或用户切换设备为静音模式还可以继续播放音频.
    if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error] ) {
        NSLog(@"Failed to set audio category! error: %@", error);
    }
}

- (void)_audioSessionInterruptionNotification:(NSNotification *)notification{
    NSDictionary *info = notification.userInfo;
    if( (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan ) {
        [self pause];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] ) [self.delegate remoteEventPausedForAudioPlayer:self];
    }
}

- (void)setRate:(float)rate {
    if ( isnan(rate) ) return;
    _rate = rate;
    if ( [self.audioPlayer prepareToPlay] ) self.audioPlayer.rate = rate;
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

/// 是否需要播放
- (BOOL)isNeedToPlay {
    return !self.isPlaying && !self.userClickedPause;
}

- (BOOL)seekToTime:(NSTimeInterval)sec {
    if ( isnan(sec) ) return NO;
    if ( ![self.audioPlayer prepareToPlay] ) return NO;
    if ( self.audioPlayer.duration == 0 ) return NO;
    if ( self.needDownload && (sec / self.audioPlayer.duration > self.downloadProgress) ) return NO;
    self.audioPlayer.currentTime = sec;
    [self resume];
    return YES;
}

- (void)pause {
    self.userClickedPause =  YES;
    [self.audioPlayer pause];
    [self _clearRefreshTimeTimer];
    [self _clearPlayTmpFileTimer];
}

- (void)resume {
    self.userClickedPause = NO;
    [self.audioPlayer play];
    self.audioPlayer.rate = self.rate;
    [self _setPlayInfo];
    [self _activateRefreshTimeTimer];
}

- (void)stop {
    [self.fileManager updateURL:nil];
    if ( self.audioPlayer ) {
        [self.audioPlayer stop];
        self.audioPlayer = nil;
    }
    self.userClickedPause = NO;
    if ( _task ) {
        [_task cancel];
        _task = nil;
    }
    self.needDownload = NO;
    self.downloadProgress = 0;
    self.fileOrigin = SJMP3PlayerFileSourceUnknown;
    [self _clearRefreshTimeTimer];
    [self _clearPlayTmpFileTimer];
}

- (void)clearDiskAudioCache {
    if ( self.isPlaying ) [self stop];
    [SJMP3PlayerFileManager clear];
}

- (void)clearTmpAudioCache {
    [SJMP3PlayerFileManager clearTmpFiles];
}

- (long long)diskAudioCacheSize {
    return [SJMP3PlayerFileManager cacheSize];
}

/*!
 *  查看音乐是否已缓存 */
- (BOOL)isCached:(NSURL *)URL {
    return [SJMP3PlayerFileManager isCached:URL];
}

#pragma mark

- (void)playWithURL:(NSURL *)URL {
    NSParameterAssert(URL);
    [self stop];
    if ( !URL ) return;
    [self _activateAudioSession];
    _currentURL = URL;
    
    if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
        [self.delegate audioPlayer:self currentTime:0 reachableTime:0 totalTime:0];
    }
    
    __weak typeof(self) _self = self;
    dispatch_async(_serialQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( URL.isFileURL ) {
            [self _playFile:URL source:SJMP3PlayerFileSourceLocal];
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
                [self.delegate audioPlayer:self downloadFinishedForURL:URL];
            }
            [self _tryToPrefetchNextAudio];
        }
        else if ( [SJMP3PlayerFileManager isCached:URL] ) {
            [self _playFile:[SJMP3PlayerFileManager fileCacheURL:URL] source:SJMP3PlayerFileSourceCache];
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
                [self.delegate audioPlayer:self downloadFinishedForURL:URL];
            }
            [self _tryToPrefetchNextAudio];
        }
        else [self _needDownloadAudio];
    });
}

#pragma mark downlaod

- (void)_needDownloadAudio {
    [self _cancelPrefetch]; // 取消预缓存, 等待当前任务下载完成
    self.needDownload = YES;
    [self.fileManager updateURL:self.currentURL];
    NSURL *URL = self.fileManager.URL;
    __weak typeof(self) _self = self;
    self.task = [SJDownloadDataTask downloadWithURLStr:URL.description toPath:self.fileManager.tmpFileCacheURL append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            self.downloadProgress = progress;
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] )
                [self.delegate audioPlayer:self audioDownloadProgress:progress];
        });
    } success:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.downloadProgress = 1;
        self.task = nil;
        [self.fileManager copyTmpFileToCache];
        [self _clearPlayTmpFileTimer];
        [self _playFile:self.fileManager.fileCacheURL source:SJMP3PlayerFileSourceCache currentTime:self.audioPlayer.currentTime];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
                [self.delegate audioPlayer:self downloadFinishedForURL:URL];
            }

            dispatch_async(self.serialQueue, ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return;
                [self _tryToPrefetchNextAudio];
            });
        });
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        
        if ( self.enableDBUG ) {
            printf("\n- SJMP3Player: 下载失败, 将会在3秒后重启下载. URL: %s \n", URL.description.UTF8String);
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( self.task.identifier == dataTask.identifier ) [dataTask restart];
        });
    }];
    
    [self _activatePlayTmpFileTimer];
    
    if ( self.enableDBUG ) {
        printf("\n- SJMP3Player: 准备缓存, URL: %s, 临时缓存地址: %s \n", URL.description.UTF8String, self.fileManager.tmpFileCacheURL.description.UTF8String);
    }
}

- (BOOL)isDownloaded {
    return [SJMP3PlayerFileManager isCached:self.currentURL];
}

- (void)_cancelPrefetch {
    [self.prefetcherFileManager updateURL:nil];
    [self.prefetcher cancel];
}

- (void)_tryToPrefetchNextAudio {
    NSURL *previousURL = nil, *nextURL = nil, *preURL = nil;

    if ( [self.delegate respondsToSelector:@selector(prefetchURLOfPreviousAudio)] ) {
        previousURL = self.delegate.prefetchURLOfPreviousAudio;
    }
    
    if ( [self.delegate respondsToSelector:@selector(prefetchURLOfNextAudio)] ) {
        nextURL = self.delegate.prefetchURLOfNextAudio;
    }
    
    // set preURL
    if ( nextURL && !nextURL.isFileURL && ![SJMP3PlayerFileManager isCached:nextURL] ) {
        preURL = nextURL;
    }
    else if ( previousURL && !previousURL.isFileURL && ![SJMP3PlayerFileManager isCached:previousURL] ) {
        preURL = previousURL;
    }
    
    if ( !preURL ) return;

    if ( !_prefetcherFileManager ) {
        _prefetcherFileManager = [SJMP3PlayerFileManager new];
    }
    
    if ( !_prefetcher ) {
        _prefetcher = [SJMP3PlayerPrefetcher new];
        __weak typeof(self) _self = self;
        _prefetcher.completionHandler = ^(SJMP3PlayerPrefetcher * _Nonnull prefetcher, BOOL finished) {
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( finished ) {
                dispatch_async(self.serialQueue, ^{
                    __strong typeof(_self) self = _self;
                    if ( !self ) return;
                    [self.prefetcherFileManager copyTmpFileToCache];
                    if ( self.enableDBUG ) {
                        printf("\n- SJMP3Player: 预加载成功: URL: %s, 保存地址: %s \n", self.prefetcherFileManager.URL.description.UTF8String, self.prefetcherFileManager.fileCacheURL.description.UTF8String);
                    }
                    [self _tryToPrefetchNextAudio];
                });
                return;
            }
            // `finished == NO`
            if ( self.enableDBUG ) {
                printf("\n- SJMP3Player: 预加载失败: URL: %s, 将会在3秒后重启下载 \n", prefetcher.URL.description.UTF8String);
            }
            NSURL *URL = prefetcher.URL;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return ;
                if ( [prefetcher.URL isEqual:URL] ) [prefetcher restart];
            });
        };
    }
    
    if ( [_prefetcherFileManager.URL isEqual:preURL] && ![SJMP3PlayerFileManager isCached:preURL] ) return;
    
    [_prefetcher cancel];
    [_prefetcherFileManager updateURL:preURL];
    if ( self.enableDBUG ) printf("\n- SJMP3Player: 准备进行预缓存: URL: %s, 临时缓存地址: %s \n", preURL.description.UTF8String, _prefetcherFileManager.tmpFileCacheURL.description.UTF8String);
    [_prefetcher prefetchAudioForURL:preURL toPath:_prefetcherFileManager.tmpFileCacheURL];
}


#pragma mark play file
/// 清除播放临时文件的timer
- (void)_clearPlayTmpFileTimer {
    SJMP3PlayerLock()
    if ( _tryToPlayTimer ) {
        [_tryToPlayTimer invalidate];
        _tryToPlayTimer = nil;
    }
    SJMP3PlayerUnlock()
}

/// 激活播放临时文件的Timer
- (void)_activatePlayTmpFileTimer {
    SJMP3PlayerLock()
    if ( !_tryToPlayTimer ) {
        __weak typeof(self) _self = self;
        _tryToPlayTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.5 block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return ;
            }
            if ( self.userClickedPause ) return;
            NSURL *tmpFileCacheURL = self.fileManager.tmpFileCacheURL;
            if ( [self.audioPlayer.url isEqual:tmpFileCacheURL] ) return;
            
            if ( self.task.wroteSize < 1024 * 500 ) return;
            
            if ( self.enableDBUG ) {
                printf("\n- SJMP3Player: 尝试播放临时文件 \n");
            }
            
            [self _playFile:self.fileManager.tmpFileCacheURL
                     source:SJMP3PlayerFileSourceTmpCache];
            
            if ( self.audioPlayer.isPlaying ) {
                if ( self.enableDBUG ) {
                    printf("\n- SJMP3Player: 播放临时文件成功 \n");
                }
                [self _clearPlayTmpFileTimer];
            }
        } repeats:YES];
        [_tryToPlayTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_tryToPlayTimer.timeInterval]];
        [[NSRunLoop mainRunLoop] addTimer:_tryToPlayTimer forMode:NSRunLoopCommonModes];
    }
    SJMP3PlayerUnlock()
}

- (void)_playFile:(NSURL *)fileURL source:(SJMP3PlayerFileSource)origin {
    [self _playFile:fileURL source:origin currentTime:0];
}

- (void)_playFile:(NSURL *)fileURL source:(SJMP3PlayerFileSource)origin currentTime:(NSTimeInterval)currentTime {
    self.audioPlayer = nil;
    if ( self.enableDBUG ) {
        switch ( origin ) {
            case SJMP3PlayerFileSourceUnknown: break;
            case SJMP3PlayerFileSourceLocal:
                printf("\n- SJMP3Player: 此次将播放`本地文件`, URL: %s, FileURL: %s \n", self.currentURL.description.UTF8String, fileURL.description.UTF8String);
                break;
            case SJMP3PlayerFileSourceCache:
                printf("\n- SJMP3Player: 此次将播放`缓存文件`, URL: %s, FileURL: %s \n", self.currentURL.description.UTF8String, fileURL.description.UTF8String);
                break;
            case SJMP3PlayerFileSourceTmpCache:
                printf("\n- SJMP3Player: 此次将播放`临时缓存文件`, URL: %s, FileURL: %s \n", self.currentURL.description.UTF8String, fileURL.description.UTF8String);
                break;
        }
    }
    
    self.fileOrigin = origin;
    NSError *error = nil;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL
                                                                 fileTypeHint:AVFileTypeMPEGLayer3
                                                                        error:&error];
    if ( error ) {
        if ( [SJMP3PlayerFileManager isCachedOfFileURL:fileURL] ) {
            [SJMP3PlayerFileManager delete:fileURL];
            printf("\n- SJMP3Player: 播放失败, 已删除下载文件: %s \n", fileURL.description.UTF8String);
        }
        
        if ( self.enableDBUG ) printf("\n- SJMP3Player: 播放器初始化失败, Error: %s, FileURL:%s \n", error.description.UTF8String, fileURL.description.UTF8String);
        return;
    }
    
    if ( !audioPlayer ) return;
    audioPlayer.enableRate = YES;
    if ( ![audioPlayer prepareToPlay] ) return;
    audioPlayer.delegate = self;
    audioPlayer.currentTime = currentTime;
    self.audioPlayer = audioPlayer;
    if ( !self.userClickedPause ) {
        [self resume];
        if ( self.enableDBUG ) {
            printf("\n- SJMP3Player: 开始播放: 当前时间: %f 秒 - %s, 持续时间: %f 秒 - 播放地址为: %s \n", audioPlayer.currentTime, audioPlayer.description.UTF8String, audioPlayer.duration, fileURL.description.UTF8String);
            if ( @available(ios 10, *) ) printf("\n- SJMP3Player: 格式%s \n", audioPlayer.format.description.UTF8String);
        }
    }
}

#pragma mark - delegate

/// 确认audioPlayer是否播放完毕(针对临时缓存文件的情况)
- (void)confirmTmpFileIsFinishedPlaying:(void(^)(BOOL result))completionHandler {
    if ( self.enableDBUG ) {
        printf("\n- SJMP3Player: 正在确认音乐是否播放完毕 \n");
    }
    
    if ( !self.fileManager.isCached ) {
        completionHandler(NO);
        return;
    }
    
    NSURL *URL = self.fileManager.URL;
    __weak typeof(self) _self = self;
    _durationLoader = [[_SJMP3PlayerGetFileDuration alloc] initWithURL:URL loadDurationCallBlock:^(NSTimeInterval secs) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( 0 == secs ) return;
        if ( completionHandler ) completionHandler(ceil(self.audioPlayer.duration) == ceil(secs));
        self.durationLoader = nil;
    }];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    __weak typeof(self) _self = self;
    void(^inner_finishPlayingExeBlock)(void) = ^ {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( self.enableDBUG ) {
            printf("\n- SJMP3Player: 播放完毕, 播放地址:%s \n ", player.url.description.UTF8String);
        }
        
        [self _clearRefreshTimeTimer];
        
        if ( [self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:)] ) {
            __weak typeof(self) _self = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return ;
                [self.delegate audioPlayerDidFinishPlaying:self];
            });
        }
    };
    
    if ( self.fileOrigin != SJMP3PlayerFileSourceTmpCache ) {
        inner_finishPlayingExeBlock();
        return;
    }
    
    NSURL *URL = self.audioPlayer.url;
    [self confirmTmpFileIsFinishedPlaying:^(BOOL result) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( ![self.audioPlayer.url isEqual:URL] ) return;
        if ( result ) inner_finishPlayingExeBlock();
        else {
            if ( self.enableDBUG ) {
                printf("\n- SJMP3Player: 监测的音乐未播放完毕, 2秒后将重启播放 \n");
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return;
                if ( self.audioPlayer != player ) return;
                if ( !self.userClickedPause ) [self _playFile:player.url source:SJMP3PlayerFileSourceTmpCache currentTime:player.duration];
            });
        }
    }];
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
    if ( _refreshTimeTimer ) {
        [_refreshTimeTimer invalidate];
        _refreshTimeTimer = nil;
    }
}

- (void)_activateRefreshTimeTimer {
    if ( _refreshTimeTimer ) return;
    __weak typeof(self) _self = self;
    _refreshTimeTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.2 block:^(NSTimer *timer) {
        __strong typeof(_self) self = _self;
        if ( !self ) {
            [timer invalidate];
            return ;
        }
        if ( self.userClickedPause ) {
            [self _clearRefreshTimeTimer];
            return;
        }
        NSTimeInterval currentTime = self.audioPlayer.currentTime;
        NSTimeInterval totalTime = self.audioPlayer.duration;
        NSTimeInterval reachableTime = self.audioPlayer.duration * self.downloadProgress;
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
            [self.delegate audioPlayer:self currentTime:currentTime reachableTime:reachableTime totalTime:totalTime];
        }
    } repeats:YES];
    [_refreshTimeTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_refreshTimeTimer.timeInterval]];
    [[NSRunLoop mainRunLoop] addTimer:_refreshTimeTimer forMode:NSRunLoopCommonModes];
}

- (void)_setPlayInfo {
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
    if ( [NSThread currentThread].isMainThread ) [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = mediaDict;
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = mediaDict;
        });
    }
}
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
