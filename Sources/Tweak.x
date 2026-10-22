#import "CGDLocalization.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "CGDAdapter.h"

%config(generator=internal);

// Startup installs hooks and a diagnostic entry; opening the guide starts AI work.
// A runtime bundle check is needed because direct dylib injection ignores the plist.
static NSString *const CGDTargetBundleIdentifier = @"com.spotify.client";

@interface CGDLoadIndicator : NSObject
@property(nonatomic) BOOL hasShown;
@property(nonatomic) BOOL attemptScheduled;
@property(nonatomic) NSUInteger attemptCount;
+ (instancetype)sharedIndicator;
- (void)start;
@end

@implementation CGDLoadIndicator

+ (instancetype)sharedIndicator {
    static CGDLoadIndicator *indicator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        indicator = [[CGDLoadIndicator alloc] init];
    });
    return indicator;
}

- (void)start {
    NSAssert([NSThread isMainThread], @"UIKit must run on the main thread.");
    self.hasShown = [[NSUserDefaults.standardUserDefaults stringForKey:@"CGDClassicalGuide.LastWelcomeVersion"] isEqual:CGD_PLUGIN_VERSION];
    CGDInstallKnownPageHooks();
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    // Also covers injection after the application is already active.
    [self scheduleAttempt];
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    CGDInstallSpotifyHooks();
    CGDInstallKnownPageHooks();
    self.attemptCount = 0;
    [self scheduleAttempt];
}

- (UIWindow *)foregroundWindow {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha <= 0.0 ||
                window.windowLevel != UIWindowLevelNormal ||
                !window.rootViewController.isViewLoaded ||
                window.rootViewController.view.window != window ||
                CGRectIsEmpty(window.bounds)) {
                continue;
            }
            if (window.isKeyWindow) {
                return window;
            }
            fallback = window;
        }
    }
    return fallback;
}

- (void)scheduleAttempt {
    if (self.hasShown || self.attemptScheduled ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        return;
    }
    self.attemptScheduled = YES;
    // Allow the host to finish its launch/activation layout. Retries are bounded.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.attemptScheduled = NO;
        if (self.hasShown ||
            UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            return;
        }
        UIWindow *window = [self foregroundWindow];
        if (!window) {
            self.attemptCount += 1;
            if (self.attemptCount < 12) {
                [self scheduleAttempt];
            }
            return;
        }
        [self showInWindow:window];
    });
}

- (void)showInWindow:(UIWindow *)window {
    self.hasShown = YES;
    [NSUserDefaults.standardUserDefaults setObject:CGD_PLUGIN_VERSION forKey:@"CGDClassicalGuide.LastWelcomeVersion"];
    // Keep activation observation to retry only missing hooks after lazy loading.

    UIView *banner = [[UIView alloc] init];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.backgroundColor = UIColor.secondarySystemBackgroundColor;
    banner.layer.cornerRadius = 14.0;
    banner.clipsToBounds = YES;
    banner.userInteractionEnabled = YES;
    [banner addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(openDiagnostics:)]];
    banner.isAccessibilityElement = YES;
    banner.accessibilityTraits = UIAccessibilityTraitButton;
    banner.accessibilityLabel = [CGD_PLUGIN_NAME stringByAppendingString:CGDL(@" 已加载，点击打开曲目诊断")];

    NSString *spotifyVersion =
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: CGDL(@"未知");
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.labelColor;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    label.adjustsFontForContentSizeCategory = YES;
    label.text = [NSString stringWithFormat:
        CGDL(@"%@ %@ · Spotify %@\n播放页点击“导赏” · 此处可查看诊断"),
        CGD_PLUGIN_NAME, CGD_PLUGIN_VERSION, spotifyVersion];

    [banner addSubview:label];
    [window addSubview:banner];
    [NSLayoutConstraint activateConstraints:@[
        [banner.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:16],
        [banner.trailingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [banner.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8],
        [label.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-12],
        [label.topAnchor constraintEqualToAnchor:banner.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-12],
    ]];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, label.text);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            banner.alpha = 0;
        } completion:^(BOOL finished) {
            (void)finished;
            [banner removeFromSuperview];
        }];
    });
}

- (void)openDiagnostics:(UITapGestureRecognizer *)gesture {
    CGDPresentDiagnostics(gesture.view.window.rootViewController);
}

@end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:CGDTargetBundleIdentifier]) {
            // Install available provider hooks before application startup can use them.
            @try { CGDInstallSpotifyHooks(); }
            @catch (NSException *exception) {
                [[CGDAdapter shared] recordIssue:
                    [CGDL(@"初始接入检查异常：") stringByAppendingString:exception.name]];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[CGDLoadIndicator sharedIndicator] start];
            });
        }
    }
}
