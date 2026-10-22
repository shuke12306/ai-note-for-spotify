#import "CGDLocalization.h"
#import "CGDAdapter.h"
#import "CGDPageTargets.h"
#import "CGDGuideUI.h"
#import "CGDEntryPlacement.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface CGDDiagnosticsController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, copy) NSDictionary *trackSnapshot;
@property(nonatomic, copy) NSString *report;
@end

@implementation CGDDiagnosticsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGDL(@"曲目信息");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:CGDL(@"关闭") style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:CGDL(@"刷新") style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.alwaysBounceVertical = YES;
    self.textView.adjustsFontForContentSizeCategory = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(16, 14, 24, 14);
    self.textView.accessibilityLabel = CGDL(@"当前曲目信息与接入诊断");
    [self.view addSubview:self.textView];
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    copyButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    copyButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [copyButton setTitle:CGDL(@"复制诊断") forState:UIControlStateNormal];
    [copyButton addTarget:self action:@selector(copyReport) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:copyButton];
    UIButton *locateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    locateButton.translatesAutoresizingMaskIntoConstraints = NO;
    locateButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    locateButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    locateButton.titleLabel.numberOfLines = 0;
    locateButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [locateButton setTitle:CGDL(@"5 秒后定位播放页") forState:UIControlStateNormal];
    locateButton.accessibilityHint = CGDL(@"关闭面板后，请停留在大封面的播放页；5 秒后会重新显示诊断。");
    [locateButton addTarget:self action:@selector(locatePlaybackPage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:locateButton];
    [NSLayoutConstraint activateConstraints:@[
        [copyButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [copyButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [copyButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [copyButton.heightAnchor constraintGreaterThanOrEqualToConstant:48],
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [locateButton.leadingAnchor constraintEqualToAnchor:copyButton.leadingAnchor],
        [locateButton.trailingAnchor constraintEqualToAnchor:copyButton.trailingAnchor],
        [locateButton.bottomAnchor constraintEqualToAnchor:copyButton.topAnchor constant:-4],
        [locateButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.textView.bottomAnchor constraintEqualToAnchor:locateButton.topAnchor constant:-8],
    ]];
    [self refresh];
}

- (void)refresh {
    CGDInstallSpotifyHooks(); // Retrying checks is idempotent, never double-hooks.
    CGDInstallKnownPageHooks();
    self.trackSnapshot = [[CGDAdapter shared] snapshot];
    NSString *body = [[CGDAdapter shared] diagnosticsForSnapshot:self.trackSnapshot];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    self.report = [NSString stringWithFormat:
        CGDL(@"读取时间：%@\n\n%@\n\n曲目随“刷新”更新；页面结构保留打开面板前的采集结果。\n若无按钮，点“5 秒后定位播放页”，关闭面板后停留在大封面的播放页。\n此诊断页不发起 AI 请求，不包含密钥或网络响应。"),
        [formatter stringFromDate:NSDate.date], body];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:self.report attributes:@{
            NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
            NSForegroundColorAttributeName: UIColor.labelColor,
        }];
    // Highlight the captured title without using the host's current/live labels.
    NSString *title = self.trackSnapshot[@"title"];
    if (title.length) {
        NSRange range = [self.report rangeOfString:[CGDL(@"曲名：") stringByAppendingString:title]];
        if (range.location != NSNotFound) {
            [text addAttribute:NSFontAttributeName
                         value:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] range:range];
        }
    }
    self.textView.attributedText = text;
    [self.textView setContentOffset:CGPointZero animated:NO];
}

- (void)copyReport {
    if (!self.report.length) return;
    UIPasteboard.generalPasteboard.string = self.report;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CGDL(@"诊断已复制")
        message:CGDL(@"可以粘贴到聊天里。内容包含当前曲目信息和插件接入状态。")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"好") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)locatePlaybackPage {
    static BOOL pending;
    if (pending) return;
    pending = YES;
    // A single explicit diagnostic capture, after this sheet is fully dismissed.
    // No controller or view is retained by the delayed block.
    [self dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            pending = NO;
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
                [[CGDAdapter shared] setHookState:CGDL(@"应用不在前台，本次定位已取消") forKey:@"延时定位"];
                return;
            }
            [[CGDAdapter shared] setHookState:CGDL(@"已等待 5 秒，在打开诊断面板前采集") forKey:@"延时定位"];
            CGDPresentDiagnostics(nil);
        });
    }];
}
@end

void CGDPresentDiagnostics(UIViewController *presenter) {
    if (!NSThread.isMainThread) return;
    // Inspect BEFORE presenting our sheet; the host can rearrange pages during
    // presentation. The probe also finds controllers outside root containment.
    UIViewController *foregroundPresenter = CGDProbePlaybackPages();
    if (foregroundPresenter) presenter = foregroundPresenter;
    if (!presenter) return;
    while (presenter.parentViewController) presenter = presenter.parentViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    if ([presenter isKindOfClass:UINavigationController.class] &&
        [((UINavigationController *)presenter).topViewController isKindOfClass:CGDDiagnosticsController.class]) {
        return;
    }
    if ([presenter isKindOfClass:UIAlertController.class] ||
        presenter.isBeingPresented || presenter.isBeingDismissed || !presenter.view.window) return;
    CGDDiagnosticsController *controller = [[CGDDiagnosticsController alloc] init];
    UINavigationController *navigation = CGDMakeNavigationController(controller);
    [presenter presentViewController:navigation animated:YES completion:nil];
}

@interface CGDEntryAnchorObserver : UIView
@property(nonatomic, copy) void (^geometryChanged)(void);
@property(nonatomic) CGRect previousBounds;
@property(nonatomic) CGRect previousParentFrame;
@property(nonatomic, weak) UIWindow *previousWindow;
@property(nonatomic) BOOL hasGeometry;
@end
@implementation CGDEntryAnchorObserver
- (void)notifyGeometryChange {
    CGRect parentFrame = self.superview.frame;
    if (self.hasGeometry && CGRectEqualToRect(self.previousBounds, self.bounds) &&
        CGRectEqualToRect(self.previousParentFrame, parentFrame) && self.previousWindow == self.window) return;
    self.hasGeometry = YES; self.previousBounds = self.bounds;
    self.previousParentFrame = parentFrame; self.previousWindow = self.window;
    if (self.geometryChanged) self.geometryChanged();
}
- (void)layoutSubviews { [super layoutSubviews]; [self notifyGeometryChange]; }
- (void)didMoveToWindow { [super didMoveToWindow]; [self notifyGeometryChange]; }
@end

@interface CGDPageOverlay : UIView
@property(nonatomic, weak) UIViewController *page;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, weak) UIView *coverAnchor;
@property(nonatomic, weak) UIView *informationAnchor;
@property(nonatomic, weak) UIView *informationRegion;
@property(nonatomic, strong) CGDEntryAnchorObserver *anchorObserver;
@property(nonatomic, strong) NSHashTable<UIScrollView *> *observedScrollViews;
@property(nonatomic) CFTimeInterval nextAnchorSearch;
@property(nonatomic) NSUInteger anchorSearchesRemaining;
@property(nonatomic) NSUInteger activationGeneration;
@property(nonatomic) BOOL anchorRetryScheduled;
@property(nonatomic, copy) NSString *placementStatus;
- (void)activate;
- (void)deactivate;
- (void)scheduleAnchorRefresh;
@end

static char CGDEntryScrollContext;

static CGDEntryRect CGDEntryRectangle(CGRect rect) {
    return (CGDEntryRect){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
}

static BOOL CGDEntryViewIsVisible(UIView *view, UIView *root) {
    if (!view || !root.window || view.window != root.window || ![view isDescendantOfView:root]) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < .01) return NO;
        if (ancestor == root) return YES;
    }
    return NO;
}

static BOOL CGDEntryIsClass(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

// Only public UIKit geometry is read. These two host classes were present in
// the phone's 9.1.60 diagnostic; no guessed host getter or layout constraint.
static UIView *CGDEntryCoverImage(UIView *cell, UIView *root) {
    UIView *best = cell;
    CGFloat largestArea = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:cell];
    for (NSUInteger i = 0; i < queue.count && i < 64; i++) {
        UIView *view = queue[i];
        if (view.hidden || view.alpha < .01) continue;
        CGFloat width = view.bounds.size.width, height = view.bounds.size.height;
        if ([view isKindOfClass:UIImageView.class] && width >= root.bounds.size.width * .5 &&
            height >= width * .8 && height <= width * 1.2 && width * height > largestArea) {
            best = view;
            largestArea = width * height;
        }
        NSUInteger count = MIN(64 - queue.count, view.subviews.count);
        if (count) [queue addObjectsFromArray:[view.subviews subarrayWithRange:NSMakeRange(0, count)]];
    }
    return best;
}

static UIView *CGDEntryFirstText(UIView *information) {
    UIView *first = nil;
    CGFloat firstY = CGFLOAT_MAX;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:information];
    for (NSUInteger i = 0; i < queue.count && i < 64; i++) {
        UIView *view = queue[i];
        if (view.hidden || view.alpha < .01) continue;
        if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length && !CGRectIsEmpty(view.bounds)) {
            CGFloat y = CGRectGetMinY([view convertRect:view.bounds toView:information]);
            if (y < firstY) { first = view; firstY = y; }
        }
        NSUInteger count = MIN(64 - queue.count, view.subviews.count);
        if (count) [queue addObjectsFromArray:[view.subviews subarrayWithRange:NSMakeRange(0, count)]];
    }
    return first ?: information;
}

@implementation CGDPageOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.observedScrollViews = [NSHashTable weakObjectsHashTable];
        self.button = [UIButton buttonWithType:UIButtonTypeSystem];
        self.button.hidden = YES;
        self.button.tintColor = [UIColor.whiteColor colorWithAlphaComponent:.78];
        [self.button setTitleColor:self.button.tintColor forState:UIControlStateNormal];
        self.button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
            scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular] maximumPointSize:17];
        self.button.titleLabel.adjustsFontForContentSizeCategory = YES;
        self.button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        self.button.contentEdgeInsets = UIEdgeInsetsMake(0, 9, 0, 9);
        self.button.imageEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 3);
        self.button.titleEdgeInsets = UIEdgeInsetsMake(0, 3, 0, -3);
        [self.button setImage:[UIImage systemImageNamed:@"book" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular]]
                     forState:UIControlStateNormal];
        [self.button setTitle:CGDL(@"导赏") forState:UIControlStateNormal];
        self.button.accessibilityLabel = [CGD_PLUGIN_NAME stringByAppendingString:CGDL(@" 导赏")];
        self.button.accessibilityHint = CGDL(@"打开当前歌曲的古典乐导赏面板。");
        // A quiet outline remains legible over changing video frames without
        // adding a solid floating button or sampling every frame.
        self.button.layer.shadowColor = UIColor.blackColor.CGColor;
        self.button.layer.shadowOpacity = .55;
        self.button.layer.shadowRadius = 2;
        self.button.layer.shadowOffset = CGSizeMake(0, 1);
        [self.button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.button];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceLanguageChanged:)
            name:CGDInterfaceLanguageDidChangeNotification object:nil];
    }
    return self;
}

- (void)interfaceLanguageChanged:(NSNotification *)notification {
    (void)notification;
    [self.button setTitle:CGDL(@"导赏") forState:UIControlStateNormal];
    self.button.accessibilityLabel = [CGD_PLUGIN_NAME stringByAppendingString:CGDL(@" 导赏")];
    self.button.accessibilityHint = CGDL(@"打开当前歌曲的古典乐导赏面板。");
    [self setNeedsLayout];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    // All touches outside the actual button go straight through to Spotify.
    return !self.hidden && !self.button.hidden && self.button.enabled && CGRectContainsPoint(self.button.frame, point);
}

- (void)reportPlacement:(NSString *)status {
    if ([status isEqualToString:self.placementStatus]) return;
    self.placementStatus = status;
    [[CGDAdapter shared] setHookState:status forKey:@"导赏入口布局"];
}

- (void)stopObservingScrollViews {
    for (UIScrollView *scroll in self.observedScrollViews.allObjects) {
        [scroll removeObserver:self forKeyPath:@"contentOffset" context:&CGDEntryScrollContext];
    }
    [self.observedScrollViews removeAllObjects];
}

- (void)observeScrollAncestors:(UIView *)view {
    UIView *root = self.page.viewIfLoaded;
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UIScrollView.class] && ![self.observedScrollViews containsObject:(UIScrollView *)ancestor]) {
            [(UIScrollView *)ancestor addObserver:self forKeyPath:@"contentOffset" options:0 context:&CGDEntryScrollContext];
            [self.observedScrollViews addObject:(UIScrollView *)ancestor];
        }
        if (ancestor == root) break;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                      change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if (context == &CGDEntryScrollContext) {
        if (NSThread.isMainThread && !self.hidden) {
            [self setNeedsLayout];
            if (!CGDEntryViewIsVisible(self.informationAnchor, self.page.viewIfLoaded)) [self scheduleAnchorRefresh];
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)scheduleAnchorRefresh {
    if (self.hidden || !self.window || self.anchorRetryScheduled) return;
    self.anchorRetryScheduled = YES;
    NSUInteger generation = self.activationGeneration;
    __weak CGDPageOverlay *weakSelf = self;
    // Cell replacement may complete after the first layout callback. Retry a
    // bounded three times, then stop; never poll the video or the whole window.
    NSArray<NSNumber *> *delays = @[@.3, @.8, @1.6];
    for (NSUInteger index = 0; index < delays.count; index++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[index].doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGDPageOverlay *overlay = weakSelf;
            if (!overlay || overlay.activationGeneration != generation) return;
            if (index == delays.count - 1) overlay.anchorRetryScheduled = NO;
            if (overlay.hidden || !overlay.window) return;
            if (index == 0 || !CGDEntryViewIsVisible(overlay.informationAnchor, overlay.page.viewIfLoaded)) {
                overlay.anchorSearchesRemaining = MAX((NSUInteger)2, overlay.anchorSearchesRemaining);
                overlay.nextAnchorSearch = 0;
                [overlay findAnchors];
            }
            [overlay setNeedsLayout];
        });
    }
}

- (void)observeInformationRegion:(UIView *)information {
    if (self.anchorObserver.superview == information && information) return;
    self.anchorObserver.geometryChanged = nil;
    [self.anchorObserver removeFromSuperview];
    self.anchorObserver = nil;
    self.informationRegion = information;
    if (!information) return;
    CGDEntryAnchorObserver *observer = [[CGDEntryAnchorObserver alloc] initWithFrame:information.bounds];
    observer.userInteractionEnabled = NO;
    observer.accessibilityElementsHidden = YES;
    observer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak CGDPageOverlay *weakSelf = self;
    observer.geometryChanged = ^{
        // Reacquire on a host layout/attachment change, not a timer or video
        // frame. Coalescing prevents cell replacement from causing scan loops.
        [weakSelf setNeedsLayout]; [weakSelf scheduleAnchorRefresh];
    };
    self.anchorObserver = observer;
    [information addSubview:observer];
}

- (void)findAnchors {
    UIView *root = self.page.viewIfLoaded;
    if (!root.window || self.hidden || !self.anchorSearchesRemaining || CACurrentMediaTime() < self.nextAnchorSearch) return;
    self.anchorSearchesRemaining--;
    self.nextAnchorSearch = CACurrentMediaTime() + .25;
    self.coverAnchor = nil;
    self.informationAnchor = nil;
    UIView *coverCell = nil, *information = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    // Bounded discovery only in the captured playback page. Cover is optional;
    // the title region remains the primary anchor in both artwork/video modes.
    for (NSUInteger i = 0; i < queue.count && i < 384; i++) {
        UIView *view = queue[i];
        if (view == self || view.hidden || view.alpha < .01) continue;
        if (CGDEntryIsClass(view, @"NowPlaying_ContentLayersImpl.LegacyCoverArtCellImpl") &&
            view.bounds.size.width >= root.bounds.size.width * .5 &&
            view.bounds.size.height >= root.bounds.size.width * .4 &&
            CGRectIntersectsRect([view convertRect:view.bounds toView:root], root.bounds)) coverCell = view;
        if (CGDEntryIsClass(view.nextResponder, @"NowPlaying_ModesImpl.InformationElementsUnit") &&
            !CGRectIsEmpty(view.bounds)) information = view;
        NSUInteger count = MIN(384 - queue.count, view.subviews.count);
        if (count) [queue addObjectsFromArray:[view.subviews subarrayWithRange:NSMakeRange(0, count)]];
    }
    if (coverCell) self.coverAnchor = CGDEntryCoverImage(coverCell, root);
    if (information) self.informationAnchor = CGDEntryFirstText(information);
    if (self.informationAnchor) {
        [self observeInformationRegion:information];
        [self stopObservingScrollViews];
        [self observeScrollAncestors:self.coverAnchor];
        [self observeScrollAncestors:self.informationAnchor];
    }
}

- (void)activate {
    self.activationGeneration++;
    self.anchorRetryScheduled = NO;
    self.hidden = NO;
    self.button.hidden = YES;
    self.anchorSearchesRemaining = 6;
    self.nextAnchorSearch = 0;
    self.coverAnchor = nil;
    self.informationAnchor = nil;
    [self observeInformationRegion:nil];
    [self stopObservingScrollViews];
    [self setNeedsLayout];
    // A few one-shot retries cover UIKit's initial asynchronous cell layout.
    // No timer, full-window scan, or permanent polling is installed.
    __weak CGDPageOverlay *weakSelf = self;
    NSUInteger generation = self.activationGeneration;
    for (NSNumber *delay in @[@.15, @.5, @1.2, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CGDPageOverlay *overlay = weakSelf;
            if (overlay && overlay.activationGeneration == generation && !overlay.hidden && overlay.window) {
                // If an initial cell was still a placeholder, allow discovery
                // to pick its image/labels once UIKit has populated them.
                if (overlay.button.hidden) {
                    overlay.coverAnchor = nil;
                    overlay.informationAnchor = nil;
                }
                [overlay setNeedsLayout];
            }
        });
    }
}

- (void)deactivate {
    self.activationGeneration++;
    self.anchorRetryScheduled = NO;
    self.hidden = YES;
    self.button.hidden = YES;
    [self observeInformationRegion:nil];
    [self stopObservingScrollViews];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; self.anchorObserver.geometryChanged = nil; [self.anchorObserver removeFromSuperview]; [self stopObservingScrollViews]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *root = self.page.viewIfLoaded;
    self.button.hidden = YES;
    if (self.hidden || !root.window) return;
    if (!CGDEntryViewIsVisible(self.informationAnchor, root)) {
        [self findAnchors];
    }
    if (!CGDEntryViewIsVisible(self.informationAnchor, root)) {
        [self reportPlacement:[NSString stringWithFormat:CGDL(@"等待定位：封面%@，曲名区域%@"),
            self.coverAnchor ? CGDL(@"已找到") : CGDL(@"未找到"), self.informationAnchor ? CGDL(@"已找到") : CGDL(@"未找到")]];
        return;
    }
    BOOL hasCover = CGDEntryViewIsVisible(self.coverAnchor, root);
    CGRect cover = hasCover ? [self.coverAnchor convertRect:self.coverAnchor.bounds toView:self] : CGRectZero;
    CGRect information = [self.informationAnchor convertRect:self.informationAnchor.bounds toView:self];
    CGFloat width = MAX(64, [self.button sizeThatFits:CGSizeMake(CGFLOAT_MAX, 44)].width);
    CGFloat height = MAX(44, self.button.titleLabel.font.lineHeight + 16);
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat right = CGRectGetMaxX(safeBounds) - 24;
    if (CGDEntryViewIsVisible(self.informationRegion, root)) {
        CGRect region = [self.informationRegion convertRect:self.informationRegion.bounds toView:self];
        // Canvas adds a thumbnail beside the title. Keep the hit target above
        // that region too, instead of aligning only to the text's baseline.
        if (!hasCover && CGRectGetMinY(region) <= CGRectGetMinY(information) && CGRectGetHeight(region) < height * 3)
            information.origin.y = CGRectGetMinY(region);
        right = MIN(right, CGRectGetMaxX(region));
    }
    CGDEntryRect placement = {0};
    CGDEntryPosition position = CGDPlaceEntry(CGDEntryRectangle(safeBounds), CGDEntryRectangle(information),
        CGDEntryRectangle(cover), right, width, height, &placement);
    if (position == CGDEntryHidden) {
        [self reportPlacement:CGDL(@"曲名区域已定位；当前留白或滚动位置不足，入口暂时隐藏")];
        return;
    }
    self.button.frame = CGRectMake(placement.x, placement.y, placement.width, placement.height);
    self.button.hidden = NO;
    [self reportPlacement:position == CGDEntryBelowCover ? CGDL(@"已显示：封面下方靠右 · 书本图标＋导赏") :
        CGDL(@"已显示：曲名上方靠右 · 无需静态封面")];
}

- (void)open { CGDPresentGuide(self.page); }
@end

static char CGDPageMarkerKey;
static char CGDOverlayKey;

static BOOL CGDIsKnownPage(UIViewController *page) {
    return CGDIsSupportedPageClass(object_getClass(page));
}

static void CGDPageAttach(UIViewController *page, NSString *source) {
    if (!objc_getAssociatedObject(page, &CGDPageMarkerKey) && CGDIsKnownPage(page)) {
        objc_setAssociatedObject(page, &CGDPageMarkerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(page, &CGDPageMarkerKey)) return;
    [[CGDAdapter shared] setHookState:source forKey:@"播放页入口触发"];
    if (!page.isViewLoaded || !page.view.window) {
        [[CGDAdapter shared] setHookState:CGDL(@"视图尚未进入窗口") forKey:@"播放页视图状态"];
        return;
    }
    [[CGDAdapter shared] setHookState:CGDL(@"视图已进入窗口") forKey:@"播放页视图状态"];
    [[CGDAdapter shared] recordPageClass:object_getClass(page) source:source];
    CGDPageOverlay *overlay = objc_getAssociatedObject(page, &CGDOverlayKey);
    if (!overlay) {
        overlay = [[CGDPageOverlay alloc] initWithFrame:page.view.bounds];
        overlay.page = page;
        objc_setAssociatedObject(page, &CGDOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != page.view) {
        [overlay removeFromSuperview];
        [page.view addSubview:overlay];
    }
    [overlay activate];
    if (!CGRectEqualToRect(overlay.frame, page.view.bounds)) overlay.frame = page.view.bounds;
    if (page.view.subviews.lastObject != overlay) [page.view bringSubviewToFront:overlay];
    [overlay setNeedsLayout];
    [[CGDAdapter shared] setHookState:CGDL(@"已添加到播放页") forKey:@"曲目信息按钮"];
}

static void CGDPageAppeared(UIViewController *page) {
    CGDPageAttach(page, @"viewDidAppear");
}

static void CGDPageDisappeared(UIViewController *page) {
    CGDPageOverlay *overlay = objc_getAssociatedObject(page, &CGDOverlayKey);
    [overlay deactivate];
    if (overlay) [[CGDAdapter shared] setHookState:CGDL(@"随播放页隐藏") forKey:@"曲目信息按钮"];
}

static void CGDPageLayout(UIViewController *page) {
    CGDPageOverlay *overlay = objc_getAssociatedObject(page, &CGDOverlayKey);
    // Some custom containers lay out a page without forwarding appearance.
    // Only checked page classes (or a provider-marked instance) qualify.
    // This uses this page alone. Entry discovery is bounded and cached.
    if (!overlay && page.isViewLoaded && page.view.window && !page.view.hidden &&
        page.view.alpha > 0 && (objc_getAssociatedObject(page, &CGDPageMarkerKey) || CGDIsKnownPage(page))) {
        CGDPageAttach(page, CGDL(@"首次在窗口中布局"));
        overlay = objc_getAssociatedObject(page, &CGDOverlayKey);
    }
    if (overlay && !overlay.hidden) {
        if (!CGRectEqualToRect(overlay.frame, page.view.bounds)) overlay.frame = page.view.bounds;
        if (page.view.subviews.lastObject != overlay) [page.view bringSubviewToFront:overlay];
        [overlay setNeedsLayout];
    }
}

static BOOL CGDInstallLifecycleMethod(Class cls, SEL selector, BOOL hasBoolean,
                                      void (*callback)(UIViewController *)) {
    char expected[] = {'v', '@', ':', @encode(BOOL)[0], '\0'};
    if (!hasBoolean) expected[3] = '\0';
    if (!CGDMethodMatches(cls, selector, expected)) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    IMP previous = method_getImplementation(method);
    IMP replacement;
    if (hasBoolean) {
        replacement = imp_implementationWithBlock(^(UIViewController *object, BOOL animated) {
            ((void (*)(id, SEL, BOOL))previous)(object, selector, animated);
            @try { if (NSThread.isMainThread) callback(object); }
            @catch (NSException *exception) {
                [[CGDAdapter shared] recordIssue:[CGDL(@"播放页回调异常：") stringByAppendingString:exception.name]];
            }
        });
    } else {
        replacement = imp_implementationWithBlock(^(UIViewController *object) {
            ((void (*)(id, SEL))previous)(object, selector);
            @try { if (NSThread.isMainThread) callback(object); }
            @catch (NSException *exception) {
                [[CGDAdapter shared] recordIssue:[CGDL(@"播放页布局异常：") stringByAppendingString:exception.name]];
            }
        });
    }
    // class_replaceMethod adds a local override if the method was inherited.
    // It never mutates the UIViewController superclass.
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    return YES;
}

static BOOL CGDInstallPageClass(Class cls) {
    if (!NSThread.isMainThread || !cls || cls == UIViewController.class ||
        ![cls isSubclassOfClass:UIViewController.class]) return NO;
    const char *image = class_getImageName(cls);
    NSString *imagePath = image ? [NSString stringWithUTF8String:image] : nil;
    NSString *appPrefix = [NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"];
    if (!imagePath || ![imagePath hasPrefix:appPrefix]) {
        [[CGDAdapter shared] recordIssue:CGDL(@"播放页类不在应用包内，未修改系统控制器")];
        return NO;
    }
    static NSMutableSet *installed;
    if (!installed) installed = [NSMutableSet set];
    NSString *name = NSStringFromClass(cls);
    if (![installed containsObject:name]) {
        char boolEncoding[] = {'v', '@', ':', @encode(BOOL)[0], '\0'};
        if (!CGDMethodMatches(cls, @selector(viewDidAppear:), boolEncoding) ||
            !CGDMethodMatches(cls, @selector(viewWillDisappear:), boolEncoding) ||
            !CGDMethodMatches(cls, @selector(viewDidLayoutSubviews), "v@:")) {
            [[CGDAdapter shared] recordIssue:CGDL(@"播放页生命周期签名不符，入口未安装")];
            return NO;
        }
        CGDInstallLifecycleMethod(cls, @selector(viewDidAppear:), YES, CGDPageAppeared);
        CGDInstallLifecycleMethod(cls, @selector(viewWillDisappear:), YES, CGDPageDisappeared);
        CGDInstallLifecycleMethod(cls, @selector(viewDidLayoutSubviews), NO, CGDPageLayout);
        [installed addObject:name];
    }
    return YES;
}

void CGDInstallPageLifecycle(UIViewController *page) {
    Class pageClass = object_getClass(page);
    // KVO-created classes have no app image; install on their real app class,
    // preserving the KVO subclass and its existing overrides.
    if ([NSStringFromClass(pageClass) hasPrefix:@"NSKVONotifying_"]) {
        pageClass = class_getSuperclass(pageClass);
    }
    if (!CGDInstallPageClass(pageClass)) return;
    objc_setAssociatedObject(page, &CGDPageMarkerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGDPageAttach(page, CGDL(@"服务返回或手动定位")); // Registration may follow appearance.
    [[CGDAdapter shared] setHookState:CGDL(@"已接入；按钮在捕获的播放页内")
                              forKey:@"播放页生命周期"];
}

void CGDInstallKnownPageHooks(void) {
    if (!NSThread.isMainThread) return;
    // A provider may exist without being called on this app's presentation path.
    // Install on the exact supported controller classes before their appearance.
    for (NSString *name in CGDPageTargetNames()) {
        NSString *status;
        @try {
            Class cls = NSClassFromString(name);
            status = !cls ? CGDL(@"类未找到") :
                (CGDInstallPageClass(cls) ? CGDL(@"生命周期已安装") : CGDL(@"校验未通过，已跳过"));
        } @catch (NSException *exception) {
            status = [CGDL(@"检测异常：") stringByAppendingString:exception.name];
        }
        [[CGDAdapter shared] setHookState:status
            forKey:[@"页面直接接入 " stringByAppendingString:name]];
    }
}
