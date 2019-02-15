//
//  NSTimer+SJMP3PlayerAdd.m
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "NSTimer+SJMP3PlayerAdd.h"

@implementation NSTimer (SJMP3PlayerAdd)
+ (NSTimer *)SJMP3PlayerAdd_timerWithTimeInterval:(NSTimeInterval)ti
                                            block:(void(^)(NSTimer *timer))block
                                          repeats:(BOOL)repeats {
    NSTimer *timer = [NSTimer timerWithTimeInterval:ti
                                             target:self
                                           selector:@selector(SJMP3PlayerAdd_exeBlock:)
                                           userInfo:block
                                            repeats:repeats];
    return timer;
}

+ (void)SJMP3PlayerAdd_exeBlock:(NSTimer *)timer {
    void(^block)(NSTimer *timer) = timer.userInfo;
    if ( block ) block(timer);
    else [timer invalidate];
}
@end
