//
//  SJDownloadDataTask.h
//  SJDownloadDataTask
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 畅三江. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NSUInteger SJDownloadDataTaskIdentitifer;

@interface SJDownloadDataTask : NSObject

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                  progress:(nullable void(^)(SJDownloadDataTask *dataTask, float progress))progressBlock
                                   success:(nullable void(^)(SJDownloadDataTask *dataTask))successBlock
                                   failure:(nullable void(^)(SJDownloadDataTask *dataTask))failureBlock;

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                    append:(BOOL)shouldAppend // YES if newly written data should be appended to any existing file contents, otherwise NO.
                                  progress:(nullable void(^)(SJDownloadDataTask *dataTask, float progress))progressBlock
                                   success:(nullable void(^)(SJDownloadDataTask *dataTask))successBlock
                                   failure:(nullable void(^)(SJDownloadDataTask *dataTask))failureBlock;

- (void)cancel; // 取消下载
- (void)restart; // 重启, 重新启动下载

#pragma mark
@property (nonatomic, readonly) SJDownloadDataTaskIdentitifer identifier;
@property (nonatomic, strong, readonly) NSString *URLStr;
@property (nonatomic, strong, readonly) NSURL *fileURL;
@property (nonatomic, readonly) long long totalSize;
@property (nonatomic, readonly) long long wroteSize;
@property (nonatomic, readonly) float progress;
@end
NS_ASSUME_NONNULL_END
