//
//  SJMP3PlayerFileManager.h
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SJMP3PlayerFileManager : NSObject
#pragma mark
+ (BOOL)delete:(NSURL *)fileCacheURL; // 删除文件
+ (BOOL)isCached:(NSURL *)URL;  // remote url
+ (BOOL)isCachedOfFileURL:(NSURL *)fileURL; // cache url
+ (NSURL *)fileCacheURL:(NSURL *)URL; // remote url
+ (NSURL *)tmpFileCacheURL:(NSURL *)URL; // remote url
+ (void)clear; // 清楚所有缓存
+ (void)clearTmpFiles; // 清楚所有临时缓存
+ (long long)cacheSize; // 缓存文件的大小, bytes

#pragma mark
- (void)updateURL:(nullable NSURL *)URL; // remote url
@property (nonatomic, readonly) BOOL isCached;
@property (nonatomic, strong, readonly, nullable) NSURL *URL; // remote url
@property (nonatomic, strong, readonly, nullable) NSURL *fileCacheURL; // cache url
@property (nonatomic, strong, readonly, nullable) NSURL *tmpFileCacheURL; // tmp url
- (long long)tmpFileCachedSize; // 文件已缓存的大小
- (BOOL)deleteCache;
- (BOOL)deleteTmpFile;
- (void)copyTmpFileToCache;
@end
NS_ASSUME_NONNULL_END
