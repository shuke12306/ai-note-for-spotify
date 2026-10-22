#import "CGDPageTargets.h"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger assertions;
static void Require(BOOL condition, const char *message) {
    assertions++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static Class Register(Class parent, const char *name) {
    Class cls = objc_allocateClassPair(parent, name, 0);
    if (!cls) { fprintf(stderr, "Fixture registration failed\n"); exit(1); }
    objc_registerClassPair(cls);
    return cls;
}

int main(void) {
    @autoreleasepool {
        Require(!CGDIsSupportedPageClass(Nil), "missing class is not a page");
        Require(!CGDIsSupportedPageClass(NSObject.class), "unrelated base class is not a page");
        // Regression fixture from the user's actual fullscreen-page diagnostic.
        Class v2 = Register(NSObject.class, "NowPlaying_ScrollImpl.NPVScrollV2ViewController");
        Require(CGDIsSupportedPageClass(v2), "actual 9.1.60 V2 playback page is recognized");
        Class observedKVO = Register(v2, "NSKVONotifying_NowPlaying_ScrollImpl.NPVScrollV2ViewController");
        Require(CGDIsSupportedPageClass(observedKVO), "runtime subclass keeps V2 recognition");
        Class background = Register(NSObject.class, "NowPlaying_ScrollImpl.NPVBackgroundV2ViewController");
        Require(!CGDIsSupportedPageClass(background), "background child must not create a second button");
        Class mini = Register(NSObject.class, "NowPlaying_BarPageImpl.CompactNowPlayingViewController");
        Require(!CGDIsSupportedPageClass(mini), "mini player must not create a fullscreen button");
        Class legacy = Register(NSObject.class, "NowPlaying_ScrollImpl.NPVScrollViewController");
        Require(CGDIsSupportedPageClass(legacy), "legacy page remains supported");
        Require(CGDIsSupportedPageClass(v2), "coexisting unused legacy class does not hide V2");
        printf("PASS: %lu PageTarget assertions (device-derived class fixtures).\n", (unsigned long)assertions);
    }
    return 0;
}
