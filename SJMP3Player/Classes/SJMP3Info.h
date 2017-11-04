//
//  SJMP3Info.h
//  Pods
//
//  Created by BlueDancer on 2017/11/4.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJMP3Info : NSObject

@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *artist;
@property (nonatomic, strong) UIImage *cover;

- (instancetype)initWithTitle:(NSString *)title artist:(NSString *)artist cover:(UIImage *)cover;

@end

NS_ASSUME_NONNULL_END
