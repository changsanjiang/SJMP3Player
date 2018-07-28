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

@interface NSTimer (SJDownloadDataTaskAdd)
+ (NSTimer *)DownloadDataTaskAdd_timerWithTimeInterval:(NSTimeInterval)ti
                                      block:(void(^)(NSTimer *timer))block
                                    repeats:(BOOL)repeats;
@end

@implementation NSTimer (SJDownloadDataTaskAdd)
+ (NSTimer *)DownloadDataTaskAdd_timerWithTimeInterval:(NSTimeInterval)ti
                                      block:(void(^)(NSTimer *timer))block
                                    repeats:(BOOL)repeats {
    NSTimer *timer = [NSTimer timerWithTimeInterval:ti
                                             target:self
                                           selector:@selector(DownloadDataTaskAdd_exeBlock:)
                                           userInfo:block
                                            repeats:repeats];
    return timer;
}

+ (void)DownloadDataTaskAdd_exeBlock:(NSTimer *)timer {
    void(^block)(NSTimer *timer) = timer.userInfo;
    if ( block ) block(timer);
    else [timer invalidate];
}

@end


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
#ifdef DEBUG
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif
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
@property long long wroteSize;
@property long long totalSize;
@property long long fileTotalSize;
@property long long speed;
@property (nonatomic) long long wroteSize_old;
@property (nonatomic, strong, nullable) NSTimer *refreshSpeedTimer;

#pragma mark
@property (nonatomic, copy, nullable) void(^responseBlock)(SJDownloadDataTask *dataTask);
@property (nonatomic, copy, nullable) void(^progressBlock)(SJDownloadDataTask *dataTask, float progress);
@property (nonatomic, copy, nullable) void(^successBlock)(SJDownloadDataTask *dataTask);
@property (nonatomic, copy, nullable) void(^failureBlock)(SJDownloadDataTask *dataTask);

@property (nonatomic, weak, nullable) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong, nullable) NSError *error;

@property (nonatomic) SJDownloadDataTaskIdentitifer identifier;
@property (nonatomic, strong) NSString *URLStr;
@property (nonatomic, strong) NSURL *fileURL;
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
   return [self downloadWithURLStr:URLStr
                            toPath:fileURL
                            append:shouldAppend
                          response:nil
                          progress:progressBlock
                           success:successBlock
                           failure:failureBlock];
}

+ (SJDownloadDataTask *)downloadWithURLStr:(NSString *)URLStr
                                    toPath:(NSURL *)fileURL
                                    append:(BOOL)shouldAppend // YES if newly written data should be appended to any existing file contents, otherwise NO.
                                  response:(nullable void(^)(SJDownloadDataTask *dataTask))responseBlock
                                  progress:(nullable void(^)(SJDownloadDataTask *dataTask, float progress))progressBlock
                                   success:(nullable void(^)(SJDownloadDataTask *dataTask))successBlock
                                   failure:(nullable void(^)(SJDownloadDataTask *dataTask))failureBlock {
    SJDownloadDataTask *sjTask = [SJDownloadDataTask new];
    sjTask.URLStr = URLStr;
    sjTask.fileURL = fileURL;
    sjTask.responseBlock = responseBlock;
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
        printf("\nSJDownloadDataTask: 此次下载将覆盖原始文件数据(如果此路径存在文件:[%s])\n", fileURL.absoluteString.UTF8String);
#endif
    }
    else {
        // 已写入的文件大小
        long long wroteSize = 0;
        request = [NSMutableURLRequest requestWithURL:URL
                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                      timeoutInterval:0];
        wroteSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] valueForKey:NSFileSize] longLongValue];
        [(NSMutableURLRequest *)request setValue:[NSString stringWithFormat:@"bytes=%lld-", wroteSize] forHTTPHeaderField:@"Range"];
        
#ifdef DEBUG
        printf("\nSJDownloadDataTask: 此次下载为追加模式, 将会向文件中追加剩余数据. 当前文件大小为: %lld\n", wroteSize);
#endif
    }
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request];
    return dataTask;
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SJDownloadDataTask *sjTask = dataTask.sj_downloadDataTask;
    
    // create output stream
    if ( !dataTask.sj_outputStream ) {
        dataTask.sj_outputStream = [[SJOutPutStream alloc] initWithPath:sjTask.fileURL append:sjTask.shouldAppend];
    }
    
    if ( response.expectedContentLength == 0 ) {
        completionHandler(NSURLSessionResponseCancel);
        if ( sjTask.successBlock ) sjTask.successBlock(sjTask);

#ifdef DEBUG
        printf("\nSJDownloadDataTask: 接收到服务器响应, 但返回响应的文件大小为 0, 该文件可能已下载完毕. 我将取消本次请求, 并回调`successBlock`\n");
#endif
    }
    else {
        sjTask.totalSize = response.expectedContentLength;
        sjTask.fileTotalSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:sjTask.fileURL.path error:nil] valueForKey:NSFileSize] longLongValue] + response.expectedContentLength;
        completionHandler(NSURLSessionResponseAllow);
        if ( sjTask.responseBlock ) sjTask.responseBlock(sjTask);

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
        printf("\nSJDownloadDataTask: 下载被取消, 下载标识:%ld \n", (unsigned long)dataTask.taskIdentifier);
#endif
        return;
    }
    
    if ( error ) {
        sjTask.error = error;
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

- (void)cancel {
    if ( _refreshSpeedTimer ) {
        [_refreshSpeedTimer invalidate];
        _refreshSpeedTimer = nil;
    }
    
    if ( self.speed != 0 ) self.speed = 0;
    
    if ( self.dataTask && self.dataTask.state != NSURLSessionTaskStateCanceling && self.dataTask.state != NSURLSessionTaskStateCompleted ) {
        [self.dataTask cancel];
        self.dataTask.sj_outputStream = nil;
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
    __weak typeof(self) _self = self;
    _refreshSpeedTimer = [NSTimer DownloadDataTaskAdd_timerWithTimeInterval:0.2 block:^(NSTimer * _Nonnull timer) {
        __strong typeof(_self) self = _self;
        if ( !self ) {
            [timer invalidate];
            return ;
        }
        if ( !self.dataTask || self.dataTask.state != NSURLSessionTaskStateRunning ) {
            self.speed = 0;
            [self.refreshSpeedTimer invalidate];
            self.refreshSpeedTimer = nil;
            return ;
        }
        long long wroteSize_now = self.wroteSize;
        long long wroteSize_old = self.wroteSize_old;
        if ( wroteSize_old != 0 ) self.speed = (wroteSize_now - wroteSize_old) / timer.timeInterval;
        self.wroteSize_old = wroteSize_now;
    } repeats:YES];
    self.wroteSize_old = self.wroteSize;
    [[NSRunLoop mainRunLoop] addTimer:_refreshSpeedTimer forMode:NSRunLoopCommonModes];
    [_refreshSpeedTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_refreshSpeedTimer.timeInterval]];
    
#ifdef DEBUG
    printf("\nSJDownloadDataTask: 准备下载: %s, 保存路径:%s, 下载标识:%ld \n", [self.URLStr UTF8String], [[self.fileURL absoluteString] UTF8String], (unsigned long)task.taskIdentifier);
#endif
}

@synthesize speed = _speed;
- (void)setSpeed:(long long)speed {
    @synchronized(self) {
        _speed = speed;
        if ( _speedDidChangeExeBlock ) _speedDidChangeExeBlock(self);
    }
}

- (long long)speed {
    @synchronized(self) {
        return _speed;
    }
}
@end
NS_ASSUME_NONNULL_END
