// Host-only adapter double for executing the real Logos hooks without UIKit.
#import <Foundation/Foundation.h>
#import "CGDTrackReader.h"
#ifndef __unused
#define __unused __attribute__((unused))
#endif
void CGDInstallSpotifyHooks(void);
@interface CGDAdapter : NSObject
+ (instancetype)shared;
- (void)capturePlayer:(id)player;
- (void)capturePage:(id)page;
- (void)setHookState:(NSString *)state forKey:(NSString *)key;
- (void)recordIssue:(NSString *)issue;
@end
