#import "CGDLocalization.h"
#import "CGDAdapter.h"
#import "CGDPageTargets.h"
#import <objc/runtime.h>

static const NSUInteger CGDWindowLimit = 8;
static const NSUInteger CGDControllerLimit = 128;
static const NSUInteger CGDViewLimit = 2048;

static BOOL CGDIsDiagnosticController(UIViewController *controller) {
    Class diagnostic = NSClassFromString(@"CGDDiagnosticsController");
    if (!diagnostic) return NO;
    if ([controller isKindOfClass:diagnostic]) return YES;
    return [controller isKindOfClass:UINavigationController.class] &&
        [((UINavigationController *)controller).topViewController isKindOfClass:diagnostic];
}

static BOOL CGDIsAppController(UIViewController *controller) {
    NSString *prefix = [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"];
    // KVO subclasses have no image of their own. Inspect their real superclass.
    for (Class cls = object_getClass(controller); cls && cls != UIViewController.class;
         cls = class_getSuperclass(cls)) {
        const char *image = class_getImageName(cls);
        if (image && [[NSString stringWithUTF8String:image] hasPrefix:prefix]) return YES;
    }
    return NO;
}

static BOOL CGDViewInWindow(UIView *view, UIWindow *window) {
    if (!view || view.window != window || view.hidden || view.alpha <= 0 ||
        CGRectIsEmpty(view.bounds)) return NO;
    UIView *ancestor = view;
    NSUInteger depth = 0;
    while (ancestor && ancestor != window && depth++ < 64) {
        if (ancestor.hidden || ancestor.alpha <= 0) return NO;
        ancestor = ancestor.superview;
    }
    return ancestor == window && CGRectIntersectsRect([view convertRect:view.bounds toView:window], window.bounds);
}

static BOOL CGDAddControllerName(UIViewController *controller, NSMutableArray *names) {
    NSString *name = NSStringFromClass(object_getClass(controller));
    if ([names containsObject:name]) return YES;
    if (names.count >= 64) return NO;
    [names addObject:name];
    return YES;
}

static void CGDRegisterObservedPage(UIViewController *controller) {
    // Use the same allowlist as automatic hook installation. Unknown observed
    // classes remain diagnostic output rather than new hook targets.
    if (!CGDIsSupportedPageClass(object_getClass(controller))) return;
    [[CGDAdapter shared] recordPageClass:object_getClass(controller) source:CGDL(@"手动页面定位")];
    CGDInstallPageLifecycle(controller);
}

UIViewController *CGDProbePlaybackPages(void) {
    if (!NSThread.isMainThread) return nil;
    NSMutableArray<NSString *> *report = [NSMutableArray array];
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    NSDateFormatter *time = [[NSDateFormatter alloc] init];
    time.dateFormat = @"HH:mm:ss";
    [report addObject:[NSString stringWithFormat:CGDL(@"%@，诊断面板打开前"), [time stringFromDate:NSDate.date]]];
    UIViewController *preferred = nil;
    CGFloat preferredScore = -CGFLOAT_MAX;
    NSUInteger controllersChecked = 0, viewsChecked = 0;
    BOOL limited = NO;
    @try {
        CGDInstallKnownPageHooks();
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0 || CGRectIsEmpty(window.bounds) ||
                    !window.rootViewController) continue;
                [windows addObject:window];
            }
        }
        [windows sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
            if (a.isKeyWindow != b.isKeyWindow) return a.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
            if (a.windowLevel == b.windowLevel) return NSOrderedSame;
            return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }];
        if (windows.count > CGDWindowLimit) limited = YES;
        for (NSUInteger wi = 0; wi < MIN(windows.count, CGDWindowLimit); wi++) {
            UIWindow *window = windows[wi];
            NSMutableArray *relatedNames = [NSMutableArray array];
            NSMutableArray *responderNames = [NSMutableArray array];
            NSMutableArray *playbackViews = [NSMutableArray array];
            BOOL hasAppController = NO;
            [report addObject:[NSString stringWithFormat:CGDL(@"窗口 %lu：%@，level=%.0f，key=%@"),
                (unsigned long)wi + 1, NSStringFromClass(window.class),
                (double)window.windowLevel, window.isKeyWindow ? CGDL(@"是") : CGDL(@"否")]];

            NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
            NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:window.rootViewController];
            NSUInteger cursor = 0;
            while (cursor < queue.count && controllersChecked < CGDControllerLimit) {
                UIViewController *controller = queue[cursor++];
                controllersChecked++;
                if ([seen containsObject:controller]) continue;
                [seen addObject:controller];
                if (CGDIsDiagnosticController(controller)) continue;
                if (CGDViewInWindow(controller.viewIfLoaded, window)) {
                    if (!CGDAddControllerName(controller, relatedNames)) limited = YES;
                    hasAppController |= CGDIsAppController(controller);
                    CGDRegisterObservedPage(controller);
                }
                // Presented pages take priority over background tab children.
                if (controller.presentedViewController) {
                    if (queue.count < CGDControllerLimit) [queue addObject:controller.presentedViewController];
                    else limited = YES;
                }
                for (UIViewController *child in controller.childViewControllers) {
                    if (queue.count >= CGDControllerLimit) { limited = YES; break; }
                    [queue addObject:child];
                }
            }
            if (cursor < queue.count) limited = YES;

            // Custom containers may omit addChildViewController / appearance
            // forwarding. Inspect root-view responders once, without reading
            // any label, accessibility value, web content, or host metadata.
            NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:window];
            cursor = 0;
            while (cursor < views.count && viewsChecked < CGDViewLimit) {
                UIView *view = views[cursor++];
                viewsChecked++;
                if (view.hidden || view.alpha <= 0) continue;
                UIResponder *responder = view.nextResponder;
                if ([responder isKindOfClass:UIViewController.class]) {
                    UIViewController *controller = (UIViewController *)responder;
                    if (CGDIsDiagnosticController(controller)) continue;
                    if (CGDViewInWindow(view, window)) {
                        if (!CGDAddControllerName(controller, responderNames)) limited = YES;
                        hasAppController |= CGDIsAppController(controller);
                        if (![seen containsObject:controller]) {
                            [seen addObject:controller];
                            CGDRegisterObservedPage(controller);
                        }
                    }
                }
                NSString *viewName = NSStringFromClass(object_getClass(view));
                if (([viewName containsString:@"NowPlaying"] || [viewName containsString:@"NPV"]) &&
                    CGDViewInWindow(view, window) && ![playbackViews containsObject:viewName]) {
                    if (playbackViews.count < 32) [playbackViews addObject:viewName];
                    else limited = YES;
                }
                for (UIView *child in view.subviews) {
                    if (views.count >= CGDViewLimit) { limited = YES; break; }
                    [views addObject:child];
                }
            }
            if (cursor < views.count) limited = YES;
            [report addObject:[CGDL(@"  控制器关系：") stringByAppendingString:
                relatedNames.count ? [relatedNames componentsJoinedByString:@"； "] : CGDL(@"未取得")]];
            [report addObject:[CGDL(@"  视图响应者：") stringByAppendingString:
                responderNames.count ? [responderNames componentsJoinedByString:@"； "] : CGDL(@"未取得")]];
            [report addObject:[CGDL(@"  播放视图类：") stringByAppendingString:
                playbackViews.count ? [playbackViews componentsJoinedByString:@"； "] : CGDL(@"未取得")]];
            CGFloat score = window.windowLevel + (window.isKeyWindow ? 1000000 : 0);
            UIViewController *candidate = window.rootViewController;
            NSUInteger presentationDepth = 0;
            while (candidate.presentedViewController &&
                   !candidate.presentedViewController.isBeingDismissed && presentationDepth++ < 32) {
                candidate = candidate.presentedViewController;
            }
            // Fullscreen presentation can remove the root's view from its
            // window. Present from the still-visible top controller instead.
            if (hasAppController && score > preferredScore &&
                CGDViewInWindow(candidate.viewIfLoaded, window)) {
                preferred = candidate;
                preferredScore = score;
            }
        }
    } @catch (NSException *exception) {
        [report addObject:[CGDL(@"采集异常：") stringByAppendingString:exception.name]];
    }
    [report addObject:[NSString stringWithFormat:CGDL(@"检查 %lu 个控制器、%lu 个视图；%@"),
        (unsigned long)controllersChecked, (unsigned long)viewsChecked,
        limited ? CGDL(@"已达到数量上限，结果可能不完整") : CGDL(@"未达到数量上限")]];
    [[CGDAdapter shared] setHookState:[report componentsJoinedByString:@"\n"] forKey:@"手动页面定位"];
    return preferred;
}
