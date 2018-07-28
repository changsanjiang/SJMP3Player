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

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                    append:(BOOL)shouldAppend // YES if newly written data should be appended to any existing file contents, otherwise NO.
                                  response:(nullable void(^)(SJDownloadDataTask *dataTask))responseBlock
                                  progress:(nullable void(^)(SJDownloadDataTask *dataTask, float progress))progressBlock
                                   success:(nullable void(^)(SJDownloadDataTask *dataTask))successBlock
                                   failure:(nullable void(^)(SJDownloadDataTask *dataTask))failureBlock;


/// 取消下载
- (void)cancel;
/// 重启, 重新启动下载
- (void)restart;
/// 是否追加数据. 调用重启之前, 建议设置此属性为YES
@property (nonatomic) BOOL shouldAppend;

@property (nonatomic, readonly) SJDownloadDataTaskIdentitifer identifier;

/// 速度改变的回调
@property (nonatomic, copy, nullable) void(^speedDidChangeExeBlock)(SJDownloadDataTask *dataTask);
/// 每秒速度, 单位: byte/s
@property (readonly) long long speed;

/// 报错
@property (nonatomic, strong, readonly, nullable) NSError *error;
/// URL
@property (nonatomic, strong, readonly) NSString *URLStr;
/// 路径
@property (nonatomic, strong, readonly) NSURL *fileURL;
/// 进度
@property (nonatomic, readonly) float progress;
/// 总size, 单位: byte
@property (readonly) long long totalSize; // response - total size. 服务器响应数据应写入的总大小
/// 已写入的size, 单位: byte
@property (readonly) long long wroteSize; // response - wrote size. 响应数据已写入的大小
// 文件实际的总大小
@property (readonly) long long fileTotalSize; // fileTotalSize = 下载之前本地已存在的文件大小 + 响应的大小`totalSize`
@end
NS_ASSUME_NONNULL_END
