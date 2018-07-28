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
/// 文件来源
///
/// - SJMP3PlayerFileSourceUnknown:         未知
/// - SJMP3PlayerFileSourceLocal:           本地文件
/// - SJMP3PlayerFileSourceCache:           缓存文件(cache目录)
///- SJMP3PlayerFileSourceTmpCache:         临时缓存文件(tmp目录)
typedef NS_ENUM(NSUInteger, SJMP3PlayerFileSource) {
    SJMP3PlayerFileSourceUnknown,
    SJMP3PlayerFileSourceLocal,
    SJMP3PlayerFileSourceCache,
    SJMP3PlayerFileSourceTmpCache,
};

@interface _SJMP3PlayerGetFileDuration: NSObject
- (instancetype)initWithFileURL:(NSURL *)fileURL loadDurationCallBlock:(void(^)(NSTimeInterval secs))block;
@end

@interface _SJMP3PlayerGetFileDuration()
@property (nonatomic, strong, readonly) AVAsset *asset;
@end
@implementation _SJMP3PlayerGetFileDuration
- (instancetype)initWithFileURL:(NSURL *)fileURL loadDurationCallBlock:(void(^)(NSTimeInterval secs))block {
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
@property (nonatomic, readonly) BOOL needToPlay;

@property (nonatomic, strong, nullable) NSTimer *refreshTimeTimer;
@property (strong, nullable) AVAudioPlayer *audioPlayer;


#pragma mark
@property (nonatomic, strong, nullable) _SJMP3PlayerGetFileDuration *durationLoader;
@property (nonatomic, strong, readonly) SJMP3PlayerPrefetcher *prefetcher;
@property (nonatomic, strong, readonly) SJMP3PlayerFileManager *prefetcherFileManager;
@property (nonatomic) SJMP3PlayerFileSource fileOrigin;
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property (nonatomic) BOOL userClickedPause;
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
}

+ (instancetype)player {
    return [self new];
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activateAudioSession) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    return self;
}

- (void)activateAudioSession {
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

- (void)audioSessionInterruptionNotification:(NSNotification *)notification{
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
- (BOOL)needToPlay {
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
}

- (void)resume {
    self.userClickedPause = NO;
    [self.audioPlayer play];
    [self _setPlayInfo];
    [self activateRefreshTimeTimer];
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
    [self activateAudioSession];
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
            [self _tryToPrefetchNextAudio];
        }
        else if ( [SJMP3PlayerFileManager isCached:URL] ) {
            [self _playFile:[SJMP3PlayerFileManager fileCacheURL:URL] source:SJMP3PlayerFileSourceCache];
            [self _tryToPrefetchNextAudio];
        }
        else [self _needDownloadAudio];
    });
}

#pragma mark downlaod

- (void)_needDownloadAudio {
    [self.prefetcher cancel]; // 取消预缓存, 等待当前任务下载完成
    self.needDownload = YES;
    [self.fileManager updateURL:self.currentURL];
    NSURL *URL = self.fileManager.URL;
    __weak typeof(self) _self = self;
    self.task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:self.fileManager.tmpFileCacheURL append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        [self _tryToPlayTmpFileCache:self.fileManager.tmpFileCacheURL progress:progress];
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
        if ( self.needToPlay ) {
            [self _playFile:self.fileManager.tmpFileCacheURL source:SJMP3PlayerFileSourceTmpCache currentTime:self.audioPlayer.currentTime];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
                [self.delegate audioPlayer:self downloadFinishedForURL:URL];
            }
            [self _tryToPrefetchNextAudio];
        });
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        
        if ( self.enableDBUG ) {
            printf("\n- 下载失败, 2秒后将重启下载. URL: %s \n", URL.absoluteString.UTF8String);
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( self.task.identifier == dataTask.identifier ) [dataTask restart];
        });
    }];
    
    if ( self.enableDBUG ) {
        printf("\n- 准备缓存, URL: %s, 临时缓存地址: %s \n", URL.absoluteString.UTF8String, self.fileManager.tmpFileCacheURL.absoluteString.UTF8String);
    }
}

- (BOOL)isDownloaded {
    return [SJMP3PlayerFileManager isCached:self.currentURL];
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
                [self.prefetcherFileManager copyTmpFileToCache];
                [self _tryToPrefetchNextAudio];
                return;
            }
            // `finished == NO`
            printf("\n- 预加载失败: URL: %s, 将会在2秒后重启下载\n", prefetcher.URL.absoluteString.UTF8String);
            NSURL *URL = prefetcher.URL;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return ;
                if ( [prefetcher.URL isEqual:URL] ) [prefetcher restart];
            });
        };
    }
    
    if ( [_prefetcherFileManager.URL isEqual:preURL] && ![SJMP3PlayerFileManager isCached:preURL] ) return;
    
    if ( self.enableDBUG ) {
        printf("\n- 准备进行预缓存: URL: %s, 临时缓存地址: %s \n", preURL.absoluteString.UTF8String, _prefetcherFileManager.tmpFileCacheURL.absoluteString.UTF8String);
    }
    
    [_prefetcher cancel];
    
    [_prefetcherFileManager updateURL:preURL];
    
    [_prefetcher prefetchAudioForURL:preURL toPath:_prefetcherFileManager.tmpFileCacheURL];
}


#pragma mark play file

- (void)_tryToPlayTmpFileCache:(NSURL *)tmpFileCacheURL progress:(float)progress {
    if ( progress < 0.1 ) return;
    if ( ![self needToPlay] ) return;
    [self _playFile:tmpFileCacheURL source:SJMP3PlayerFileSourceTmpCache currentTime:self.audioPlayer.currentTime];
}

- (BOOL)_playFile:(NSURL *)fileURL source:(SJMP3PlayerFileSource)origin {
    return [self _playFile:fileURL source:origin currentTime:0];
}

- (BOOL)_playFile:(NSURL *)fileURL source:(SJMP3PlayerFileSource)origin currentTime:(NSTimeInterval)currentTime {
    if ( self.enableDBUG ) {
        switch ( origin ) {
            case SJMP3PlayerFileSourceUnknown: break;
            case SJMP3PlayerFileSourceLocal:
                printf("\n- 此次将播放`本地文件`, URL: %s, FileURL: %s \n", self.currentURL.absoluteString.UTF8String, fileURL.absoluteString.UTF8String);
                break;
            case SJMP3PlayerFileSourceCache:
                printf("\n- 此次将播放`缓存文件`, URL: %s, FileURL: %s \n", self.currentURL.absoluteString.UTF8String, fileURL.absoluteString.UTF8String);
                break;
            case SJMP3PlayerFileSourceTmpCache:
                printf("\n- 此次将播放`临时缓存文件`, URL: %s, FileURL: %s \n", self.currentURL.absoluteString.UTF8String, fileURL.absoluteString.UTF8String);
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
            NSLog(@"\nSJMP3Player: -播放失败, 已删除下载文件-%@ \n", fileURL);
        }
        
        if ( self.enableDBUG ) NSLog(@"\nSJMP3Player: -播放器初始化失败-%@-%@ \n", error, fileURL);
        return NO;
    }
    
    if ( !audioPlayer ) return NO;
    audioPlayer.enableRate = YES;
    if ( ![audioPlayer prepareToPlay] ) return NO;
    audioPlayer.delegate = self;
    audioPlayer.currentTime = currentTime;
    [audioPlayer play];
    audioPlayer.rate = self.rate;
    if ( self.enableDBUG ) {
        NSLog(@"\nSJMP3Player: -开始播放\n-持续时间: %f 秒\n-播放地址为: %@ ", audioPlayer.duration, fileURL);
        if ( @available(ios 10, *) ) NSLog(@"\n-格式%@", audioPlayer.format);
    }
    self.audioPlayer = audioPlayer;
    [self activateRefreshTimeTimer];
    [self _setPlayInfo];
    return YES;
}

/// 确认audioPlayer是否播放完毕(针对临时缓存文件的情况)
- (void)confirmTmpFileIsFinishedPlaying:(void(^)(BOOL result))completionHandler {
    if ( !self.fileManager.isCached ) {
        completionHandler(NO);
        return;
    }
    
    NSURL *tmpFileCacheURL = self.fileManager.tmpFileCacheURL;
    __weak typeof(self) _self = self;
    _durationLoader = [[_SJMP3PlayerGetFileDuration alloc] initWithFileURL:tmpFileCacheURL loadDurationCallBlock:^(NSTimeInterval secs) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( 0 == secs ) return;
        if ( completionHandler ) completionHandler(ceil(self.audioPlayer.duration) == ceil(secs));
    }];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    __weak typeof(self) _self = self;
    void(^inner_finishPlayingExeBlock)(void) = ^ {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( self.enableDBUG ) {
            printf("- 播放完毕\n-播放地址:%s", player.url.absoluteString.UTF8String);
        }
        
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
    
    [self confirmTmpFileIsFinishedPlaying:^(BOOL result) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( result ) inner_finishPlayingExeBlock();
        else if ( !self.userClickedPause ) [self _playFile:player.url source:SJMP3PlayerFileSourceTmpCache currentTime:player.duration];
    }];
}

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
    NSLog(@"SJMP3Player: %@", error);
#ifdef DEBUG
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

- (void)activateRefreshTimeTimer {
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

#pragma mark

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
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = mediaDict;
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
