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
    SJDownloadDataTask *sjTask = [SJDownloadDataTask new];
    sjTask.URLStr = URLStr;
    sjTask.fileURL = fileURL;
    sjTask.progressBlock = progressBlock;
    sjTask.successBlock = successBlock;
    sjTask.failureBlock = failureBlock;
    sjTask.shouldAppend = shouldAppend;
    [sjTask restart];
    return sjTask;
}

+ (NSURLSessionDataTask *)downloadTaskWithURLStr:(NSString *)URLStr toPath:(NSURL *)fileURL append:(BOOL)shouldAppend {
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
    if ( !shouldAppend ) {
        request = [NSURLRequest requestWithURL:URL];
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 此次下载将覆盖原始文件数据(如果[%s]存在文件)\n", fileURL.absoluteString.UTF8String);
#endif
    }
    else {
        long long wroteSize = 0;
        request = [NSMutableURLRequest requestWithURL:URL
                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                      timeoutInterval:0];
        wroteSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] valueForKey:NSFileSize] longLongValue];
        [(NSMutableURLRequest *)request setValue:[NSString stringWithFormat:@"bytes=%lld-", wroteSize]
                              forHTTPHeaderField:@"Range"];
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 此次下载为追加模式, 将会向文件中追加剩余数据. 当前文件大小为: %lld\n", wroteSize);
#endif
    }
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request];
    return dataTask;
}

- (void)cancel {
    if ( self.dataTask && self.dataTask.state != NSURLSessionTaskStateCanceling ) {
        [self.dataTask cancel];
        self.dataTask = nil;
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 下载被取消, URL: %s, 下载标识:%ld \n", [self.URLStr UTF8String], self.dataTask.taskIdentifier);
#endif
    }
}

- (void)restart {
    [self cancel];
    NSURLSessionDataTask *task = [[self class] downloadTaskWithURLStr:self.URLStr toPath:self.fileURL append:self.shouldAppend];
    self.dataTask = task;
    task.sj_downloadDataTask = self;
    [task resume];
    
#ifdef DEBUG
    printf("\nSJDownloadDataTask: 准备下载: %s, 保存路径:%s, 下载标识:%ld \n", [self.URLStr UTF8String], [[self.fileURL absoluteString] UTF8String], (unsigned long)task.taskIdentifier);
#endif
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    if ( !dataTask.sj_outputStream ) {
        dataTask.sj_outputStream = [[SJOutPutStream alloc] initWithPath:sjTask.fileURL append:sjTask.shouldAppend];
    }
    sjTask.totalSize = response.expectedContentLength;
    if ( response.expectedContentLength == 0 ) {
        completionHandler(NSURLSessionResponseCancel);
        if ( sjTask.successBlock ) sjTask.successBlock(sjTask);
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 接收到服务器响应, 但返回响应的文件大小为 0, 该文件可能已下载完毕. 我将取消本次请求, 并回调`successBlock`\n");
#endif
    }
    else {
        completionHandler(NSURLSessionResponseAllow);
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 接收到服务器响应, 文件总大小: %lld, 下载标识:%ld \n", sjTask.totalSize, (unsigned long)dataTask.taskIdentifier);
#endif
    }
    
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [dataTask.sj_outputStream write:data];
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    sjTask.wroteSize += data.length;
    
    float progress = sjTask.progress;
    if ( sjTask.progressBlock ) sjTask.progressBlock(sjTask, progress);
    
#ifdef DEBUG
    printf("\nSJDownloadDataTask: 写入大小: %lld, 文件大小: %lld, 下载进度: %f", sjTask.wroteSize, sjTask.totalSize, progress);
#endif
}

+ (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask didCompleteWithError:(NSError *)error {
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    if ( error.code == NSURLErrorCancelled ) {
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 取消下载, 下载标识:%ld \n", (unsigned long)dataTask.taskIdentifier);
#endif
        return;
    }
    
    if ( error ) {
        if ( sjTask.failureBlock ) sjTask.failureBlock(sjTask);
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 下载错误, error: %s, 下载标识:%ld \n", [error.description UTF8String], (unsigned long)dataTask.taskIdentifier);
#endif
        return;
    }
    
    if ( sjTask.successBlock ) sjTask.successBlock(sjTask);
    
#ifdef DEBUG
    printf("\nSJDownloadDataTask: 文件下载完成, 下载标识: %ld, 保存路径:%s \n", (unsigned long)dataTask.taskIdentifier, [[sjTask fileURL].path UTF8String]);
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
