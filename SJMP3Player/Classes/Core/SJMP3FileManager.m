//
//  SJMP3FileManager.m
//  SJMP3PlayerProject
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import "SJMP3FileManager.h"

NS_ASSUME_NONNULL_BEGIN
// folder
static void sj_checkout_folders(void);
static NSString *sj_root_folder(void);
static NSString *sj_tmp_folder(void);

// file path
static NSString *sj_tmp_path(NSURL *URL);
static NSString *sj_file_path(NSURL *URL);
static BOOL sj_file_exists(NSURL *URL);

#pragma mark -
@interface SJMP3FileManager()

@end

@implementation SJMP3FileManager
@synthesize URL = _URL;
@synthesize filePath = _filePath;
@synthesize tmpPath = _tmpPath;

+ (void)clear {
    [NSFileManager.defaultManager removeItemAtPath:sj_root_folder() error:nil];
    [NSFileManager.defaultManager removeItemAtPath:sj_tmp_folder() error:nil];
    sj_checkout_folders();
}

+ (long long)size {
    NSString *rootFolder = sj_root_folder();
    NSArray *paths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootFolder error:nil];
    NSMutableArray<NSString *> *itemPaths = [NSMutableArray new];
    [paths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [itemPaths addObject:[rootFolder stringByAppendingPathComponent:obj]];
    }];
    
    __block long long size = 0;
    [itemPaths enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary<NSFileAttributeKey, id> *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:obj error:nil];
        size += [dict[NSFileSize] longLongValue];
    }];
    return size;
}

+ (nullable NSString *)filePathForURL:(NSURL *)URL {
    return sj_file_path(URL);
}

+ (nullable NSString *)tmpPathForURL:(NSURL *)URL {
    return sj_tmp_path(URL);
}

+ (BOOL)fileExistsForURL:(NSURL *)URL {
    return sj_file_exists(URL);
}

+ (void)deleteForURL:(NSURL *)URL {
    if ( !URL )
        return;
    [NSFileManager.defaultManager removeItemAtPath:sj_file_path(URL) error:nil];
    [NSFileManager.defaultManager removeItemAtPath:sj_tmp_path(URL) error:nil];
}

- (instancetype)initWithURL:(NSURL *)URL {
    self = [super init];
    if ( !self )
        return nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sj_checkout_folders();
    });
    
    _URL = URL;
    _filePath = sj_file_path(URL);
    _tmpPath = sj_tmp_path(URL);
    return self;
}

- (BOOL)fileExists {
    return sj_file_exists(_URL);
}

- (void)saveTmpItemToFilePath {
    if ( [NSFileManager.defaultManager fileExistsAtPath:_tmpPath] ) {
        [NSFileManager.defaultManager copyItemAtPath:_tmpPath toPath:_filePath error:nil];
    }
}

- (nullable NSData *)tmpData {
    return [NSData dataWithContentsOfFile:self.tmpPath];
}
- (nullable NSData *)fileData {
    return [NSData dataWithContentsOfFile:self.filePath];
}
@end

#pragma mark -
static NSString *sj_root_folder(void) {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"com.dancebaby.lanwuzhe.audioCacheFolder/cache"];
}

static NSString *sj_tmp_folder(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"audioTmpFolder"];
}

static void sj_checkout_folders(void) {
    NSString *folder = sj_root_folder();
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }

    folder = sj_tmp_folder();
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:folder] ) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

static NSString *sj_tmp_path(NSURL *URL) {
    NSString *format = URL.pathExtension; if ( format.length == 0 ) format = @"mp3";
    return [sj_tmp_folder() stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.%@", (unsigned long)[URL.absoluteString hash], format]];
}

static NSString *sj_file_path(NSURL *URL) {
    NSString *format = URL.pathExtension; if ( format.length == 0 ) format = @"mp3";
    return [sj_root_folder() stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.%@", (unsigned long)[URL.absoluteString hash], format]];
}

static BOOL sj_file_exists(NSURL *URL) {
    return [[NSFileManager defaultManager] fileExistsAtPath:sj_file_path(URL)];
}
NS_ASSUME_NONNULL_END
