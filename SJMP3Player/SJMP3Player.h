//
//  SJMP3Player.h
//  Pods
//
//  Created by BlueDancer on 2019/6/25.
//

#import <Foundation/Foundation.h>
@protocol SJMP3PlayerDelegate;

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3Player : NSObject
+ (nullable instancetype)playerWithURL:(NSURL *)URL;
- (nullable instancetype)initWithURL:(NSURL *)URL;

@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) float downloadProgress;
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic) BOOL mute;

- (void)resume;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)secs;

@property (nonatomic, weak, nullable) id<SJMP3PlayerDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) NSURL *URL;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol SJMP3PlayerDelegate<NSObject>
@optional
/// 下载进度的回调
///
- (void)mp3Player:(SJMP3Player *)player downloadProgressDidChange:(float)progress;

/// 播放完毕的回调
///
- (void)mp3PlayerDidFinishPlaying:(SJMP3Player *)player;

/// 初始化失败
///
- (void)mp3Player:(SJMP3Player *)player initializationFailed:(NSError *)error;

/// 播放时间改变的回调
///
- (void)mp3Player:(SJMP3Player *)player currentTimeDidChange:(NSTimeInterval)currentTime;

/// 播放时长改变的回调
///
- (void)mp3Player:(SJMP3Player *)player durationDidChange:(NSTimeInterval)duration;

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
