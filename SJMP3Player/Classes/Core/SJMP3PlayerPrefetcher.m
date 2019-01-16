//
//  SJMP3PlayerPrefetcher.m
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import "SJMP3PlayerPrefetcher.h"
#import <SJDownloadDataTask/SJDownloadDataTask.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3PlayerPrefetcher ()
@property (nonatomic, strong, nullable) SJDownloadDataTask *task;
@property (strong, nullable) NSURL *URL;
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
- (void)prefetchAudioForURL:(NSURL *)URL toPath:(NSURL *)fileURL {
    if ( [_task.URLStr isEqualToString:URL.absoluteString] ) return;
    [self cancel];
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    self.URL = URL;
    __weak typeof(self) _self = self;
    _task = [SJDownloadDataTask downloadWithURLStr:URL.absoluteString toPath:fileURL append:YES progress:nil success:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        self.task = nil;
        if ( self.completionHandler ) self.completionHandler(self, YES);
    } failure:^(SJDownloadDataTask * _Nonnull dataTask) {
        __strong typeof(_self) self = _self;
        if ( !self ) return ;
        if ( self.completionHandler ) self.completionHandler(self, NO);
    }];
    dispatch_semaphore_signal(_lock);
}
- (void)cancel {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    [_task cancel];
    _task = nil;
    self.URL = nil;
    dispatch_semaphore_signal(_lock);
}
- (void)restart {
    [_task restart];
}
@end
NS_ASSUME_NONNULL_END
