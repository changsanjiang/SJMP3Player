//
//  SJMP3Player.m
//  Pods
//
//  Created by changsanjiang on 10/13/2017.
//

#import "SJMP3Player.h"
#import <AVFoundation/AVFoundation.h>
#import <SJDownloadDataTask/SJDownloadDataTask.h>
#import "NSTimer+SJMP3PlayerAdd.h"
#import "SJMP3FileManager.h"

NS_ASSUME_NONNULL_BEGIN
#define DWONLOAD_RETRY_AFTER       (3)
#define TRY_TO_PLAY_AFTER          (0.5)

#ifdef DEBUG
#define ENABLE_DEBUG    (1)
#else
#define ENABLE_DEBUG    (0)
#endif

typedef struct {
    BOOL isRemote;
    BOOL isPaused;              ///< 是否调用了暂停
    BOOL isPlaying;             ///< 是否调用了playing
    BOOL isStopped;             ///< 是否调用了停止
} SJMP3PlaybackControlInfo;

@interface SJMP3Player ()<AVAudioPlayerDelegate>
@property (nonatomic, strong, nullable) SJDownloadDataTask *downloadTask;
@property (nonatomic, strong, nullable) SJDownloadDataTask *prefetchTask;
@property (nonatomic, readonly) SJMP3PlaybackControlInfo controlInfo;

@property (nonatomic) NSTimeInterval duration;
@property (nonatomic, strong, nullable) NSURL *URL;
@property (strong, nullable) AVAudioPlayer *player;

@property (nonatomic, strong, nullable) NSTimer *tryToPlayTimer;
@property (nonatomic, strong, nullable) NSTimer *refreshTimeTimer;
@end

@implementation SJMP3Player
+ (nullable instancetype)playerWithURL:(NSURL *)URL {
    return [[SJMP3Player alloc] initWithURL:URL];
}

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ( AVAudioSession.sharedInstance.category != AVAudioSessionCategoryPlayback &&
            AVAudioSession.sharedInstance.category != AVAudioSessionCategoryPlayAndRecord ) {
            NSError *error = nil;
            // 使播放器在静音状态下也能放出声音
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
#ifdef DEBUG
            if ( error ) NSLog(@"%@", error.userInfo);
#endif
        }
        
        
        NSError *error = NULL;
        if ( ![[AVAudioSession sharedInstance] setActive:YES error:&error] ) {
#ifdef DEBUG
            NSLog(@"Failed to set active audio session! error: %@", error);
#endif
        }
    });
}

- (nullable instancetype)initWithURL:(NSURL *)URL {
    if ( URL == nil ) return nil;
    self = [super init];
    if ( self ) {
        _URL = URL;
        _rate = 1;
        _volume = 1;
        [self _initalize];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)_initalize {
    NSURL *_Nullable fileURL = nil;
    if ( _URL.isFileURL ) {
        fileURL = _URL;
    }
    else if ( [SJMP3FileManager fileExistsForURL:_URL] ){
        fileURL = [SJMP3FileManager fileURLForURL:_URL];
    }
    
#if ENABLE_DEBUG
    [self _log_asset_begin_init];
#endif
    
    AVURLAsset *asset = [AVURLAsset assetWithURL:fileURL?:_URL];
    static NSString *kDuration = @"duration";
    __weak typeof(self) _self = self;
    [asset loadValuesAsynchronouslyForKeys:@[kDuration] completionHandler:^{
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = nil;
            NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
            [asset statusOfValueForKey:kDuration error:&error];
            if ( duration == 0 || error != nil ) {
#if ENABLE_DEBUG
                [self _log_asset_init_error];
#endif
                if ( [self.delegate respondsToSelector:@selector(mp3Player:initializationFailed:)] ) {
                    [self.delegate mp3Player:self initializationFailed:error];
                }
            }
            else {
#if ENABLE_DEBUG
                [self _log_asset_finish_init];
#endif
                self.duration = duration;
                
                if ( [self.delegate respondsToSelector:@selector(mp3Player:durationDidChange:)] ) {
                    [self.delegate mp3Player:self durationDidChange:duration];
                }
                
                [self _loadAudioPlayer];
            }
        });
    }];
}

- (void)_loadAudioPlayer {
    NSURL *_Nullable fileURL = nil;
    if ( _URL.isFileURL ) {
        fileURL = _URL;
    }
    else if ( [SJMP3FileManager fileExistsForURL:_URL] ){
        fileURL = [SJMP3FileManager fileURLForURL:_URL];
    }
    
    if ( fileURL != nil ) {
        _controlInfo.isRemote = NO;
        
        NSError *_Nullable error = nil;
        AVAudioPlayer *_Nullable player = [self _createAudioPlayerForFileURL:fileURL error:&error];
        if ( error != nil ) {
            if ( [self.delegate respondsToSelector:@selector(mp3Player:initializationFailed:)] ) {
                [self.delegate mp3Player:self initializationFailed:error];
            }
            
#if ENABLE_DEBUG
            [self _log_player_init_error:error];
#endif
        }
        else {
            [self setPlayer:player];
            [self resume];
            [self _prefetchIfNeeded];
            if ( [self.delegate respondsToSelector:@selector(mp3Player:downloadProgressDidChange:)] ) {
                [self.delegate mp3Player:self downloadProgressDidChange:1];
            }
            
#if ENABLE_DEBUG
            [self _log_player_finish_init];
#endif
        }
    }
    else {
        // not cached, do download
        _controlInfo.isRemote = YES;
        [self _needDownloadCurrentAudio];
    }
}

#pragma mark -
- (NSTimeInterval)currentTime {
    if ( !self.player.isPlaying ) {
        if ( self.downloadTask.totalSize != 0 ) {
            if ( self.player.data.length != self.downloadTask.totalSize )
                return 1.0 * self.player.data.length / self.downloadTask.totalSize * self.duration;
        }
    }
    return self.player.currentTime;
}

- (float)downloadProgress {
    if ( self.controlInfo.isRemote )
        return self.downloadTask.progress;
    return 1;
}

- (void)setRate:(float)rate {
    _rate = rate;
    self.player.rate = rate;
}

@synthesize volume = _volume;
- (void)setVolume:(float)volume {
    _volume = volume;
    self.player.volume = _mute?0.001:_volume;
}

- (float)volume {
    return _mute?0.001:_volume;
}

- (void)setMute:(BOOL)mute {
    _mute = mute;
    self.player.volume = mute?0.001:_volume;
}

- (void)resume {
    if ( self.URL != nil ) {
        _controlInfo.isPlaying = YES;
        _controlInfo.isPaused = NO;
        [self.player play];
        [self.player setRate:self.rate];
        [self.player setVolume:self.volume];
        [self _refreshTime_start];
    }
}
- (void)pause {
    if ( self.URL != nil ) {
        [self _refreshTime_end];
        [self _tryToPlay_end];
        _controlInfo.isPlaying = NO;
        _controlInfo.isPaused = YES;
        [self.player pause];
    }
}
- (void)stop {
    if ( self.URL != nil ) {
        self.URL = nil;
        [self _refreshTime_end];
        [self _tryToPlay_end];
        [self _cancelDownloadTasks];
        [self.player stop];
        self.player = nil;
        _controlInfo.isPaused = NO;
        _controlInfo.isPlaying = NO;
        _controlInfo.isStopped = YES;
        _controlInfo.isRemote = NO;
    }
}
- (void)seekToTime:(NSTimeInterval)secs {
    if ( self.URL != nil ) {
        if ( self.duration == 0 )
            return;
        /// if 未下载完
        if ( _controlInfo.isRemote && self.downloadTask.progress < 1 ) {
            if ( self.downloadTask.totalSize == 0 )
                return;
            NSTimeInterval reach = 1.0 * self.player.data.length / self.downloadTask.totalSize * self.duration;
            if ( secs > reach ) secs = reach * 0.92;
        }
        [self.player setCurrentTime:secs];
        [self resume];
    }
}

#pragma mark -

- (void)_needDownloadCurrentAudio {
    NSURL *URL = self.URL;
    NSURL *toPath = [SJMP3FileManager tmpURLForURL:URL];
    __weak typeof(self) _self = self;
    self.downloadTask = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:toPath append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self _downloadProgressDidChange:progress];
        });
    } success:^(SJDownloadDataTask * _Nonnull dataTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self _didCompleteDownload:nil];
        });
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self _didCompleteDownload:dataTask.error];
        });
    }];
    
#if ENABLE_DEBUG
    [self _log_download_begin];
#endif
}

- (void)_downloadProgressDidChange:(float)progress {
    if ( !self.controlInfo.isPaused && !self.controlInfo.isStopped)
        [self _tryToPlay_start];
    
    if ( [self.delegate respondsToSelector:@selector(mp3Player:downloadProgressDidChange:)] ) {
        [self.delegate mp3Player:self downloadProgressDidChange:progress];
    }
}

- (void)_didCompleteDownload:(nullable NSError *)error {
    if ( error != nil ) {
#if ENABLE_DEBUG
        [self _log_download_error];
#endif
        __weak typeof(self) _self = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DWONLOAD_RETRY_AFTER * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [self.downloadTask restart];
        });
    }
    else {
#if ENABLE_DEBUG
        [self _log_download_finish];
#endif
        [SJMP3FileManager copyTmpFileToRootFolderForURL:_URL];
#if ENABLE_DEBUG
        [self _log_player_last_continue_playing];
#endif
        [self _resetPlayer];
        [self _prefetchIfNeeded];
    }
}

- (void)_prefetchIfNeeded {
    NSURL *_Nullable URL = nil;
    // next
    if ( [self.delegate respondsToSelector:@selector(prefetchURLOfNextAudio)] ) {
        NSURL *_Nullable audio = [self.delegate prefetchURLOfNextAudio];
        if ( ![SJMP3FileManager fileExistsForURL:audio] ) {
            URL = audio;
        }
    }
    
    // previous
    if ( URL == nil ) {
        if ( [self.delegate respondsToSelector:@selector(prefetchURLOfNextAudio)] ) {
            NSURL *_Nullable audio = [self.delegate prefetchURLOfPreviousAudio];
            if ( ![SJMP3FileManager fileExistsForURL:audio] ) {
                URL = audio;
            }
        }
    }
    
    if ( URL != nil ) {
        __weak typeof(self) _self = self;
        _prefetchTask = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:[SJMP3FileManager tmpURLForURL:URL] append:YES progress:nil success:^(SJDownloadDataTask * _Nonnull dataTask) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_self _didCompletePrefetch:nil URL:URL];
            });
        } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_self _didCompletePrefetch:dataTask.error URL:URL];
            });
        }];
        
#if ENABLE_DEBUG
        [self _log_prefetch_begin];
#endif
    }
}

- (void)_didCompletePrefetch:(nullable NSError *)error URL:(NSURL *)URL {
    if ( error != nil ) {
#if ENABLE_DEBUG
        [self _log_prefetch_error];
#endif
        __weak typeof(self) _self = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DWONLOAD_RETRY_AFTER * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return;
            [self.prefetchTask restart];
        });
    }
    else {
#if ENABLE_DEBUG
        [self _log_prefetch_finish];
#endif
        
        _prefetchTask = nil;
        [SJMP3FileManager copyTmpFileToRootFolderForURL:URL];
        [self _prefetchIfNeeded];
    }
}

- (void)_cancelDownloadTasks {
    if ( _downloadTask != nil ) {
        [_downloadTask cancel];
        _downloadTask = nil;
    }
    if ( _prefetchTask != nil ) {
        [_prefetchTask cancel];
        _prefetchTask = nil;
    }
}

#pragma mark - AVAudioPlayer

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if ( self.downloadTask.error != nil ) {
        return;
    }
    
    if ( _controlInfo.isRemote == NO || self.downloadTask.totalSize == player.data.length ) {
        if ( [self.delegate respondsToSelector:@selector(mp3PlayerDidFinishPlaying:)] ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate mp3PlayerDidFinishPlaying:self];
            });
        }
        
#if ENABLE_DEBUG
        [self _log_player_finish_playing];
#endif
    }
    else {
        [self _resetPlayer];
    }
}

- (nullable AVAudioPlayer *)_createAudioPlayerForFileURL:(NSURL *)fileURL error:(NSError *_Nullable * _Nullable)error {
    if ( fileURL == nil )
        return nil;
    
    NSData *_Nullable data = [NSData dataWithContentsOfURL:fileURL
                                                   options:NSDataReadingMappedIfSafe|NSDataReadingUncached
                                                     error:error];
    if ( data == nil ) {
        return nil;
    }
    
    AVAudioPlayer *_Nullable player = [[AVAudioPlayer alloc] initWithData:data fileTypeHint:AVFileTypeMPEGLayer3 error:error];
    if ( player == nil ) {
        return nil;
    }
    
    [player setEnableRate:YES];
    [player prepareToPlay];
    return player;
}

- (void)_resetPlayer {
    AVAudioPlayer *_Nullable player = [self _createAudioPlayerForFileURL:self.downloadTask.fileURL error:nil];
    if ( player == nil ) {
        return;
    }
    
    NSTimeInterval currentTime = 0;
    if ( self.player.isPlaying ) {
        currentTime = self.player.currentTime;
    }
    else if ( self.downloadTask.totalSize != 0 ) {
        currentTime = 1.0 * self.player.data.length / self.downloadTask.totalSize * self.duration;
    }
    
    //    NSLog(@"=========");
    //    NSLog(@"Old: %lf - %lf", currentTime, self.player.duration);
    
    player.currentTime = currentTime;
    
    //    NSLog(@"New: %lf - %lf", player.currentTime, player.duration);
    
    [self setPlayer:player];
    if ( !self.controlInfo.isPaused )
        [self resume];
    [self _tryToPlay_end];
    
#if ENABLE_DEBUG
    [self _log_player_continue_playing];
#endif
}

#pragma mark -

- (void)_tryToPlay_start {
    if ( _tryToPlayTimer == nil ) {
        __weak typeof(self) _self = self;
        _tryToPlayTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:TRY_TO_PLAY_AFTER block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return;
            }
            
            if ( self.downloadTask.wroteSize < 1024 * 500 ) {
                return;
            }
            
            if ( self.player.isPlaying ) {
                [self _tryToPlay_end];
            }
            else {
                [self _resetPlayer];
            }
        } repeats:YES];
        
        [_tryToPlayTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_tryToPlayTimer.timeInterval]];
        [NSRunLoop.mainRunLoop addTimer:_tryToPlayTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)_tryToPlay_end {
    if ( _tryToPlayTimer != nil ) {
        [_tryToPlayTimer invalidate];
        _tryToPlayTimer = nil;
    }
}

- (void)_refreshTime_start {
    if ( _refreshTimeTimer == nil ) {
        __weak typeof(self) _self = self;
        _refreshTimeTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.2 block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return;
            }
            
            if ( !self.player.isPlaying ) {
                return;
            }
            
            if ( [self.delegate respondsToSelector:@selector(mp3Player:currentTimeDidChange:)] ) {
                [self.delegate mp3Player:self currentTimeDidChange:self.player.currentTime];
            }
        } repeats:YES];
        [_refreshTimeTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_refreshTimeTimer.timeInterval]];
        [[NSRunLoop mainRunLoop] addTimer:_refreshTimeTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)_refreshTime_end {
    if ( _refreshTimeTimer != nil ) {
        [_refreshTimeTimer invalidate];
        _refreshTimeTimer = nil;
    }
}

@synthesize player = _player;
- (void)setPlayer:(nullable AVAudioPlayer *)player {
    @synchronized (self) {
        _player.delegate = nil;
        _player = player;
        player.delegate = self;
    }
}

- (nullable AVAudioPlayer *)player {
    @synchronized (self) {
        return _player;
    }
}

#pragma mark - log

#if ENABLE_DEBUG
- (void)_log_asset_begin_init {
    printf("\n- SJMP3Player: 正在初始化资源... \n");
}

- (void)_log_asset_finish_init {
    printf("\n- SJMP3Player: 资源初始化完成. \n");
}

- (void)_log_asset_init_error {
    printf("\n- SJMP3Player: 资源初始化失败. \n");
}

//
- (void)_log_player_init_error:(nullable NSError *)error {
    printf("\n- SJMP3Player: 初始化失败, Error: %s. \n", error.description.UTF8String);
}

- (void)_log_player_finish_init {
    printf("\n- SJMP3Player: 初始化成功. \n");
    printf("\n- SJMP3Player: 当前时间: %lf 秒, 持续时间: %lf 秒. \n", self.player.currentTime, self.player.duration);
}

- (void)_log_player_finish_playing {
    printf("\n- SJMP3Player: 播放完毕. \n ");
}

- (void)_log_player_continue_playing {
    printf("\n- SJMP3Player: 续播. \n ");
}

- (void)_log_player_last_continue_playing {
    printf("\n- SJMP3Player: 进行最后一次续播. \n ");
}

//
- (void)_log_download_begin {
    printf("\n- SJMP3Player: 开始下载. \n ");
}

- (void)_log_download_finish {
    printf("\n- SJMP3Player: 完成下载. \n ");
}

- (void)_log_download_error {
    printf("\n- SJMP3Player: 下载报错, 将在 %d 后重试. \n ", DWONLOAD_RETRY_AFTER);
}

//
- (void)_log_prefetch_begin {
    printf("\n- SJMP3Player: 开始预加载. \n ");
}

- (void)_log_prefetch_finish {
    printf("\n- SJMP3Player: 预加载完成. \n ");
}

- (void)_log_prefetch_error {
    printf("\n- SJMP3Player: 预加载报错, 将在 %d 后重试. \n ", DWONLOAD_RETRY_AFTER);
}

- (void)_log_ {
    printf("\n- SJMP3Player: \n ");
}
#endif
@end
NS_ASSUME_NONNULL_END
