//
//  SJMP3Player.h
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol SJMP3PlayerDelegate;

@interface SJMP3Player : NSObject

+ (instancetype)player;

- (void)playWithURL:(NSURL *)URL;

@property (nonatomic, weak, nullable) id <SJMP3PlayerDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic) float rate;
@property (nonatomic) BOOL enableDBUG;

/// 跳转
- (BOOL)seekToTime:(NSTimeInterval)sec;

/// 暂停
- (void)pause;

/// 恢复播放
- (void)resume;

/// 停止播放, 停止缓存
- (void)stop;

/// 清除本地缓存
- (void)clearDiskAudioCache;

/// 清除临时缓存
- (void)clearTmpAudioCache;

/// 已缓存的audios的大小 bytes
- (long long)diskAudioCacheSize;

/// 查看音乐是否已缓存
- (BOOL)isCached:(NSURL *)URL;

@end


@interface SJMP3Info : NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *artist;
@property (nonatomic, strong) UIImage *cover;

- (instancetype)initWithTitle:(NSString *)title artist:(NSString *)artist cover:(UIImage *)cover;
@end


@protocol SJMP3PlayerDelegate <NSObject>

@required
/// 用于显示在锁屏界面 Control Center 的信息
- (SJMP3Info *)playInfo;

/// 点击了锁屏界面 Control Center 下一首按钮
- (void)remoteEvent_NextWithAudioPlayer:(SJMP3Player *)player;

/// 点击了锁屏界面 Control Center 上一首按钮
- (void)remoteEvent_PreWithAudioPlayer:(SJMP3Player *)player;

@optional
/// 下载的进度回调
- (void)audioPlayer:(SJMP3Player *)player audioDownloadProgress:(CGFloat)progress;

/// 下载完成的回调
- (void)audioPlayer:(SJMP3Player *)player downloadFinishedForURL:(NSURL *)URL;

/// 播放相关时间的回调
/// - currentTime   当前时间
/// - reachableTime 可以播放到的时间(已下载的部分, 未下载的部分无法播放)
/// - totalTime     全部时间
- (void)audioPlayer:(SJMP3Player *)player currentTime:(NSTimeInterval)currentTime reachableTime:(NSTimeInterval)reachableTime totalTime:(NSTimeInterval)totalTime;

/// 播放完毕的回调
- (void)audioPlayerDidFinishPlaying:(SJMP3Player *)player;

/// 控制台进行了暂停操作
- (void)remoteEventPausedForAudioPlayer:(SJMP3Player *)player;

/// 控制台进行了播放操作
- (void)remoteEventPlayedForAudioPlayer:(SJMP3Player *)player;

/// 预加载
/// 如果想提前下载`前一首歌曲`, 请返回相应的URL
/// 当前播放的音频下载完成后, 会调用此方法, 优先下载`nextAudio`
- (nullable NSURL *)prefetchURLOfPreviousAudio;

/// 预加载
/// 如果想提前下载`下一首歌曲`, 请返回相应的URL
/// 当前播放的音频下载完成后, 会调用此方法, 优先下载`nextAudio`
- (nullable NSURL *)prefetchURLOfNextAudio;

@end
NS_ASSUME_NONNULL_END
