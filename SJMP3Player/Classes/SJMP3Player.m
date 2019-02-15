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
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import "Core/NSTimer+SJMP3PlayerAdd.h"
#import "Core/SJMP3PlayerPrefetcher.h"
#import "Core/SJMP3FileManager.h"
#import "Core/SJMP3DurationLoader.h"

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

#pragma mark
@interface SJMP3Player()<AVAudioPlayerDelegate>
// - player
@property (strong, nullable) AVAudioPlayer *audioPlayer;
@property BOOL userClickedPause;
@property (nonatomic) BOOL needDownload;
@property (nonatomic) BOOL isCheckingCurrentAudioIsFinishedPlaying;

// - task
@property (strong, nullable) NSURL *currentURL;
@property (strong, nullable) SJMP3DurationLoader *durationLoader;
@property (strong, nullable) SJDownloadDataTask *task;
@property float downloadProgress;
@property (strong, nullable) SJMP3FileManager *fileManager;

// - timer
@property (nonatomic, strong, nullable) NSTimer *refreshTimeTimer;
@property (nonatomic, strong, nullable) NSTimer *tryToPlayTimer;

// - prefetcher
@property (nonatomic, strong, readonly) SJMP3PlayerPrefetcher *prefetcher;
@property (strong, nullable) SJMP3FileManager *prefetcherFileManager;

@property (nonatomic, readonly) dispatch_queue_t serialQueue;
@property (nonatomic) SJMP3PlayerFileSource fileOrigin;
@end

@implementation SJMP3Player {
    dispatch_semaphore_t _lock;
}

+ (instancetype)player {
    return [self new];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if ( _task ) [_task cancel];
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _rate = 1;
    _volume = 1;
    _lock = dispatch_semaphore_create(1);
    _prefetcher = [SJMP3PlayerPrefetcher new];
    _remoteCommandHandler = [SJRemoteCommandHandler new];
    __weak typeof(self) _self = self;
    _remoteCommandHandler.pauseCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self pause];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] ) [self.delegate remoteEventPausedForAudioPlayer:self];
    };
    _remoteCommandHandler.playCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self resume];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPlayedForAudioPlayer:)] ) [self.delegate remoteEventPlayedForAudioPlayer:self];
    };
    _remoteCommandHandler.previousCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self.delegate remoteEvent_PreWithAudioPlayer:self];
    };
    _remoteCommandHandler.nextCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self.delegate remoteEvent_NextWithAudioPlayer:self];
    };
    _remoteCommandHandler.seekToTimeCommandHandler = ^(id<SJRemoteCommandHandler>  _Nonnull handler, NSTimeInterval secs) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self seekToTime:secs];
    };
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    
    _serialQueue = dispatch_queue_create("com.sjmp3player.audioQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(_serialQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self _activateAudioSession];
    });
    return self;
}

- (void)_activateAudioSession {
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

- (void)_audioSessionInterruptionNotification:(NSNotification *)notification{
    NSDictionary *info = notification.userInfo;
    if( (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan ) {
        [self pause];
        if ( [self.delegate respondsToSelector:@selector(remoteEventPausedForAudioPlayer:)] ) [self.delegate remoteEventPausedForAudioPlayer:self];
    }
}

#pragma mark -
- (void)setMute:(BOOL)mute {
    _mute = mute;
    _audioPlayer.volume = mute?0.001:_volume;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    _audioPlayer.volume = volume;
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
    AVAudioPlayer *player = self.audioPlayer;
    [player play];
    player.rate = self.rate;
    player.volume = _mute?0.001:_volume;
    self.userClickedPause = NO;
    [self _setPlayInfo];
    [self _activateRefreshTimeTimer];
}

- (void)stop {
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
    [self stop];
    if ( !URL ) return;
    self.currentURL = URL;
    __weak typeof(self) _self = self;
    dispatch_async(_serialQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
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
    });
}

#pragma mark downlaod

- (void)_needDownloadCurrentAudio {
    __weak typeof(self) _self = self;
    // 取消预缓存, 等待当前任务下载完成
    [self _cancelPrefetch];
    NSURL *URL = self.fileManager.URL;
    self.task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:[NSURL fileURLWithPath:self.fileManager.tmpPath] append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
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
        dispatch_async(self.serialQueue, ^{
            self.task = nil;
            [self _downloadIsFinished];
            [self.fileManager saveTmpItemToFilePath];
            [self _clearPlayTmpFileTimer];
            [self _tryToPrefetchNextAudio];
            if ( dataTask.totalSize != self.audioPlayer.data.length ) {
            #ifdef DEBUG
                printf("\n- SJMP3Player: 下载完毕, 即将重新初始化播放器");
            #endif
                [self _play:self.fileManager.fileData
                     source:SJMP3PlayerFileSourceCache
                currentTime:self.audioPlayer.currentTime];
            }
        });
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        #ifdef DEBUG
        printf("\n- SJMP3Player: 下载失败, 将会在3秒后重启下载. URL: %s \n", URL.description.UTF8String);
        #endif

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( self.task.identifier == dataTask.identifier ) [dataTask restart];
        });
    }];
    
    [self _activatePlayTmpFileTimer];
    
    #ifdef DEBUG
    printf("\n- SJMP3Player: 准备缓存, URL: %s, 临时缓存地址: %s \n", URL.description.UTF8String, self.fileManager.tmpPath.description.UTF8String);
    #endif
}

- (BOOL)isDownloaded {
    return [SJMP3FileManager fileExistsForURL:self.currentURL];
}

- (void)_cancelPrefetch {
    self.prefetcherFileManager = nil;
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
    
    if ( nextURL && !nextURL.isFileURL && ![SJMP3FileManager fileExistsForURL:nextURL] ) {
        preURL = nextURL;
    }
    else if ( previousURL && !previousURL.isFileURL && ![SJMP3FileManager fileExistsForURL:previousURL] ) {
        preURL = previousURL;
    }
    
    if ( !preURL ) return;
    
    self.prefetcherFileManager = [[SJMP3FileManager alloc] initWithURL:preURL];
    __weak typeof(self) _self = self;
    [_prefetcher prefetchAudioForURL:preURL toPath:[NSURL fileURLWithPath:[_prefetcherFileManager tmpPath]] completionHandler:^(SJMP3PlayerPrefetcher * _Nonnull prefetcher, BOOL finished) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        dispatch_async(self.serialQueue, ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            if ( finished ) {
                [self.prefetcherFileManager saveTmpItemToFilePath];
                #ifdef DEBUG
                printf("\n- SJMP3Player: 预加载成功: URL: %s, 保存地址: %s \n", self.prefetcherFileManager.URL.description.UTF8String, self.prefetcherFileManager.tmpPath.description.UTF8String);
                #endif
                [self _tryToPrefetchNextAudio];
            }
            else {
                NSURL *URL = self.prefetcherFileManager.URL;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), self.serialQueue, ^{
                    __strong typeof(_self) self = _self;
                    if ( !self ) return ;
                    if ( [self.prefetcherFileManager.URL isEqual:URL] )
                        [prefetcher restart];
                });
                
                #ifdef DEBUG
                printf("\n- SJMP3Player: 预加载失败: URL: %s, 将会在3秒后重启下载 \n", URL.description.UTF8String);
                #endif
            }
        });
    }];
    
    #ifdef DEBUG
    printf("\n- SJMP3Player: 准备进行预缓存: URL: %s, 临时缓存地址: %s \n", preURL.description.UTF8String, _prefetcherFileManager.tmpPath.description.UTF8String);
    #endif
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
            
            if ( self.audioPlayer.isPlaying ) {
                [self _clearPlayTmpFileTimer];
            #ifdef DEBUG
                printf("\n- SJMP3Player: 播放临时文件成功 \n");
            #endif
            }
        } repeats:YES];
        [_tryToPlayTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_tryToPlayTimer.timeInterval]];
        [[NSRunLoop mainRunLoop] addTimer:_tryToPlayTimer forMode:NSRunLoopCommonModes];
    }
    SJMP3PlayerUnlock()
}

- (void)_play:(NSData *)data source:(SJMP3PlayerFileSource)origin {
    [self _play:data source:origin currentTime:0];
}
- (void)_play:(NSData *)data source:(SJMP3PlayerFileSource)origin currentTime:(NSTimeInterval)currentTime {
    
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
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:nil];
 
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
        printf("\n- SJMP3Player: 开始播放: 当前时间: %f 秒 - %s, 持续时间: %f 秒 \n", audioPlayer.currentTime, audioPlayer.description.UTF8String, audioPlayer.duration);
        if ( @available(ios 10, *) ) printf("\n- SJMP3Player: 格式%s \n", audioPlayer.format.description.UTF8String);
        printf("\n ------------------------------------ \n");
        #endif
    }
    else {
        [self pause];
    }
    audioPlayer.currentTime = currentTime;
}

#pragma mark - delegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    
#ifdef DEBUG
    printf("\n- SJMP3Player: 正在确认音乐是否播放完毕 \n");
#endif
    
    [self _clearRefreshTimeTimer];
    self.isCheckingCurrentAudioIsFinishedPlaying = YES;
    if ( self.task.totalSize == player.data.length ||
         self.fileOrigin != SJMP3PlayerFileSourceTmpCache ) {
        __weak typeof(self) _self = self;
        if ( [self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:)] ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return ;
                [self.delegate audioPlayerDidFinishPlaying:self];
            });
        }
        
    #ifdef DEBUG
        printf("\n- SJMP3Player: 已确认播放完毕, 播放地址:%s \n ", self.currentURL.description.UTF8String);
    #endif
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

/* if an error occurs while decoding it will be reported to the delegate. */
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
#ifdef DEBUG
    NSLog(@"SJMP3Player: %@", error);
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif

}


#pragma mark

- (void)_clearRefreshTimeTimer {
    SJMP3PlayerLock();
    if ( _refreshTimeTimer ) {
        [_refreshTimeTimer invalidate];
        _refreshTimeTimer = nil;
    }
    SJMP3PlayerUnlock();
}

- (void)_activateRefreshTimeTimer {
    SJMP3PlayerLock();
    if ( !_refreshTimeTimer ) {
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
           
            [self _playbackTimeDidChange];
        } repeats:YES];
        [_refreshTimeTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_refreshTimeTimer.timeInterval]];
        [[NSRunLoop mainRunLoop] addTimer:_refreshTimeTimer forMode:NSRunLoopCommonModes];
    }
    SJMP3PlayerUnlock();
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

- (void)_playbackTimeDidChange {
    NSTimeInterval currentTime = self.audioPlayer.currentTime;
    NSTimeInterval totalTime = self.audioPlayer.duration;
    NSTimeInterval reachableTime = self.audioPlayer.duration * self.downloadProgress;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( self.isCheckingCurrentAudioIsFinishedPlaying ) {
            return;
        }
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
            [self.delegate audioPlayer:self currentTime:currentTime reachableTime:reachableTime totalTime:totalTime];
        }
    });
}

- (void)_downloadIsFinished {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadProgress = 1;
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
            [self.delegate audioPlayer:self downloadFinishedForURL:self.currentURL];
        }
    });
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
