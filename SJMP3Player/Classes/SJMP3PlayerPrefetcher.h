//
//  SJMP3PlayerPrefetcher.h
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import <Foundation/Foundation.h>
#import "SJMP3PlayerFileManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3PlayerPrefetcher : NSObject
@property (nonatomic, strong, readonly, nullable) NSURL *URL;
- (void)prefetchAudioForURL:(NSURL *)URL toPath:(NSURL *)fileURL;
- (void)cancel;
- (void)restart;
@end
NS_ASSUME_NONNULL_END
