//
//  SJMP3PlayerPrefetcher.m
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import "SJMP3PlayerPrefetcher.h"
#import <SJDownloadDataTask/SJDownloadDataTask.h>

NS_ASSUME_NONNULL_BEGIN
#define SJMP3PlayerPrefetcherLock()   dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
#define SJMP3PlayerPrefetcherUnlock() dispatch_semaphore_signal(self->_lock);

@interface SJMP3PlayerPrefetcher ()
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@end

@implementation SJMP3PlayerPrefetcher {
    dispatch_semaphore_t _lock;
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _lock = dispatch_semaphore_create(1);
    return self;
}
- (void)prefetchAudioForURL:(NSURL *)URL toPath:(NSURL *)fileURL completionHandler:(void (^)(SJMP3PlayerPrefetcher * _Nonnull, BOOL))completionHandler {
    [self cancel];
    SJMP3PlayerPrefetcherLock();
    __weak typeof(self) _self = self;
    _task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:fileURL append:YES progress:nil success:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.task = nil;
        if ( completionHandler ) completionHandler(self, YES);
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( completionHandler ) completionHandler(self, NO);
    }];
    SJMP3PlayerPrefetcherUnlock();
}
- (void)cancel {
    SJMP3PlayerPrefetcherLock();
    [_task cancel];
    _task = nil;
    SJMP3PlayerPrefetcherUnlock();
}
- (void)restart {
    SJMP3PlayerPrefetcherLock();
    [_task restart];
    SJMP3PlayerPrefetcherUnlock();
}
@end
NS_ASSUME_NONNULL_END
