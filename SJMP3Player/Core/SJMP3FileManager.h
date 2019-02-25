//
//  SJMP3FileManager.h
//  SJMP3PlayerProject
//
//  Created by 畅三江 on 2018/5/26.
//  Copyright © 2018年 changsanjiang. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol SJMP3FileManager <NSObject>
+ (void)clear;
+ (long long)size;
+ (nullable NSString *)filePathForURL:(NSURL *)URL;
+ (nullable NSString *)tmpPathForURL:(NSURL *)URL;
+ (BOOL)fileExistsForURL:(NSURL *)URL;
+ (void)deleteForURL:(NSURL *)URL;

- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) NSString *filePath;
@property (nonatomic, strong, readonly) NSString *tmpPath;
@property (nonatomic, strong, readonly) NSURL *URL;

@property (nonatomic, readonly) BOOL fileExists;
- (void)saveTmpItemToFilePath;

- (nullable NSData *)tmpData;
- (nullable NSData *)fileData;
- (nullable NSURL *)fileURL;
- (nullable NSURL *)tmpURL;
@end

@interface SJMP3FileManager : NSObject<SJMP3FileManager>

@end
NS_ASSUME_NONNULL_END
