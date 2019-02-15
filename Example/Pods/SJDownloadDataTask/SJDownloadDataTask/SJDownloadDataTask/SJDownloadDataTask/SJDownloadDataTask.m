//
//  SJDownloadDataTask.m
//  SJDownloadDataTask
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 畅三江. All rights reserved.
//

#import "SJDownloadDataTask.h"
#import <objc/message.h>
#import "NSTimer+SJDownloadDataTaskAdd.h"
#import "SJOutPutStream.h"
#import <SJObserverHelper/NSObject+SJObserverHelper.h>

NS_ASSUME_NONNULL_BEGIN
#define SJDownloadDataTaskSafeExeMethod() \
if ( ![NSThread.currentThread isMainThread] ) { \
    [self performSelector:_cmd onThread:NSThread.mainThread withObject:nil waitUntilDone:NO]; \
    return; \
}

#define SJDownloadDataTaskContainerLock()   dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
#define SJDownloadDataTaskContainerUnlock() dispatch_semaphore_signal(self->_lock);
@interface SJDownloadDataTaskContainer : NSObject
+ (instancetype)shared;

- (void)insertTask:(SJDownloadDataTask *)sjTask forIdentifier:(NSUInteger)taskIdentifier;
- (void)removeTaskForIdentifier:(NSUInteger)taskIdentifier;
- (nullable SJDownloadDataTask *)taskForIdentifier:(NSUInteger)taskIdentifier;
@end

@implementation SJDownloadDataTaskContainer {
    NSMutableDictionary *_dict;
    dispatch_semaphore_t _lock;
}

+ (instancetype)shared {
    static id _instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [self new];
    });
    return _instance;
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _lock = dispatch_semaphore_create(1);
    _dict = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)_taskKeyForIdentifier:(NSUInteger)taskIdentifier {
    return [NSString stringWithFormat:@"%lu", (unsigned long)taskIdentifier];
}

- (void)insertTask:(SJDownloadDataTask *)sjTask forIdentifier:(NSUInteger)taskIdentifier {
    SJDownloadDataTaskContainerLock();
    [_dict setValue:sjTask forKey:[self _taskKeyForIdentifier:taskIdentifier]];
    SJDownloadDataTaskContainerUnlock();
}

- (void)removeTaskForIdentifier:(NSUInteger)taskIdentifier {
    SJDownloadDataTaskContainerLock();
    [_dict removeObjectForKey:[self _taskKeyForIdentifier:taskIdentifier]];
    SJDownloadDataTaskContainerUnlock();
}

- (nullable SJDownloadDataTask *)taskForIdentifier:(NSUInteger)taskIdentifier {
    return _dict[[self _taskKeyForIdentifier:taskIdentifier]];
}
@end

@interface SJDownloadDataTask ()<NSURLSessionDelegate>
@property (nonatomic) long long wroteSize_before;
@property long long speed;

@property (nonatomic, weak, nullable) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong, nullable) NSProgress *downloadProgress;
@property (nonatomic, strong, nullable) NSTimer *speedRefreshTimer;
@property (strong, nullable) SJOutPutStream *outPutStream;
@property (nonatomic, strong, nullable) NSError *error;
@end

@implementation SJDownloadDataTask {
    SJDownloadDataTaskIdentitifer _identifier;
    NSString *_URLStr;
    NSURL *_fileURL;
    
    /// Blocks
    void(^_Nullable _responseBlock)(SJDownloadDataTask *dataTask);
    void(^_Nullable _progressBlock)(SJDownloadDataTask *dataTask, float progress);
    void(^_Nullable _successBlock)(SJDownloadDataTask *dataTask);
    void(^_Nullable _failureBlock)(SJDownloadDataTask *dataTask);
}

#ifdef DEBUG
- (void)dealloc {
    NSLog(@"%d - %s", (int)__LINE__, __func__);
}
#endif

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
    sjTask->_URLStr = URLStr;
    sjTask->_fileURL = fileURL;
    sjTask->_responseBlock = responseBlock;
    sjTask->_progressBlock = progressBlock;
    sjTask->_successBlock = successBlock;
    sjTask->_failureBlock = failureBlock;
    sjTask->_shouldAppend = shouldAppend;
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
        taskQueue.name = @"com.SJDownloadDataTask.taskQueue";
    }
    
    if ( !session ) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        session = [NSURLSession sessionWithConfiguration:config delegate:(id)self delegateQueue:taskQueue];
    }
    
    NSURLRequest *request = nil;
    
    if ( !shouldAppend ) {
        request = [NSURLRequest requestWithURL:URL];
        
        #ifdef SJ_MAC
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
        if ( 0 != wroteSize ) {
            [(NSMutableURLRequest *)request setValue:[NSString stringWithFormat:@"bytes=%lld-", wroteSize] forHTTPHeaderField:@"Range"];
        }
        
        #ifdef SJ_MAC
        printf("\nSJDownloadDataTask: 此次下载为追加模式, 将会向文件中追加剩余数据. 当前文件大小为: %lld\n", wroteSize);
        #endif
    }
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request];
    return dataTask;
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SJDownloadDataTask *sjTask = [SJDownloadDataTaskContainer.shared taskForIdentifier:dataTask.taskIdentifier];
    
    if ( !sjTask ) {
        [dataTask cancel];
        return;
    }

    int64_t wroteSize = 0;
    if ( sjTask.shouldAppend ) {
        wroteSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:sjTask.fileURL.path error:nil] valueForKey:NSFileSize] longLongValue];
    }
    
    sjTask.downloadProgress.totalUnitCount = response.expectedContentLength + wroteSize;
    sjTask.downloadProgress.completedUnitCount = wroteSize;
    
    if ( sjTask->_responseBlock ) {
        sjTask->_responseBlock(sjTask);
    }
    
    if ( response.expectedContentLength == 0 ) {
        completionHandler(NSURLSessionResponseCancel);
        if ( sjTask->_successBlock ) {
            sjTask->_successBlock(sjTask);
        }

        #ifdef SJ_MAC
        printf("\nSJDownloadDataTask: 接收到服务器响应, 但返回响应的文件大小为 0, 该文件可能已下载完毕. 我将取消本次请求, 并回调`successBlock`\n");
        #endif
    }
    else {
        // create output stream
        sjTask.outPutStream = [[SJOutPutStream alloc] initWithPath:sjTask.fileURL append:sjTask.shouldAppend];
        [sjTask.outPutStream open];
        completionHandler(NSURLSessionResponseAllow);
        
        #ifdef SJ_MAC
        printf("\nSJDownloadDataTask: 接收到服务器响应, 文件总大小: %lld, 下载标识:%ld \n", downloadTask.totalSize, (unsigned long)dataTask.taskIdentifier);
        #endif
    }
}

+ (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    SJDownloadDataTask *sjTask = [SJDownloadDataTaskContainer.shared taskForIdentifier:dataTask.taskIdentifier];
    if ( !sjTask ) {
        [dataTask cancel];
        return;
    }
    
    [sjTask.outPutStream write:data];
    sjTask.downloadProgress.completedUnitCount += data.length;

    #ifdef SJ_MAC
    printf("\nSJDownloadDataTask: 写入大小: %lld, 文件大小: %lld, 下载进度: %f", sjTask.wroteSize, sjTask.totalSize, sjTask.downloadProgress.completedUnitCount * 1.0 / sjTask.downloadProgress.totalUnitCount);
    #endif
}

+ (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask didCompleteWithError:(NSError *)error {
    SJDownloadDataTask *sjTask = [SJDownloadDataTaskContainer.shared taskForIdentifier:dataTask.taskIdentifier];
    if ( !sjTask ) {
        return;
    }
    
    [SJDownloadDataTaskContainer.shared removeTaskForIdentifier:dataTask.taskIdentifier];
    
    if ( error.code == NSURLErrorCancelled ) {
        #ifdef SJ_MAC
        printf("\nSJDownloadDataTask: 下载被取消, 下载标识:%ld \n", (unsigned long)dataTask.taskIdentifier);
        #endif
        return;
    }
    
    if ( error ) {
        sjTask.error = error;
        if ( sjTask->_failureBlock ) {
            sjTask->_failureBlock(sjTask);
        }
        
        #ifdef SJ_MAC
        printf("\nSJDownloadDataTask: 下载错误, error: %s, 下载标识:%ld \n", [error.description UTF8String], (unsigned long)dataTask.taskIdentifier);
        #endif
        return;
    }
    
    if ( sjTask->_successBlock ) {
        sjTask->_successBlock(sjTask);
    }
    
    #ifdef SJ_MAC
    printf("\nSJDownloadDataTask: 文件下载完成, 下载标识: %ld, 保存路径:%s \n", (unsigned long)dataTask.taskIdentifier, [[sjTask fileURL].path UTF8String]);
    #endif
}

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    _downloadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    _downloadProgress.totalUnitCount = NSURLSessionTransferSizeUnknown;
    [_downloadProgress sj_addObserver:self forKeyPath:@"completedUnitCount"];
    return self;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context {
    if ( _progressBlock )
        _progressBlock(self, self.progress);
}

- (SJDownloadDataTaskIdentitifer)identifier {
    return (SJDownloadDataTaskIdentitifer)_dataTask.taskIdentifier;
}

- (void)restart {
    SJDownloadDataTaskSafeExeMethod();
    
    [self cancel];
    NSURLSessionDataTask *task = [SJDownloadDataTask downloadTaskWithURLStr:self.URLStr toPath:self.fileURL append:self.shouldAppend];
    [task resume];
    [self _activateSpeedRefreshTimer];
    [SJDownloadDataTaskContainer.shared insertTask:self forIdentifier:task.taskIdentifier];
    self.dataTask = task;
    
    #ifdef SJ_MAC
    printf("\nSJDownloadDataTask: 准备下载: %s, 保存路径:%s, 下载标识:%ld \n", [self.URLStr UTF8String], [[self.fileURL absoluteString] UTF8String], (unsigned long)task.taskIdentifier);
    #endif
}

- (void)cancel {
    SJDownloadDataTaskSafeExeMethod();
    
    [self _cleanSpeedRefreshTimerIfNeeded];
    [self _cleanTaskIfNeeded];
}

- (void)_cleanTaskIfNeeded {
    SJDownloadDataTaskSafeExeMethod();
    
    if ( self.dataTask ) {
        NSURLSessionDataTask *task = self.dataTask;
        
        /// clean
        [SJDownloadDataTaskContainer.shared removeTaskForIdentifier:task.taskIdentifier];
        self.dataTask = nil;
        if ( task && task.state != NSURLSessionTaskStateCanceling && task.state != NSURLSessionTaskStateCompleted ) {
            [task cancel];
            #ifdef SJ_MAC
            printf("\nSJDownloadDataTask: 下载被取消, URL: %s, 下载标识:%ld \n", [self.URLStr UTF8String], task.taskIdentifier);
            #endif
        }
        
        self.outPutStream = nil;
    }
}

- (void)_activateSpeedRefreshTimer {
    SJDownloadDataTaskSafeExeMethod();

    if ( _speedRefreshTimer ) {
        return;
    }
    
    __weak typeof(self) _self = self;
    _speedRefreshTimer = [NSTimer DownloadDataTaskAdd_timerWithTimeInterval:0.2 block:^(NSTimer * _Nonnull timer) {
        __strong typeof(_self) self = _self;
        if ( !self ) {
            [timer invalidate];
            return ;
        }
        if ( !self.dataTask || self.dataTask.state != NSURLSessionTaskStateRunning ) {
            [self _cleanSpeedRefreshTimerIfNeeded];
            return ;
        }
        long long wroteSize_now = self.wroteSize;
        long long wroteSize_before = self.wroteSize_before;
        if ( wroteSize_before != 0 ) {
            self.speed = (wroteSize_now - wroteSize_before) / timer.timeInterval;
        }
        self.wroteSize_before = wroteSize_now;
    } repeats:YES];
    self.wroteSize_before = self.wroteSize;
    [NSRunLoop.mainRunLoop addTimer:_speedRefreshTimer forMode:NSRunLoopCommonModes];
    [_speedRefreshTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_speedRefreshTimer.timeInterval]];
}

- (void)_cleanSpeedRefreshTimerIfNeeded {
    SJDownloadDataTaskSafeExeMethod();
    
    if ( _speedRefreshTimer ) {
        [_speedRefreshTimer invalidate];
        _speedRefreshTimer = nil;
    }
    
    self.speed = 0;
}


#pragma mark -

@synthesize speed = _speed;
- (void)setSpeed:(long long)speed {
    @synchronized(self) {
        if ( speed == _speed ) {
            return;
        }
        _speed = speed;
        if ( _speedDidChangeExeBlock ) {
            _speedDidChangeExeBlock(self);
        }
    }
}

- (long long)speed {
    @synchronized(self) {
        return _speed;
    }
}

- (int64_t)wroteSize {
    return _downloadProgress.completedUnitCount;
}

- (int64_t)totalSize {
    return _downloadProgress.totalUnitCount;
}

- (float)progress {
    return (self.totalSize == 0)?0:(self.wroteSize * 1.0 / self.totalSize);
}
@end
NS_ASSUME_NONNULL_END
