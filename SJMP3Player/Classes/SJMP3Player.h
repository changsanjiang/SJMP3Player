//
//  SJMP3Player.h
//  SJMP3PlayWhileDownloadingProject
//
//  Created by BlueDancer on 2017/6/21.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN


@protocol SJMP3PlayerDelegate;

@interface SJMP3Player : NSObject

/*!
 *  default if No. */
@property (nonatomic, assign, readwrite) BOOL enableDBUG;

@property (nonatomic, weak,   readwrite) id<SJMP3PlayerDelegate> delegate;

@property (nonatomic, assign, readwrite) CGFloat rate;

@property (nonatomic, strong, readonly) NSString *currentPlayingURLStr;

@property (nonatomic, assign, readonly) BOOL playStatus;

/*!
 *  初始化 */
+ (instancetype)player;

/*!
 *  播放
 *  If you do not know, please set 5. */
- (void)playeAudioWithPlayURLStr:(NSString *)playURLStr minDuration:(double)minDuration;

/*!
 *  从指定的进度播放 */
- (void)setPlayProgress:(float)progress;

/*!
 *  暂停 */
- (void)pause;

/*!
 *  恢复播放 */
- (void)resume;

/*!
 *  停止播放, 停止缓存 */
- (void)stop;

/*!
 *  清除本地缓存 */
- (void)clearDiskAudioCache;

/*!
 *  已缓存的audios的大小 */
- (NSInteger)diskAudioCacheSize;

/*!
 *  查看音乐是否已缓存 */
- (BOOL)checkMusicHasBeenCachedWithPlayURL:(NSString *)playURL;

@end




#pragma mark -


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

- (void)audioPlayer:(SJMP3Player *)player audioDownloadProgress:(CGFloat)progress;

- (void)audioPlayer:(SJMP3Player *)player currentTime:(NSTimeInterval)currentTime reachableTime:(NSTimeInterval)reachableTime totalTime:(NSTimeInterval)totalTime;

- (void)audioPlayerDidFinishPlaying:(SJMP3Player *)player;

@end

NS_ASSUME_NONNULL_END
