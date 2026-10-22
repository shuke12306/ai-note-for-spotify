#import "CGDAdapter.h"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger assertions, baseCalls, priorHookCalls, legacyCalls, pageCalls, captures, issues;
static id lastPlayer, lastPage, lastArgument, returnValue;
static BOOL throwInObserver;

static void Require(BOOL condition, const char *label) {
    assertions++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}

@implementation CGDAdapter
+ (instancetype)shared {
    static CGDAdapter *adapter;
    if (!adapter) adapter = [CGDAdapter new];
    return adapter;
}
- (void)capturePlayer:(id)player {
    captures++;
    if (throwInObserver) [NSException raise:@"ObserverError" format:@"test"];
    lastPlayer = player;
}
- (void)capturePage:(id)page { lastPage = page; }
- (void)setHookState:(NSString *)state forKey:(NSString *)key { (void)state; (void)key; }
- (void)recordIssue:(NSString *)issue { (void)issue; issues++; }
@end

static id BaseModern(id self, SEL selector, id argument) {
    (void)self; (void)selector;
    baseCalls++;
    lastArgument = argument;
    return returnValue;
}
static id ExistingModernHook(id self, SEL selector, id argument) {
    priorHookCalls++;
    return BaseModern(self, selector, argument);
}
static id Legacy(id self, SEL selector) {
    (void)self; (void)selector; legacyCalls++; return returnValue;
}
static id Page(id self, SEL selector, id argument) {
    (void)self; (void)selector; lastArgument = argument; pageCalls++; return returnValue;
}
static id Call1(id target, SEL selector, id argument) {
    IMP implementation = class_getMethodImplementation(object_getClass(target), selector);
    return ((id (*)(id, SEL, id))implementation)(target, selector, argument);
}
static id Call0(id target, SEL selector) {
    IMP implementation = class_getMethodImplementation(object_getClass(target), selector);
    return ((id (*)(id, SEL))implementation)(target, selector);
}

int main(void) {
    @autoreleasepool {
        // Missing classes may be checked safely, then registered lazily.
        CGDInstallSpotifyHooks();
        Class provider = objc_allocateClassPair([NSObject class],
            "NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation", 0);
        Class pageProvider = objc_allocateClassPair([NSObject class],
            "NowPlaying_ScrollImpl.NowPlayingScrollPrivateServiceImplementation", 0);
        Require(provider != Nil && pageProvider != Nil, "fixture classes allocated");
        SEL modern = NSSelectorFromString(@"provideStatefulPlayerWithFeatureIdentifier:");
        SEL legacy = NSSelectorFromString(@"provideStatefulPlayer");
        SEL pageSelector = NSSelectorFromString(@"provideScrollViewControllerWithDependencies:");
        class_addMethod(provider, legacy, (IMP)Legacy, "@@:");
        class_addMethod(pageProvider, pageSelector, (IMP)Page, "@@:@");
        objc_registerClassPair(provider);
        objc_registerClassPair(pageProvider);
        id object = [provider new];
        id pageObject = [pageProvider new];
        returnValue = @"sentinel-result";
        CGDInstallSpotifyHooks();
        Require(class_getInstanceMethod(provider, modern) == NULL,
                "missing method not fabricated by hook installation");
        Require(Call0(object, legacy) == returnValue && legacyCalls == 1 && captures == 1,
                "legacy original called once and result captured");

        class_addMethod(provider, modern, (IMP)ExistingModernHook, "@@:@");
        CGDInstallSpotifyHooks();
        CGDInstallSpotifyHooks();
        id argument = @"feature-identity";
        Require(Call1(object, modern, argument) == returnValue, "modern return identity preserved");
        Require(baseCalls == 1 && priorHookCalls == 1, "pre-existing hook chain called exactly once");
        Require(lastArgument == argument && lastPlayer == returnValue && captures == 2,
                "argument identity preserved and result captured once");
        Require(Call1(pageObject, pageSelector, argument) == returnValue &&
                pageCalls == 1 && lastPage == returnValue, "page result captured, original called once");

        throwInObserver = YES;
        Require(Call1(object, modern, argument) == returnValue, "observer exception does not change host result");
        Require(issues == 1 && baseCalls == 2 && priorHookCalls == 2, "observer error reported once");
        throwInObserver = NO;
        returnValue = nil;
        Require(Call1(object, modern, argument) == nil && lastPlayer == nil,
                "nil provider result propagated and captured");
        Require(baseCalls == 3 && captures == 4, "repeated installation never nests our hook");
        printf("PASS: %lu Hook assertions (Logos hooks with GNU SEL comparison adaptation).\n",
            (unsigned long)assertions);
    }
    return 0;
}
