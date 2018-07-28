//
//  SJMP3PlayerFileManager.m
//  SJMP3Player
//
//  Created by 畅三江 on 2018/7/28.
//

#import "SJMP3PlayerFileManager.h"

@implementation SJMP3PlayerFileManager
- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    [[self class] _checkoutCacheFolder];
    return self;
}
+ (void)_checkoutCacheFolder {
    NSString *folder = SJMP3PlayerFileManager.rootCacheFolder;
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    folder = SJMP3PlayerFileManager.tmpCacheFolder;
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}
+ (NSString *)rootCacheFolder {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"com.dancebaby.lanwuzhe.audioCacheFolder/cache"];
}
+ (NSString *)tmpCacheFolder {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"audioTmpFolder"];
}
+ (NSString *)fileCachePath:(NSURL *)URL {
    return [SJMP3PlayerFileManager.rootCacheFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.mp3", (unsigned long)[URL.absoluteString hash]]];
}
+ (NSString *)tmpFileCachePath:(NSURL *)URL {
    return [SJMP3PlayerFileManager.tmpCacheFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.mp3", (unsigned long)[URL.absoluteString hash]]];
}
+ (BOOL)delete:(NSURL *)fileCacheURL {
    return [[NSFileManager defaultManager] removeItemAtURL:fileCacheURL error:nil];
}
+ (BOOL)isCached:(NSURL *)URL {
    return [[NSFileManager defaultManager] fileExistsAtPath:[SJMP3PlayerFileManager fileCachePath:URL]];
}
+ (BOOL)isCachedOfFileURL:(NSURL *)fileURL {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self.rootCacheFolder stringByAppendingPathComponent:fileURL.lastPathComponent]];
}
+ (NSURL *)fileCacheURL:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self fileCachePath:URL]];
}
+ (NSURL *)tmpFileCacheURL:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self tmpFileCachePath:URL]];
}
+ (void)clear {
    [[NSFileManager defaultManager] removeItemAtPath:[self rootCacheFolder]  error:nil];
    [self clearTmpFiles];
    [self _checkoutCacheFolder];
}
+ (long long)cacheSize {
    __block long long size = 0;
    [[self fileCaches] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        size += [self _fileSizeOfPath:obj];
    }];
    return size;
}
+ (void)clearTmpFiles {
    [[NSFileManager defaultManager] removeItemAtPath:[self tmpCacheFolder] error:nil];
    [self _checkoutCacheFolder];
}
+ (NSArray<NSString *> *)fileCaches {
    NSString *rootFolder = [self rootCacheFolder];
    NSArray *paths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootFolder error:nil];
    NSMutableArray<NSString *> *itemPaths = [NSMutableArray new];
    [paths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [itemPaths addObject:[rootFolder stringByAppendingPathComponent:obj]];
    }];
    return itemPaths;
}
+ (long long)_fileSizeOfPath:(NSString *)path {
    NSDictionary<NSFileAttributeKey, id> *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [dict[NSFileSize] longLongValue];
}

#pragma mark
- (void)updateURL:(nullable NSURL *)URL {
    if ( URL.isFileURL ) return;
    _URL = URL;
}
- (BOOL)isCached {
    if ( !_URL ) return NO;
    return [SJMP3PlayerFileManager isCached:self.URL];
}
- (nullable NSURL *)fileCacheURL {
    if ( !_URL ) return nil;
    return [NSURL fileURLWithPath:[SJMP3PlayerFileManager fileCachePath:self.URL]];
}
- (nullable NSURL *)tmpFileCacheURL {
    if ( !_URL ) return nil;
    return [NSURL fileURLWithPath:[SJMP3PlayerFileManager tmpFileCachePath:self.URL]];
}
- (long long)tmpFileCachedSize {
    if ( !_URL ) return 0;
    return [[self class] _fileSizeOfPath:self.tmpFileCacheURL.path];
}
- (BOOL)deleteCache {
    if ( !self.isCached ) return NO;
    return [[NSFileManager defaultManager] removeItemAtPath:self.fileCacheURL.path error:nil];
}
- (BOOL)deleteTmpFile {
    if ( !_URL ) return NO;
    return [[NSFileManager defaultManager] removeItemAtPath:self.tmpFileCacheURL.path error:nil];
}
- (void)copyTmpFileToCache {
    if ( !_URL ) return;
    [[NSFileManager defaultManager] copyItemAtURL:self.tmpFileCacheURL toURL:self.fileCacheURL error:nil];
}
@end
