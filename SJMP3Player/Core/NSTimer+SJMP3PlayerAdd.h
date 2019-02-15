//
//  NSTimer+SJMP3PlayerAdd.h
//  SJMP3Player_Example
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSTimer (SJMP3PlayerAdd)
+ (NSTimer *)SJMP3PlayerAdd_timerWithTimeInterval:(NSTimeInterval)ti
                                            block:(void(^)(NSTimer *timer))block
                                          repeats:(BOOL)repeats;
@end
