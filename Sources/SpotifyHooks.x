#import "CGDAdapter.h"

%config(generator=internal);

// Each hook calls the implementation present at install time exactly once.
// Host exceptions are not swallowed; only our post-call observer is guarded.
%group CGDModernPlayer
%hook CGDModernPlayerProvider
- (id)provideStatefulPlayerWithFeatureIdentifier:(id)identifier {
    id result = %orig(identifier);
    @try {
        [[CGDAdapter shared] capturePlayer:result];
        [[CGDAdapter shared] setHookState:@"已调用，返回值已检查" forKey:@"播放器入口（带标识）"];
    }
    @catch (NSException *exception) {
        [[CGDAdapter shared] recordIssue:[@"播放器捕获异常：" stringByAppendingString:exception.name]];
    }
    return result;
}
%end
%end

%group CGDLegacyPlayer
%hook CGDLegacyPlayerProvider
- (id)provideStatefulPlayer {
    id result = %orig;
    @try {
        [[CGDAdapter shared] capturePlayer:result];
        [[CGDAdapter shared] setHookState:@"已调用，返回值已检查" forKey:@"播放器入口（无参数）"];
    }
    @catch (NSException *exception) {
        [[CGDAdapter shared] recordIssue:[@"播放器捕获异常：" stringByAppendingString:exception.name]];
    }
    return result;
}
%end
%end

%group CGDPageProviderGroup
%hook CGDPageProvider
- (id)provideScrollViewControllerWithDependencies:(id)dependencies {
    id result = %orig(dependencies);
    @try {
        [[CGDAdapter shared] capturePage:result];
        [[CGDAdapter shared] setHookState:@"已调用，返回值已检查" forKey:@"播放页入口"];
    }
    @catch (NSException *exception) {
        [[CGDAdapter shared] recordIssue:[@"播放页捕获异常：" stringByAppendingString:exception.name]];
    }
    return result;
}
%end
%end

void CGDInstallSpotifyHooks(void) {
    static BOOL modernInstalled = NO;
    static BOOL legacyInstalled = NO;
    static BOOL pageInstalled = NO;
    @synchronized ([CGDAdapter shared]) {
        Class playerProvider = NSClassFromString(
            @"NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation");
        Class pageProvider = NSClassFromString(
            @"NowPlaying_ScrollImpl.NowPlayingScrollPrivateServiceImplementation");
        if (!modernInstalled) {
            if (CGDMethodMatches(playerProvider,
                    NSSelectorFromString(@"provideStatefulPlayerWithFeatureIdentifier:"), "@@:@")) {
                %init(CGDModernPlayer, CGDModernPlayerProvider = playerProvider);
                modernInstalled = YES;
            }
            [[CGDAdapter shared] setHookState:modernInstalled ? @"已安装，等待返回播放器" :
                @"未找到类或兼容方法" forKey:@"播放器入口（带标识）"];
        }
        if (!legacyInstalled) {
            if (CGDMethodMatches(playerProvider, NSSelectorFromString(@"provideStatefulPlayer"), "@@:")) {
                %init(CGDLegacyPlayer, CGDLegacyPlayerProvider = playerProvider);
                legacyInstalled = YES;
            }
            [[CGDAdapter shared] setHookState:legacyInstalled ? @"已安装，等待返回播放器" :
                @"未找到类或兼容方法" forKey:@"播放器入口（无参数）"];
        }
        if (!pageInstalled) {
            if (CGDMethodMatches(pageProvider,
                    NSSelectorFromString(@"provideScrollViewControllerWithDependencies:"), "@@:@")) {
                %init(CGDPageProviderGroup, CGDPageProvider = pageProvider);
                pageInstalled = YES;
            }
            [[CGDAdapter shared] setHookState:pageInstalled ? @"已安装，等待返回播放页" :
                @"未找到类或兼容方法" forKey:@"播放页入口"];
        }
    }
}
