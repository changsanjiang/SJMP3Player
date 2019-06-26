//
//  SJMP3FileManager.h
//  Pods
//
//  Created by BlueDancer on 2019/6/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJMP3FileManager : NSObject
+ (void)clear;
+ (unsigned long long)size;
+ (NSString *)filePathForURL:(NSURL *)URL;
+ (NSURL *)fileURLForURL:(NSURL *)URL;
+ (BOOL)fileExistsForURL:(NSURL *)URL;
+ (void)deleteFileForURL:(NSURL *)URL;
+ (void)deleteFile:(NSURL *)fileURL;
+ (BOOL)isSubitemInRootFolderWithFileURL:(NSURL *)fileURL;

+ (NSString *)tmpPathForURL:(NSURL *)URL;
+ (NSURL *)tmpURLForURL:(NSURL *)URL;

+ (void)copyTmpFileToRootFolderForURL:(NSURL *)URL;
@end

NS_ASSUME_NONNULL_END
