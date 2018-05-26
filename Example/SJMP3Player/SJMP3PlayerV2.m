//
//  SJMP3PlayerV2.m
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "SJMP3PlayerV2.h"
#import <SJDownloadDataTask/SJDownloadDataTask.h>
#import <AVFoundation/AVFoundation.h>
#import "NSTimer+SJMP3PlayerAdd.h"

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3PlayerFileManager : NSObject
#pragma mark
+ (BOOL)delete:(NSURL *)fileURL;
+ (BOOL)isCached:(NSURL *)URL;
+ (BOOL)isCachedForFileURL:(NSURL *)fileURL;
+ (NSURL *)tmpFileURLPath:(NSURL *)URL; // remote file url
+ (void)clear;
+ (long long)cacheSize;

#pragma mark
- (void)changeURL:(NSURL *)URL;
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
    [self _checkoutCacheFolder];
    return self;
}

- (void)_checkoutCacheFolder {
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
- (void)changeURL:(NSURL *)URL {
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
    return [SJMP3PlayerFileManager.rootFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.mp3", (unsigned long)[URL.absoluteString hash]]];
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
+ (NSURL *)tmpFileURLPath:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self tmpFilePath:URL]];
}
+ (void)clear {
    [[self cacheFiles] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [[NSFileManager defaultManager] removeItemAtPath:obj error:nil];
    }];
}
+ (long long)cacheSize {
    __block NSInteger size = 0;
    [[self cacheFiles] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary<NSFileAttributeKey, id> *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:obj error:nil];
        size += [dict[NSFileSize] integerValue] / 1000 / 1000;
    }];
    return size;
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
@interface SJMP3PlayerV2()<AVAudioPlayerDelegate>
@property (nonatomic) dispatch_queue_t serialQueue;
@property (nonatomic, strong, readonly) SJMP3PlayerFileManager *fileManager;
@property (nonatomic, strong, nullable) NSTimer *refreshCurrentTimeTimer;
@property (nonatomic, strong, nullable) AVAudioPlayer *audioPlayer;

@property (nonatomic) BOOL userClickedPause;

#pragma mark
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property (nonatomic) BOOL needDownload;
@property (nonatomic) BOOL isStartPlaying;
@property (atomic) float downloadProgress;
@property (nonatomic) BOOL isDownloaded;
@end

@implementation SJMP3PlayerV2

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
    return self;
}

- (void)setRate:(float)rate {
    if ( isnan(rate) ) return;
    _rate = rate;
    if ( _audioPlayer && [_audioPlayer prepareToPlay] ) _audioPlayer.rate = rate;
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
    if ( ![_audioPlayer prepareToPlay] ) return NO;
    if ( self.needDownload ) {
        if ( sec / self.audioPlayer.duration > self.downloadProgress ) return NO;
    }
    self.audioPlayer.currentTime = sec;
    return YES;
}

- (void)pause {
    self.userClickedPause =  YES;
    [_audioPlayer pause];
}

- (void)resume {
    self.userClickedPause = NO;
    [_audioPlayer play];
    [self activateRefreshTimeTimer];
}

- (void)stop {
    [_task cancel];
    [_audioPlayer stop];
    _audioPlayer = nil;
}

- (void)clearDiskAudioCache {
    if ( self.isPlaying ) [self stop];
    [SJMP3PlayerFileManager clear];
}

- (NSInteger)diskAudioCacheSize {
    return [SJMP3PlayerFileManager cacheSize];
}

/*!
 *  查看音乐是否已缓存 */
- (BOOL)isCached:(NSURL *)URL {
    return [SJMP3PlayerFileManager isCached:URL];
}

#pragma mark
- (void)playWithURL:(NSURL *)URL minDuration:(double)minDuration {
    if ( !URL ) return;
    __weak typeof(self) _self = self;
    dispatch_async(_serialQueue, ^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.needDownload = NO;
        self.isStartPlaying = NO;
        self.isDownloaded = NO;
        
        if ( URL.isFileURL ) {
            self.isStartPlaying = [self _playFile:URL currentTime:0];
            return;
        }
        
        self.minDuration = minDuration;
        [self.fileManager changeURL:URL];
        if ( _fileManager.isCached ) {
            self.isStartPlaying = [self _playFile:self.fileManager.fileURL currentTime:0];
            return;
        }
        
        self.needDownload = YES;
        __weak typeof(self) _self = self;
        _task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:self.fileManager.tmpFileURL append:YES progress:^(SJDownloadDataTask * _Nonnull dataTask, float progress) {
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            if ( !self.isStartPlaying && progress > 0.1 ) {
                self.isStartPlaying = [self _playFile:dataTask.fileURL currentTime:0];
            }
            if ( [self.delegate respondsToSelector:@selector(audioPlayer:audioDownloadProgress:)] ) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(_self) self = _self;
                    if ( !self ) return ;
                    [self.delegate audioPlayer:self audioDownloadProgress:progress];
                });
            }
            self.downloadProgress = progress;
        } success:^(SJDownloadDataTask * _Nonnull dataTask) {
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            [self.fileManager moveTmpFileToCache];
            if ( !self.isStartPlaying ) {
                [self _playFile:self.fileManager.fileURL currentTime:self.audioPlayer.currentTime];
            }
            self.isDownloaded = YES;
        } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
            __strong typeof(_self) self = _self;
            if ( !self ) return ;
            self.isDownloaded = NO;
            [self.fileManager deleteTmpFile];
        }];
    });
}


- (BOOL)_playFile:(NSURL *)fileURL currentTime:(NSTimeInterval)currentTime {
    NSError *error = nil;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL fileTypeHint:AVFileTypeMPEGLayer3 error:&error];
    if ( error ) {
        if ( [SJMP3PlayerFileManager isCachedForFileURL:fileURL] ) {
            [SJMP3PlayerFileManager delete:fileURL];
            NSLog(@"\nSJMP3PlayerV2: -播放失败, 已删除下载文件-%@ \n", fileURL);
        }
        
        if ( self.enableDBUG ) NSLog(@"\nSJMP3PlayerV2: -播放器初始化失败-%@-%@ \n", error, fileURL);
        return NO;
    }
    
    if ( !audioPlayer ) return NO;
    audioPlayer.enableRate = YES;
    if ( ![audioPlayer prepareToPlay] ) return NO;
    if ( audioPlayer.duration < _minDuration ) return NO;
    audioPlayer.delegate = self;
    audioPlayer.currentTime = currentTime;
    [audioPlayer play];
    audioPlayer.rate = self.rate;
    if ( self.enableDBUG ) {
        NSLog(@"\nSJMP3PlayerV2: -开始播放\n-持续时间: %f 秒\n-播放地址为: %@ ", audioPlayer.duration, fileURL);
        if ( @available(ios 10, *) ) NSLog(@"\n-格式%@", audioPlayer.format);
    }
    _audioPlayer = audioPlayer;
    [self activateRefreshTimeTimer];
    return YES;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if ( ![self.currentURL isFileURL] ) {
        if ( !self.isDownloaded ) return;
    }
    
    if ( self.enableDBUG ) {
        NSLog(@"\nSJMP3PlayerV2: -播放完毕\n-播放地址:%@", player.url);
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
    NSLog(@"SJMP3PlayerV2: %@", error);
}


#pragma mark

- (void)activateRefreshTimeTimer {
    if ( _refreshCurrentTimeTimer ) {
        [_refreshCurrentTimeTimer invalidate];
        _refreshCurrentTimeTimer = nil;
    }
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
                [timer invalidate];
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
@end
NS_ASSUME_NONNULL_END
