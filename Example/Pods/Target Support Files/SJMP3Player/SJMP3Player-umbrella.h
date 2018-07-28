#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "SJMP3Player.h"
#import "NSTimer+SJMP3PlayerAdd.h"
#import "SJMP3PlayerFileManager.h"
#import "SJMP3PlayerPrefetcher.h"

FOUNDATION_EXPORT double SJMP3PlayerVersionNumber;
FOUNDATION_EXPORT const unsigned char SJMP3PlayerVersionString[];

