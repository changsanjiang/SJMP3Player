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
@end

@implementation SJMP3PlayerPrefetcher
- (nullable NSURL *)URL {
    if ( !_task ) return nil;
    return [NSURL URLWithString:_task.URLStr];
}
- (void)prefetchAudioForURL:(NSURL *)URL toPath:(NSURL *)fileURL {
    if ( [_task.URLStr isEqualToString:URL.absoluteString] ) return;
    [self cancel];
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
}
- (void)cancel {
    [_task cancel];
    _task = nil;
}
- (void)restart {
    [_task restart];
}
@end
NS_ASSUME_NONNULL_END
