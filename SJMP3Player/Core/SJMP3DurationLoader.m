//
//  SJMP3DurationLoader.m
//  Pods
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "SJMP3DurationLoader.h"
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3DurationLoader ()
@property (nonatomic, strong, readonly) AVAsset *asset;
@property NSTimeInterval duration;
@end

@implementation SJMP3DurationLoader
- (instancetype)initWithURL:(NSURL *)URL {
    self = [super init];
    if ( !self ) return nil;
    // AVURLAssetPreferPreciseDurationAndTimingKey
    // 传递该选项暗示了开发者希望得到稍长一点的加载时间, 以获取更准确的时长及时间信息
    _asset = [AVAsset assetWithURL:URL];
    __weak typeof(self) _self = self;
    [_asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        NSTimeInterval duration = CMTimeGetSeconds(self.asset.duration);
        self.duration = duration;
    }];
    return self;
}
- (void)dealloc {
    [_asset cancelLoading];
}
@end
NS_ASSUME_NONNULL_END
