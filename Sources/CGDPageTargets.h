#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// One allowlist for automatic lifecycle hooks AND the manual page probe.
// V2 was observed on the device: Spotify 9.1.60, build 916001969.
NS_INLINE NSArray<NSString *> *CGDPageTargetNames(void) {
    return @[
        @"NowPlaying_ScrollImpl.NPVScrollV2ViewController",
        @"NowPlaying_ScrollImpl.NPVScrollViewController",
        @"NowPlaying_ScrollImpl.NowPlayingScrollViewController",
    ];
}

NS_INLINE BOOL CGDIsSupportedPageClass(Class candidate) {
    if (!candidate) return NO;
    for (NSString *name in CGDPageTargetNames()) {
        Class target = NSClassFromString(name);
        if (!target) continue;
        // Includes KVO subclasses; never matches unrelated similarly named views.
        for (Class cls = candidate; cls; cls = class_getSuperclass(cls)) {
            if (cls == target) return YES;
        }
    }
    return NO;
}
