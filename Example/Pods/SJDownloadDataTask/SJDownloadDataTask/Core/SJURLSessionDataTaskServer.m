//
//  SJURLSessionDataTaskServer.m
//  SJDownloadDataTask
//
//  Created by BlueDancer on 2019/5/13.
//  Copyright © 2019 畅三江. All rights reserved.
//

#import "SJURLSessionDataTaskServer.h"
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import "SJDownloadDataTaskResourceLoader.h"

NS_ASSUME_NONNULL_BEGIN
@interface _SJBackgroundAudioPlayer : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end

@interface _SJBackgroundAudioPlayer () {
    @private
    dispatch_semaphore_t _lock;
    NSUInteger _num;
    AVAudioPlayer *_player;
}
@end

@implementation _SJBackgroundAudioPlayer
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
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[SJDownloadDataTaskResourceLoader.bundle URLForResource:@"blank.mp3" withExtension:nil] error:nil];
    return self;
}

- (void)start {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    _num ++;
    if ( _player.isPlaying == NO ) {
        _player.numberOfLoops = NSUIntegerMax;
        [_player prepareToPlay];
        [_player play];
    }
    dispatch_semaphore_signal(_lock);
}
- (void)stop {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    _num --;
    if ( _num == 0 ) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER);
            if ( self->_num == 0 ) {
                [self->_player stop];
            }
            dispatch_semaphore_signal(self->_lock);
        });
    }
    dispatch_semaphore_signal(_lock);
}
@end

@interface SJURLSessionDataTaskServer ()<NSURLSessionDelegate>

@end

@implementation SJURLSessionDataTaskServer
+ (instancetype)shared {
    static id _instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [self new];
    });
    return _instance;
}

static void *kResponseHandler = &kResponseHandler;
static void *kReceivedDataHandler = &kReceivedDataHandler;
static void *kCompletionHandler = &kCompletionHandler;
static void *kCancelledHandler = &kCancelledHandler;

- (nullable NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)URL
                                         wroteSize:(long long)wroteSize
                                          response:(nullable SJURLSessionDataTaskResponseHandler)responseHandler
                                      receivedData:(nullable SJURLSessionDataTaskReceivedDataHandler)receivedDataHandler
                                        completion:(nullable SJURLSessionDataTaskCompletionHandler)completionHandler
                                         cancelled:(nullable SJURLSessionDataTaskCancelledHandler)cancelledHandler {
    if ( !URL ) return nil;
    [_SJBackgroundAudioPlayer.shared start];
    
    static NSURLSession *_Nullable Session;
    static NSOperationQueue *_Nullable TaskQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TaskQueue = [NSOperationQueue new];
        TaskQueue.name = @"com.SJDownloadDataTask.taskQueue";
        
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        Session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:TaskQueue];
    });
    
    NSURLRequest *request = nil;
    if ( wroteSize == 0 ) {
        request = [NSURLRequest requestWithURL:URL];
    }
    else {
        NSMutableURLRequest *mutableRequest = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:0];
        [mutableRequest setValue:[NSString stringWithFormat:@"bytes=%lld-", wroteSize]
                              forHTTPHeaderField:@"Range"];
        request = mutableRequest;
    }
    
    NSURLSessionDataTask *dataTask = [Session dataTaskWithRequest:request];
    objc_setAssociatedObject(dataTask, kResponseHandler, responseHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(dataTask, kReceivedDataHandler, receivedDataHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(dataTask, kCompletionHandler, completionHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(dataTask, kCancelledHandler, cancelledHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return dataTask;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSHTTPURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    SJURLSessionDataTaskResponseHandler _Nullable handler = objc_getAssociatedObject(dataTask, kResponseHandler);
    if ( handler != nil ) {
        if ( handler(dataTask) == YES )
            completionHandler(NSURLSessionResponseAllow);
        else
            completionHandler(NSURLSessionResponseCancel);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    SJURLSessionDataTaskReceivedDataHandler _Nullable handler = objc_getAssociatedObject(dataTask, kReceivedDataHandler);
    if ( handler != nil ) {
        handler(dataTask, data);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask didCompleteWithError:(NSError *)error {
    [_SJBackgroundAudioPlayer.shared stop];
    
    if ( error.code == NSURLErrorCancelled ) {
        objc_setAssociatedObject(dataTask, kResponseHandler, nil, 0);
        objc_setAssociatedObject(dataTask, kReceivedDataHandler, nil, 0);
        objc_setAssociatedObject(dataTask, kCompletionHandler, nil, 0);
        SJURLSessionDataTaskCancelledHandler _Nullable handler = objc_getAssociatedObject(self, kCancelledHandler);
        if ( handler != nil ) {
            handler(dataTask);
        }
        objc_setAssociatedObject(dataTask, kCancelledHandler, nil, 0);
        return;
    }

    SJURLSessionDataTaskCompletionHandler _Nullable handler = objc_getAssociatedObject(dataTask, kCompletionHandler);
    if ( handler != nil ) {
        handler(dataTask);
    }
}
@end
NS_ASSUME_NONNULL_END
