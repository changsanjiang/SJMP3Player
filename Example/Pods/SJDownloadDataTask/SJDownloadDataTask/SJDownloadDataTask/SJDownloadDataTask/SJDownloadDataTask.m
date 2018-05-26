//
//  SJDownloadDataTask.m
//  SJDownloadDataTask
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 畅三江. All rights reserved.
//

#import "SJDownloadDataTask.h"
#import <objc/message.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJOutPutStream : NSObject
- (instancetype)initWithPath:(NSURL *)filePath append:(BOOL)shouldAppend;
- (NSInteger)write:(NSData *)data;
@end

@implementation SJOutPutStream {
    NSOutputStream *_outputStream;
}
- (instancetype)initWithPath:(NSURL *)filePath append:(BOOL)shouldAppend {
    self = [super init];
    if ( !self ) return nil;
    _outputStream = [[NSOutputStream alloc] initWithURL:filePath append:shouldAppend];
    [_outputStream open];
    return self;
}
- (NSInteger)write:(NSData *)data {
    return [_outputStream write:data.bytes maxLength:data.length];
}
- (void)dealloc {
    NSLog(@"%s %d", __func__, (int)__LINE__);
    [_outputStream close];
}
@end


#pragma mark -
@interface NSURLSessionTask (SJDownloadDataTaskAdd)
@property (nonatomic, strong) SJDownloadDataTask *sj_downloadDataTask;
@property (nonatomic, strong, nullable) SJOutPutStream *sj_outputStream;
@end

@implementation NSURLSessionTask (SJDownloadDataTaskAdd)
- (void)setSj_downloadDataTask:(SJDownloadDataTask *)sj_downloadDataTask {
    objc_setAssociatedObject(self, @selector(sj_downloadDataTask), sj_downloadDataTask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (SJDownloadDataTask *)sj_downloadDataTask {
    return objc_getAssociatedObject(self, _cmd);
}
- (void)setSj_outputStream:(nullable SJOutPutStream *)sj_outputStream {
    objc_setAssociatedObject(self, @selector(sj_outputStream), sj_outputStream, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (nullable SJOutPutStream *)sj_outputStream {
    return objc_getAssociatedObject(self, _cmd);
}
@end


#pragma mark -
@interface SJDownloadDataTask ()<NSURLSessionDelegate>

#pragma mark
@property (nonatomic) long long wroteSize;
@property (nonatomic) long long totalSize;

#pragma mark
@property (nonatomic, copy, nullable) void(^progressBlock)(SJDownloadDataTask *dataTask, float progress);
@property (nonatomic, copy, nullable) void(^successBlock)(SJDownloadDataTask *dataTask);
@property (nonatomic, copy, nullable) void(^failureBlock)(SJDownloadDataTask *dataTask);
@property (nonatomic) SJDownloadDataTaskIdentitifer identifier;
@property (nonatomic, strong) NSString *URLStr;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic) BOOL shouldAppend;
@property (nonatomic, weak, nullable) NSURLSessionDataTask *dataTask;
@end

@implementation SJDownloadDataTask

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                  progress:(nullable void (^)(SJDownloadDataTask * _Nonnull, float))progressBlock
                                   success:(nullable void (^)(SJDownloadDataTask * _Nonnull))successBlock
                                   failure:(nullable void (^)(SJDownloadDataTask * _Nonnull))failureBlock {
    return [self downloadWithURLStr:URLStr
                             toPath:fileURL
                             append:NO
                           progress:progressBlock
                            success:successBlock
                            failure:failureBlock];
}

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                    append:(BOOL)shouldAppend // YES if newly written data should be appended to any existing file contents, otherwise NO.
                                  progress:(nullable void(^)(SJDownloadDataTask *dataTask, float progress))progressBlock
                                   success:(nullable void(^)(SJDownloadDataTask *dataTask))successBlock
                                   failure:(nullable void(^)(SJDownloadDataTask *dataTask))failureBlock {
    NSURL *URL = [NSURL URLWithString:URLStr];
    NSParameterAssert(URL);
    NSParameterAssert(fileURL);
    static NSURLSession *session;
    static NSOperationQueue *taskQueue;
    
    if ( !taskQueue ) {
        taskQueue = [NSOperationQueue new];
        taskQueue.maxConcurrentOperationCount = 1;
        taskQueue.name = @"com.sjmediadownloader.taskqueue";
    }
    if ( !session ) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        session = [NSURLSession sessionWithConfiguration:config delegate:(id)self delegateQueue:taskQueue];
    }
    
    NSURLRequest *request = nil;
    long long wroteSize = 0;
    if ( !shouldAppend ) {
        request = [NSURLRequest requestWithURL:URL];
    }
    else {
        request = [NSMutableURLRequest requestWithURL:URL
                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                      timeoutInterval:0];
        wroteSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] valueForKey:NSFileSize] longLongValue];
        [(NSMutableURLRequest *)request setValue:[NSString stringWithFormat:@"bytes=%lld-", wroteSize]
                              forHTTPHeaderField:@"Range"];
    }
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request];
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask = [SJDownloadDataTask new];
    sjTask.dataTask = dataTask;
    sjTask.URLStr = URLStr;
    sjTask.fileURL = fileURL;
    sjTask.progressBlock = progressBlock;
    sjTask.successBlock = successBlock;
    sjTask.failureBlock = failureBlock;
    sjTask.shouldAppend = shouldAppend;
    sjTask.wroteSize = wroteSize;
    [dataTask resume];
    
#ifdef DEBUG
    printf("\n准备下载: %s, 保存路径:%s, 下载标识:%ld \n", [URLStr UTF8String], [[fileURL absoluteString] UTF8String], (unsigned long)dataTask.taskIdentifier);
#endif
    return sjTask;
}

- (void)cancel {
    [self.dataTask cancel];
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    if ( !dataTask.sj_outputStream ) {
        dataTask.sj_outputStream = [[SJOutPutStream alloc] initWithPath:sjTask.fileURL append:sjTask.shouldAppend];
    }
    sjTask.totalSize = response.expectedContentLength;
    completionHandler(NSURLSessionResponseAllow);
    
#ifdef DEBUG
    printf("\n接收到服务器响应, 文件总大小: %lld, 下载标识:%ld \n", sjTask.totalSize, (unsigned long)dataTask.taskIdentifier);
#endif
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [dataTask.sj_outputStream write:data];
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    sjTask.wroteSize += data.length;
    
    float progress = sjTask.progress;
    if ( sjTask.progressBlock ) sjTask.progressBlock(sjTask, progress);
    
#ifdef DEBUG
    printf("\n写入大小: %lld, 文件大小: %lld, 下载进度: %f", sjTask.wroteSize, sjTask.totalSize, progress);
#endif
}

+ (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask didCompleteWithError:(NSError *)error {
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    if ( error.code == NSURLErrorCancelled ) {
        
#ifdef DEBUG
        printf("\n取消下载, 下载标识:%ld \n", (unsigned long)dataTask.taskIdentifier);
#endif
        return;
    }
    
    if ( error ) {
        if ( sjTask.failureBlock ) sjTask.failureBlock(sjTask);
        
#ifdef DEBUG
        printf("\n下载错误, error: %s, 下载标识:%ld \n", [error.description UTF8String], (unsigned long)dataTask.taskIdentifier);
#endif
        return;
    }
    
    if ( sjTask.successBlock ) sjTask.successBlock(sjTask);
    
#ifdef DEBUG
    printf("\n文件下载完成, 下载标识: %ld, 保存路径:%s \n", (unsigned long)dataTask.taskIdentifier, [[sjTask fileURL].path UTF8String]);
#endif
}

- (float)progress {
    return _totalSize == 0 ? 0 : _wroteSize * 1.0 / _totalSize;
}

- (SJDownloadDataTaskIdentitifer)identifier {
    return (SJDownloadDataTaskIdentitifer)_dataTask.taskIdentifier;
}
@end
NS_ASSUME_NONNULL_END
