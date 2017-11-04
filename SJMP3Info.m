//
//  SJMP3Info.m
//  Pods
//
//  Created by BlueDancer on 2017/11/4.
//
//

#import "SJMP3Info.h"

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
