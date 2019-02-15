//
//  SJMP3PlayerPrefetcher.h
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3PlayerPrefetcher : NSObject
- (void)prefetchAudioForURL:(NSURL *)URL toPath:(NSURL *)fileURL completionHandler:(void(^)(SJMP3PlayerPrefetcher *prefetcher, BOOL finished))completionHandler;
- (void)cancel;
- (void)restart;
@end
NS_ASSUME_NONNULL_END
