#import <UIKit/UIKit.h>
#import "CGDTrackReader.h"

#define CGD_PLUGIN_NAME @"AI Note"
#define CGD_PLUGIN_VERSION @"1.1.0"

void CGDInstallSpotifyHooks(void);

@interface CGDAdapter : NSObject
+ (instancetype)shared;
- (void)capturePlayer:(id)player;
- (void)capturePage:(id)page;
- (void)recordPageClass:(Class)pageClass source:(NSString *)source;
- (NSDictionary *)snapshot;
- (void)setHookState:(NSString *)state forKey:(NSString *)key;
- (void)recordIssue:(NSString *)issue;
- (NSString *)diagnosticsForSnapshot:(NSDictionary *)snapshot;
@end

// UI callbacks only touch the captured Spotify page, never UIViewController itself.
void CGDInstallPageLifecycle(UIViewController *page);
void CGDInstallKnownPageHooks(void);
// One bounded, user-triggered inspection of foreground windows. No polling.
UIViewController *CGDProbePlaybackPages(void);
void CGDPresentDiagnostics(UIViewController *presenter);
