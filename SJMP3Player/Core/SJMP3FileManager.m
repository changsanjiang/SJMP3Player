//
//  SJMP3FileManager.m
//  Pods
//
//  Created by BlueDancer on 2019/6/25.
//

#import "SJMP3FileManager.h"

NS_ASSUME_NONNULL_BEGIN
@implementation SJMP3FileManager
static NSString *_rootFolder;
static NSString *_tmpFolder;
+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _rootFolder = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"com.dancebaby.lanwuzhe.audioCacheFolder/cache"];
        _tmpFolder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"audioTmpFolder"];
        [self _checkoutRootFolderIfNeeded];
        [self _checkoutTmpFolderIfNeeded];
    });
}
+ (void)clear {
    NSArray<NSString *> *folders = @[_tmpFolder, _rootFolder];
    for ( NSString *folder in folders ) {
        if ( [NSFileManager.defaultManager isDeletableFileAtPath:folder] ) {
            [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
        }
        else {
            NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil];
            [contents enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString *path = [folder stringByAppendingPathComponent:obj];
                if ( [NSFileManager.defaultManager isDeletableFileAtPath:path] ) {
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                }
            }];
        }
    }
    
    [self _checkoutRootFolderIfNeeded];
    [self _checkoutTmpFolderIfNeeded];
}
+ (unsigned long long)size {
    NSArray *paths = [NSFileManager.defaultManager contentsOfDirectoryAtPath:_rootFolder error:nil];
    NSMutableArray<NSString *> *itemPaths = [NSMutableArray new];
    [paths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [itemPaths addObject:[_rootFolder stringByAppendingPathComponent:obj]];
    }];
    
    __block unsigned long long size = 0;
    [itemPaths enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary<NSFileAttributeKey, id> *dict = [NSFileManager.defaultManager attributesOfItemAtPath:obj error:nil];
        size += [dict[NSFileSize] unsignedLongLongValue];
    }];
    return size;
}
+ (NSString *)filePathForURL:(NSURL *)URL {
    return [_rootFolder stringByAppendingPathComponent:[self _fileNameForURL:URL]];
}
+ (NSURL *)fileURLForURL:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self filePathForURL:URL]];
}
+ (BOOL)fileExistsForURL:(NSURL *)URL {
    return [NSFileManager.defaultManager fileExistsAtPath:[self filePathForURL:URL]];
}
+ (void)deleteFileForURL:(NSURL *)URL {
    NSString *path = [self filePathForURL:URL];
    if ( [NSFileManager.defaultManager isDeletableFileAtPath:path] ) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}
+ (void)deleteFile:(NSURL *)fileURL {
    [NSFileManager.defaultManager removeItemAtPath:fileURL.absoluteString error:nil];
}
+ (BOOL)isSubitemInRootFolderWithFileURL:(NSURL *)fileURL {
    NSString *folder = [fileURL.absoluteString stringByDeletingLastPathComponent];
    return [folder isEqualToString:_rootFolder];
}
+ (NSString *)tmpPathForURL:(NSURL *)URL {
    return [_tmpFolder stringByAppendingPathComponent:[self _fileNameForURL:URL]];
}
+ (NSURL *)tmpURLForURL:(NSURL *)URL {
    return [NSURL fileURLWithPath:[self tmpPathForURL:URL]];
}
+ (void)copyTmpFileToRootFolderForURL:(NSURL *)URL {
    NSString *tmp = [self tmpPathForURL:URL];
    NSString *file = [self filePathForURL:URL];
    if ( [NSFileManager.defaultManager fileExistsAtPath:tmp] ) {
        @try {
            [NSFileManager.defaultManager copyItemAtPath:tmp toPath:file error:nil];
        } @catch (NSException *exception) { } @finally { }
    }
}

#pragma mark -

+ (void)_checkoutRootFolderIfNeeded {
    if ( ![NSFileManager.defaultManager fileExistsAtPath:_rootFolder] ) {
        [NSFileManager.defaultManager createDirectoryAtPath:_rootFolder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}
+ (void)_checkoutTmpFolderIfNeeded {
    if ( ![NSFileManager.defaultManager fileExistsAtPath:_tmpFolder] ) {
        [NSFileManager.defaultManager createDirectoryAtPath:_tmpFolder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

+ (NSString *)_fileNameForURL:(NSURL *)URL {
    NSString *format = URL.pathExtension;
    if ( format.length == 0 )
        format = @"mp3";
    NSString *name = [NSString stringWithFormat:@"%ld.%@", (unsigned long)[URL.absoluteString hash], format];
    return name;
}
@end
NS_ASSUME_NONNULL_END
