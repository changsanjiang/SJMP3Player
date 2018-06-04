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

NS_ASSUME_NONNULL_BEGIN

@interface SJMP3PlayerFileManager : NSObject
#pragma mark
+ (BOOL)delete:(NSURL *)fileURL;
+ (BOOL)isCached:(NSURL *)URL;
+ (BOOL)isCachedForFileURL:(NSURL *)fileURL;
+ (NSURL *)tmpFileURL:(NSURL *)URL; // remote url
+ (void)clear;
+ (void)clearTmpFiles;
+ (long long)cacheSize;

#pragma mark
- (void)updateURL:(nullable NSURL *)URL;
@property (nonatomic, readonly) BOOL isCached;
@property (nonatomic, strong, readonly, nullable) NSURL *URL;
@property (nonatomic, strong, readonly, nullable) NSURL *fileURL;
@property (nonatomic, strong, readonly, nullable) NSURL *tmpFileURL;
- (BOOL)deleteCache;
- (BOOL)deleteTmpFile;
- (void)moveTmpFileToCache;
@end

@implementation SJMP3PlayerFileManager
- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    [[self class] _checkoutCacheFolder];
    return self;
}

+ (void)_checkoutCacheFolder {
    /// cache folder
    NSString *folder = SJMP3PlayerFileManager.rootFolder;
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    /// tmp cache folder
    folder = SJMP3PlayerFileManager.tmpFolder;
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

#pragma mark
- (void)updateURL:(nullable NSURL *)URL {
    if ( URL.isFileURL ) return;
    _URL = URL;
}
- (BOOL)isCached {
    if ( !self.URL ) return NO;
    return [SJMP3PlayerFileManager isCached:self.URL];
}
- (nullable NSURL *)fileURL {
    if ( !self.URL ) return nil;
    return [NSURL fileURLWithPath:[SJMP3PlayerFileManager filePath:self.URL]];
}
- (nullable NSURL *)tmpFileURL {
    if ( !self.URL ) return nil;
    return [NSURL fileURLWithPath:[SJMP3PlayerFileManager tmpFilePath:self.URL]];
}
- (BOOL)deleteCache {
    if ( !self.isCached ) return NO;
    return [[NSFileManager defaultManager] removeItemAtPath:self.fileURL.path error:nil];
}
- (BOOL)deleteTmpFile {
    return [[NSFileManager defaultManager] removeItemAtPath:self.tmpFileURL.path error:nil];
}
- (void)moveTmpFileToCache {
    if ( !self.URL ) return;
    [[NSFileManager defaultManager] copyItemAtURL:self.tmpFileURL toURL:self.fileURL error:nil];
}

#pragma mark
+ (NSString *)rootFolder {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"com.dancebaby.lanwuzhe.audioCacheFolder/cache"];
}
+ (NSString *)tmpFolder {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"audioTmpFolder"];
}
+ (NSString *)filePath:(NSURL *)URL {
    return [SJMP3PlayerFileManager.rootFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld", (unsigned long)[URL.absoluteString hash]]];
}
+ (NSString *)tmpFilePath:(NSURL *)URL {
    return [SJMP3PlayerFileManager.tmpFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld", (unsigned long)[URL.absoluteString hash]]];
}
+ (BOOL)delete:(NSURL *)fileURL {
    return [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
}
+ (BOOL)isCached:(NSURL *)URL {
    return [[NSFileManager defaultManager] fileExistsAtPath:[SJMP3PlayerFileManager filePath:URL]];
}
+ (BOOL)isCachedForFileURL:(NSURL *)fileURL {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self.rootFolder stringByAppendingPathComponent:fileURL.lastPathComponent]];
}
+ (NSURL *)tmpFileURL:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self tmpFilePath:URL]];
}
+ (void)clear {
    [[NSFileManager defaultManager] removeItemAtPath:[self rootFolder]  error:nil];
    [self _checkoutCacheFolder];
}
+ (long long)cacheSize {
    __block long long size = 0;
    [[self cacheFiles] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary<NSFileAttributeKey, id> *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:obj error:nil];
        size += [dict[NSFileSize] integerValue];
    }];
    return size;
}
+ (void)clearTmpFiles {
    [[NSFileManager defaultManager] removeItemAtPath:[self tmpFolder] error:nil];
    [self _checkoutCacheFolder];
}
+ (NSArray<NSString *> *)cacheFiles {
    NSString *rootFolder = [self rootFolder];
    NSArray *paths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootFolder error:nil];
    NSMutableArray<NSString *> *itemPaths = [NSMutableArray new];
    [paths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [itemPaths addObject:[rootFolder stringByAppendingPathComponent:obj]];
    }];
    return itemPaths;
}
@end


#pragma mark -

typedef NS_ENUM(NSUInteger, SJMP3PlayerFileOrigin) {
    SJMP3PlayerFileOriginUnknown,
    SJMP3PlayerFileOriginLocal,
    SJMP3PlayerFileOriginCache,
    SJMP3PlayerFileOriginTmpCache,
};

@interface SJMP3Player()<AVAudioPlayerDelegate>
@property (nonatomic, strong, readonly) SJMP3PlayerFileManager *fileManager;
@property (nonatomic, readonly) dispatch_queue_t serialQueue;
@property (nonatomic, readonly) BOOL needToPlay;

@property (nonatomic, strong, nullable) NSTimer *refreshCurrentTimeTimer;
@property (strong, nullable) AVAudioPlayer *audioPlayer;


#pragma mark
@property (nonatomic) NSTimeInterval audioDuration;
@property (nonatomic) SJMP3PlayerFileOrigin fileOrigin;
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property (nonatomic) BOOL userClickedPause;
@property (nonatomic) BOOL needDownload;
@property (nonatomic) BOOL isDownloaded;
@property float downloadProgress;
@end

@implementation SJMP3Player

+ (instancetype)player {
    return [self new];
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _rate = 1;
    NSError *error = NULL;
    if ( ![[AVAudioSession sharedInstance] setActive: YES error:&error] ) {
        NSLog(@"Failed to set active audio session! error: %@", error);
    }
    // 默认情况下为 AVAudioSessionCategorySoloAmbient,
    // 这种类型可以确保当应用开始时关闭其他的音频, 并且当屏幕锁定或者设备切换为静音模式时应用能够自动保持静音,
    // 当屏幕锁定或其他应用置于前台时, 音频将会停止, AVAudioSession会停止工作.
    
    // 设置为AVAudioSessionCategoryPlayback, 可以实现当应用置于后台或用户切换设备为静音模式还可以继续播放音频.
    if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error] ) {
        NSLog(@"Failed to set audio category! error: %@", error);
    }

    _serialQueue = dispatch_queue_create("com.sjmp3player.audioQueue", DISPATCH_QUEUE_SERIAL);
    _fileManager = [SJMP3PlayerFileManager new];
    [self _configRemoteEventReceiver];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

- (BOOL)needToPlay {
    return !self.isPlaying && !self.userClickedPause;
}

- (BOOL)seekToTime:(NSTimeInterval)sec {
    if ( isnan(sec) ) return NO;
    if ( ![self.audioPlayer prepareToPlay] ) return NO;
    if ( self.needDownload ) {
        if ( sec / self.audioPlayer.duration > self.downloadProgress ) return NO;
    }
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
    self.isDownloaded = NO;
    self.fileOrigin = SJMP3PlayerFileOriginUnknown;
    self.audioDuration = 0;
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
    [self playWithURL:URL audioDuration:0];
}

- (void)playWithURL:(NSURL *)URL audioDuration:(NSTimeInterval)sec {
    NSParameterAssert(URL);
    [self stop];
    [self.fileManager updateURL:URL];
    self.audioDuration = sec;
    _currentURL = URL;
    if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
        [self.delegate audioPlayer:self currentTime:0 reachableTime:0 totalTime:0];
    }
    __weak typeof(self) _self = self;
    dispatch_async(_serialQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( URL.isFileURL ) {
            [self _playFile:URL
                 fileOrigin:SJMP3PlayerFileOriginLocal];
            
            if ( self.enableDBUG ) {
                NSLog(@"\nSJMP3Player: -此次播放本地文件, URL: %@\n", URL);
            }
        }
        else if ( self.fileManager.isCached ) {
            [self _playFile:self.fileManager.fileURL
                 fileOrigin:SJMP3PlayerFileOriginCache];
            
            if ( self.enableDBUG ) {
                NSLog(@"\nSJMP3Player: -此次播放缓存文件, URL: %@, fileURL: %@ \n", URL, self.fileManager.fileURL);
            }
        }
        else {
            [self _downloadAudio];
            
            if ( self.enableDBUG ) {
                NSLog(@"\nSJMP3Player: -准备缓存媒体文件, URL: %@, 保存地址: %@ \n", URL, self.fileManager.tmpFileURL);
            }
        }
    });
}

- (void)_downloadAudio {
    self.needDownload = YES;
    NSURL *URL = self.fileManager.URL;
    __weak typeof(self) _self = self;
    self.task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:self.fileManager.tmpFileURL append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.downloadProgress = progress;
        if ( self.needToPlay && progress > 0.1 ) {
            [self _playFile:dataTask.fileURL
                 fileOrigin:SJMP3PlayerFileOriginTmpCache
                currentTime:self.audioPlayer.currentTime];
        }
        if ( [self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(_self) self = _self;
                if ( !self ) return ;
                [self.delegate audioPlayer:self
                     audioDownloadProgress:progress];
            });
        }
    } success:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.isDownloaded = YES;
        self.downloadProgress = 1;
        [self.fileManager moveTmpFileToCache];
        if ( self.needToPlay ) {
            [self _playFile:self.fileManager.fileURL
                 fileOrigin:SJMP3PlayerFileOriginTmpCache
                currentTime:self.audioPlayer.currentTime];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:downloadFinishedForURL:)] ) {
                [self.delegate audioPlayer:self downloadFinishedForURL:URL];
            }
        });
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.isDownloaded = NO;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            [dataTask restart];
        });
        
        if ( self.enableDBUG ) {
            NSLog(@"\nSJMP3Player: -下载失败, 2秒后将重启下载. URL: %@, savePath: %@ \n", URL, self.fileManager.tmpFileURL);
        }
    }];
}

- (BOOL)_playFile:(NSURL *)fileURL fileOrigin:(SJMP3PlayerFileOrigin)origin {
    return [self _playFile:fileURL fileOrigin:origin currentTime:0];
}

- (BOOL)_playFile:(NSURL *)fileURL fileOrigin:(SJMP3PlayerFileOrigin)origin currentTime:(NSTimeInterval)currentTime {
    self.fileOrigin = origin;
    NSError *error = nil;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL
                                                                 fileTypeHint:AVFileTypeMPEGLayer3
                                                                        error:&error];
    if ( error ) {
        if ( [SJMP3PlayerFileManager isCachedForFileURL:fileURL] ) {
            [SJMP3PlayerFileManager delete:fileURL];
            NSLog(@"\nSJMP3Player: -播放失败, 已删除下载文件-%@ \n", fileURL);
        }
        
        if ( self.enableDBUG ) NSLog(@"\nSJMP3Player: -播放器初始化失败-%@-%@ \n", error, fileURL);
        return NO;
    }
    
    if ( !audioPlayer ) return NO;
    audioPlayer.enableRate = YES;
    if ( ![audioPlayer prepareToPlay] ) return NO;
    if ( self.audioDuration != 0 && self.needDownload ) {
        if ( !self.isDownloaded && audioPlayer.currentTime < self.audioDuration * 0.3 ) return NO;
    }
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

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if ( self.fileOrigin == SJMP3PlayerFileOriginTmpCache ) {
        if ( !self.isDownloaded ) return;
    }
    
    if ( self.enableDBUG ) {
        NSLog(@"\nSJMP3Player: -播放完毕\n-播放地址:%@", player.url);
    }
    
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
    NSLog(@"SJMP3Player: %@", error);
#ifdef DEBUG
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif

}


#pragma mark

- (void)_clearRefreshCurrentTimeTimer {
    if ( _refreshCurrentTimeTimer ) {
        [_refreshCurrentTimeTimer invalidate];
        _refreshCurrentTimeTimer = nil;
    }
}

- (void)activateRefreshTimeTimer {
    [self _clearRefreshCurrentTimeTimer];
    __weak typeof(self) _self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.refreshCurrentTimeTimer = [NSTimer SJMP3PlayerAdd_timerWithTimeInterval:0.2 block:^(NSTimer *timer) {
            __strong typeof(_self) self = _self;
            if ( !self ) {
                [timer invalidate];
                return ;
            }
            if ( !self.audioPlayer.isPlaying ) {
                [self _clearRefreshCurrentTimeTimer];
                return;
            }
            NSTimeInterval currentTime = self.audioPlayer.currentTime;
            NSTimeInterval totalTime = self.audioPlayer.duration;
            NSTimeInterval reachableTime = self.audioPlayer.duration * self.downloadProgress;
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:currentTime:reachableTime:totalTime:)] ) {
                [self.delegate audioPlayer:self currentTime:currentTime reachableTime:reachableTime totalTime:totalTime];
            }
        } repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.refreshCurrentTimeTimer forMode:NSRunLoopCommonModes];
    });
}

#pragma mark
- (void)_configRemoteEventReceiver {
    
    SEL sel = @selector(remoteControlReceivedWithEvent:);
    Method remoteControlReceivedWithEvent = class_getInstanceMethod([[UIApplication sharedApplication].delegate class], sel);
    class_replaceMethod([[UIApplication sharedApplication].delegate class], sel, (IMP)_sj_remoteControlReceived, method_getTypeEncoding(remoteControlReceivedWithEvent));
    objc_setAssociatedObject([UIApplication sharedApplication].delegate, sel, self, OBJC_ASSOCIATION_ASSIGN);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminateNotification) name:UIApplicationWillTerminateNotification object:nil];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActiveNotification) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];

}
- (void)audioSessionInterruptionNotification:(NSNotification *)notification{
    NSDictionary *info = notification.userInfo;
    if( (AVAudioSessionInterruptionType)[info[AVAudioSessionInterruptionTypeKey] integerValue] == AVAudioSessionInterruptionTypeBegan ) {
        [self pause];
    }
}

- (void)applicationWillResignActiveNotification {
    if ( !self.audioPlayer ) return;
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [(UIResponder *)[UIApplication sharedApplication].delegate becomeFirstResponder];
    [self _setPlayInfo];
}

- (void)applicationWillTerminateNotification {
    [(UIResponder *)[UIApplication sharedApplication].delegate resignFirstResponder];
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
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
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = mediaDict;
}

static void _sj_remoteControlReceived(id self, SEL _cmd, UIEvent *event) {
    SJMP3Player *player = objc_getAssociatedObject(self, _cmd);
    if ( UIEventTypeRemoteControl != event.type ) return;
    switch ( event.subtype ) {
        case UIEventSubtypeRemoteControlPlay: {
            [player resume];
        }
            break;
        case UIEventSubtypeRemoteControlPause: {
            [player pause];
        }
            break;
            
        case UIEventSubtypeRemoteControlNextTrack: {
            if ( ![player.delegate respondsToSelector:@selector(remoteEvent_NextWithAudioPlayer:)] ) return;
            [player.delegate remoteEvent_NextWithAudioPlayer:player];
        }
            break;
            
        case UIEventSubtypeRemoteControlPreviousTrack: {
            if ( ![player.delegate respondsToSelector:@selector(remoteEvent_PreWithAudioPlayer:)] ) return;
            [player.delegate remoteEvent_PreWithAudioPlayer:player];
        }
            break;
        default:
            break;
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
