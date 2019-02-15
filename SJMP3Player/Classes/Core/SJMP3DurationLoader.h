//
//  SJMP3DurationLoader.h
//  Pods
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3DurationLoader : NSObject
- (instancetype)initWithURL:(NSURL *)URL;
@property (readonly) NSTimeInterval duration;
@end
NS_ASSUME_NONNULL_END
