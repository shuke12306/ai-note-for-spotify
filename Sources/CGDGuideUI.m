#import "CGDLocalization.h"
#import "CGDGuideUI.h"
#import "CGDAdapter.h"
#import "CGDSettingsStore.h"
#import "CGDModulePreferences.h"
#import "CGDPlaybackTheme.h"
#import "CGDGuideService.h"
#import "CGDGuideLanguage.h"
#import "CGDGuidePrompts.h"
#import "CGDGuideData.h"
#import "CGDGuideLibrary.h"

static UIColor *CGDNavigationButtonColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
            [UIColor colorWithRed:0.55 green:0.75 blue:1 alpha:1] :
            [UIColor colorWithRed:0 green:0.27 blue:0.65 alpha:1];
    }];
}

static void CGDSetButtonAppearance(UIBarButtonItemAppearance *appearance, UIColor *foreground, UIColor *disabled) {
    NSDictionary *active = @{NSForegroundColorAttributeName: foreground};
    appearance.normal.titleTextAttributes = active;
    appearance.highlighted.titleTextAttributes = active;
    appearance.disabled.titleTextAttributes = @{NSForegroundColorAttributeName: disabled};
}

@interface CGDNavigationController : UINavigationController <UINavigationControllerDelegate>
@property(nonatomic, strong) CGDPlaybackTheme *cgdTheme;
@end

static CGDPlaybackTheme *CGDControllerTheme(UIViewController *controller) {
    UINavigationController *nav = controller.navigationController;
    return [nav isKindOfClass:CGDNavigationController.class] ? ((CGDNavigationController *)nav).cgdTheme : nil;
}

@implementation CGDNavigationController
@synthesize cgdTheme = _cgdTheme;
- (void)setCgdTheme:(CGDPlaybackTheme *)theme {
    _cgdTheme = theme;
    self.overrideUserInterfaceStyle = theme ?
        (theme.dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight) : UIUserInterfaceStyleUnspecified;
    if (self.isViewLoaded) [self applyNavigationTheme];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
    [self applyNavigationTheme];
}
- (void)applyNavigationTheme {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    UIColor *foreground = self.cgdTheme.navigationTextColor ?: CGDNavigationButtonColor();
    UIColor *disabled = self.cgdTheme ? [foreground colorWithAlphaComponent:.5] : UIColor.secondaryLabelColor;
    appearance.backgroundColor = self.cgdTheme.colors.firstObject ?: UIColor.secondarySystemGroupedBackgroundColor;
    appearance.shadowColor = UIColor.separatorColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: self.cgdTheme.navigationTextColor ?: UIColor.labelColor};
    appearance.largeTitleTextAttributes = appearance.titleTextAttributes;
    CGDSetButtonAppearance(appearance.buttonAppearance, foreground, disabled);
    CGDSetButtonAppearance(appearance.doneButtonAppearance, foreground, disabled);
    CGDSetButtonAppearance(appearance.backButtonAppearance, foreground, disabled);
    UINavigationBar *bar = self.navigationBar;
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    // Runtime selector gating also supports the existing Clang 11 toolchain,
    // which lacks the runtime helper emitted by @available on this target.
    SEL compactEdgeSetter = @selector(setCompactScrollEdgeAppearance:);
    if ([bar respondsToSelector:compactEdgeSetter]) {
        [bar performSelector:@selector(setCompactScrollEdgeAppearance:) withObject:appearance];
    }
    bar.translucent = NO;
    bar.barStyle = UIBarStyleDefault;
    bar.tintColor = foreground;
    bar.titleTextAttributes = appearance.titleTextAttributes;
    bar.largeTitleTextAttributes = appearance.largeTitleTextAttributes;
}
- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
    (void)navigationController; (void)animated;
    // A host-wide UIBarButtonItem appearance can otherwise restore white text.
    // Set concrete plugin items too, including the synthesized back button.
    UINavigationItem *item = controller.navigationItem;
    NSMutableArray<UIBarButtonItem *> *buttons = [NSMutableArray array];
    [buttons addObjectsFromArray:item.leftBarButtonItems ?: @[]];
    [buttons addObjectsFromArray:item.rightBarButtonItems ?: @[]];
    UIBarButtonItem *back = [[UIBarButtonItem alloc] initWithTitle:CGDL(@"返回")
        style:UIBarButtonItemStylePlain target:nil action:NULL];
    item.backBarButtonItem = back;
    [buttons addObject:back];
    UIColor *foreground = self.cgdTheme.navigationTextColor ?: CGDNavigationButtonColor();
    UIColor *disabled = self.cgdTheme ? [foreground colorWithAlphaComponent:.5] : UIColor.secondaryLabelColor;
    for (UIBarButtonItem *button in buttons) {
        button.tintColor = foreground;
        NSDictionary *active = @{NSForegroundColorAttributeName: foreground};
        [button setTitleTextAttributes:active forState:UIControlStateNormal];
        [button setTitleTextAttributes:active forState:UIControlStateHighlighted];
        [button setTitleTextAttributes:@{NSForegroundColorAttributeName: disabled}
                             forState:UIControlStateDisabled];
    }
}
@end

UINavigationController *CGDMakeNavigationController(UIViewController *root) {
    UINavigationController *navigation = [[CGDNavigationController alloc] initWithRootViewController:root];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    return navigation;
}

@interface CGDTextLabel : UILabel
@property(nonatomic) BOOL secondary;
@end
@implementation CGDTextLabel
@end

static UILabel *CGDLabel(NSString *text, UIFontTextStyle style, BOOL secondary) {
    CGDTextLabel *label = [[CGDTextLabel alloc] init];
    label.secondary = secondary;
    label.text = text;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = secondary ? UIColor.secondaryLabelColor : UIColor.labelColor;
    return label;
}

static void CGDShowMessage(UIViewController *controller, NSString *title, NSString *message) {
    if (!controller.viewIfLoaded.window || controller.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CGDLocalizedMessage(title) message:CGDLocalizedMessage(message) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"好") style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
static void CGDAnchorMenu(UIAlertController *menu, UIViewController *controller, UIView *anchor) {
    menu.popoverPresentationController.sourceView = anchor ?: controller.view;
    menu.popoverPresentationController.sourceRect = anchor ? anchor.bounds : CGRectMake(controller.view.bounds.size.width / 2, 80, 1, 1);
}
// UIAlertAction handlers run before the outgoing sheet finishes dismissing.
// Wait for that transition before presenting another menu, alert or page.
static void CGDAfterMenu(UIViewController *controller, void (^action)(void)) {
    if (!controller || !action) return;
    UIViewController *presented = controller.presentedViewController;
    if (!presented) { action(); return; }
    if (![presented isKindOfClass:UIAlertController.class]) return;
    id<UIViewControllerTransitionCoordinator> transition = presented.transitionCoordinator;
    if (presented.isBeingDismissed && transition) {
        BOOL scheduled = [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (!context.isCancelled) action();
        }];
        if (scheduled) return;
    }
    [controller dismissViewControllerAnimated:YES completion:action];
}
static dispatch_queue_t CGDLibraryQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.classicalguide.library", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static CGDGuideLibrary *CGDLibrary(void) {
    static CGDGuideLibrary *library;
    if (!library) {
        NSString *directory = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        if (directory.length) library = [[CGDGuideLibrary alloc] initWithPath:[directory stringByAppendingPathComponent:@"com.classicalguide/favorites-v1.json"]];
    }
    return library;
}

@interface CGDSavedGuideController : UIViewController
@property(nonatomic, copy) NSDictionary *item;
@end
@implementation CGDSavedGuideController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = CGDL(@"已收藏的导赏");
    UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text.editable = NO; text.selectable = YES; text.adjustsFontForContentSizeCategory = YES;
    text.backgroundColor = UIColor.systemBackgroundColor; text.textColor = UIColor.labelColor;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.textContainerInset = UIEdgeInsetsMake(20, 16, 28, 16);
    text.text = CGDGuidePlainText(self.item[@"snapshot"], self.item[@"event"]);
    [self.view addSubview:text];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CGDL(@"复制") style:UIBarButtonItemStylePlain target:self action:@selector(copyText)];
}
- (void)copyText { UIPasteboard.generalPasteboard.string = CGDGuidePlainText(self.item[@"snapshot"], self.item[@"event"]); CGDShowMessage(self, CGDL(@"已复制"), nil); }
@end

@interface CGDLibraryController : UITableViewController
@property(nonatomic, copy) NSArray *items;
@property(nonatomic, copy) NSString *loadFailure;
@end
@implementation CGDLibraryController
- (void)viewDidLoad { [super viewDidLoad]; self.title = CGDL(@"我的收藏"); [self reloadLibrary]; }
- (void)reloadLibrary {
    __weak CGDLibraryController *weakSelf = self;
    dispatch_async(CGDLibraryQueue(), ^{
        CGDGuideLibrary *library = CGDLibrary(); NSArray *items = library.items;
        NSString *error = library ? library.loadError : CGDL(@"收藏暂不可用。");
        dispatch_async(dispatch_get_main_queue(), ^{
            CGDLibraryController *controller = weakSelf; if (!controller) return;
            controller.items = items ?: @[]; controller.loadFailure = error; [controller.tableView reloadData];
            if (error) CGDShowMessage(controller, CGDL(@"读取收藏失败"), error);
        });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.items.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.loadFailure) return CGDLocalizedMessage(self.loadFailure);
    return self.items.count ? CGDL(@"长按一项可移除收藏。收藏独立保存，清除导赏缓存不会移除收藏。") : CGDL(@"还没有收藏。在导赏右上角的更多菜单中选择“收藏当前导赏”。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CGDFavorite"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"CGDFavorite"];
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = item[@"snapshot"][@"title"]; cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", item[@"snapshot"][@"artist"] ?: @"", item[@"event"][@"language"]];
    cell.detailTextLabel.numberOfLines = 0; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CGDSavedGuideController *controller = [[CGDSavedGuideController alloc] init]; controller.item = self.items[indexPath.row];
    [self.navigationController pushViewController:controller animated:YES];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    (void)tableView; (void)point; NSDictionary *item = self.items[indexPath.row]; __weak CGDLibraryController *weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        (void)suggested;
        UIAction *remove = [UIAction actionWithTitle:CGDL(@"移除收藏") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *action) {
            (void)action; CGDLibraryController *controller = weakSelf; if (!controller) return;
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:CGDL(@"移除这篇收藏？") message:item[@"snapshot"][@"title"] preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:CGDL(@"移除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                (void)a; dispatch_async(CGDLibraryQueue(), ^{
                    NSString *error = [CGDLibrary() removeItem:item[@"id"]];
                    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadLibrary]; if (error) CGDShowMessage(weakSelf, CGDL(@"移除失败"), error); });
                });
            }]];
            [controller presentViewController:confirm animated:YES completion:nil];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithTitle:@"" children:@[remove]];
    }];
}
@end

@interface CGDRegenerateButton : UIButton
@property(nonatomic, strong) UIImage *refreshImage;
@property(nonatomic, strong) UIActivityIndicatorView *progress;
- (void)setGenerating:(BOOL)generating;
@end

@implementation CGDRegenerateButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.refreshImage = [UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular]];
        [self setImage:self.refreshImage forState:UIControlStateNormal];
        self.tintColor = UIColor.labelColor;
        self.alpha = .5;
        self.accessibilityHint = CGDL(@"重新生成这个模块");
        self.progress = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.progress.hidesWhenStopped = YES;
        self.progress.userInteractionEnabled = NO;
        self.progress.isAccessibilityElement = NO;
        self.progress.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.progress];
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:44],
            [self.heightAnchor constraintEqualToConstant:44],
            [self.progress.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.progress.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]]];
    }
    return self;
}
- (void)setGenerating:(BOOL)generating {
    [self setImage:generating ? nil : self.refreshImage forState:UIControlStateNormal];
    self.alpha = generating ? .7 : (self.enabled ? .5 : .25);
    self.accessibilityValue = generating ? CGDL(@"正在生成") : nil;
    if (generating) [self.progress startAnimating]; else [self.progress stopAnimating];
}
@end

@interface CGDCardStack : UIStackView
@end
@implementation CGDCardStack
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cardAppearanceChanged:)
            name:CGDCardAppearanceDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)cardAppearanceChanged:(NSNotification *)notification {
    (void)notification;
    [self refreshCardStyle];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self refreshCardStyle];
}
- (void)refreshCardStyle {
    if (!self.window) return;
    UIResponder *responder = self;
    for (NSUInteger i = 0; responder && i < 32; i++, responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        CGDPlaybackTheme *theme = CGDControllerTheme((UIViewController *)responder);
        self.backgroundColor = CGDResolvedCardColor(theme, ((UIViewController *)responder).traitCollection);
        self.overrideUserInterfaceStyle = CGDCardInterfaceStyle(self.backgroundColor);
        self.layer.borderWidth = .5;
        self.layer.borderColor = [CGDReadableCardText(self.backgroundColor, NO) colorWithAlphaComponent:.15].CGColor;
        // Only our small card subtree, on explicit style changes (never layout).
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:self.subviews];
        for (NSUInteger j = 0; j < views.count && j < 128; j++) {
            UIView *view = views[j];
            if ([view isKindOfClass:CGDTextLabel.class]) {
                CGDTextLabel *label = (CGDTextLabel *)view;
                label.textColor = CGDReadableCardText(self.backgroundColor, label.secondary);
            }
            if ([view isKindOfClass:CGDRegenerateButton.class]) {
                CGDRegenerateButton *button = (CGDRegenerateButton *)view;
                button.tintColor = CGDReadableCardText(self.backgroundColor, NO);
                button.progress.color = button.tintColor;
            }
            if (views.count < 128) {
                NSArray *children = view.subviews;
                [views addObjectsFromArray:[children subarrayWithRange:NSMakeRange(0, MIN(128 - views.count, children.count))]];
            }
        }
        break;
    }
}
@end

static UIStackView *CGDCard(NSString *title) {
    UIStackView *card = [[CGDCardStack alloc] initWithFrame:CGRectZero];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 10;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 18;
    card.layoutMarginsRelativeArrangement = YES;
    card.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(18, 18, 18, 18);
    if (title.length) {
        UILabel *heading = CGDLabel(title, UIFontTextStyleHeadline, NO);
        heading.accessibilityTraits |= UIAccessibilityTraitHeader;
        [card addArrangedSubview:heading];
    }
    return card;
}

static UIButton *CGDAction(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 8, 10, 8);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@interface CGDScrollController : UIViewController
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIStackView *content;
@property(nonatomic, strong) UIView *themeBackground;
@end

@implementation CGDScrollController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    if (theme) {
        self.view.backgroundColor = theme.colors.firstObject;
        self.themeBackground = CGDThemeBackground(theme, self.view.bounds);
        [self.view addSubview:self.themeBackground];
    }
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    self.content = [[UIStackView alloc] init];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content.axis = UILayoutConstraintAxisVertical;
    self.content.spacing = 16;
    [self.scrollView addSubview:self.content];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.content.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.content.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24],
        [self.content.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16],
        [self.content.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16],
        [self.content.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32],
    ]];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    // Also covers a navigation controller eagerly loading its root before the
    // captured theme is assigned. Theme installation still occurs just once.
    if (theme && !self.themeBackground) {
        self.themeBackground = CGDThemeBackground(theme, self.view.bounds);
        self.view.backgroundColor = theme.colors.firstObject;
        [self.view insertSubview:self.themeBackground atIndex:0];
    }
}
@end

static dispatch_queue_t CGDSettingsQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.classicalguide.settings", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@interface CGDModuleSettingsController : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSString *> *moduleOrder;
@property(nonatomic, strong) NSMutableArray<NSString *> *hiddenModules;
@end

@implementation CGDModuleSettingsController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGDL(@"导赏模块");
    NSDictionary *layout = CGDLoadModuleLayout();
    self.moduleOrder = [layout[@"order"] mutableCopy];
    self.hiddenModules = [layout[@"hidden"] mutableCopy];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.allowsSelectionDuringEditing = NO;
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    if (theme) self.tableView.backgroundView = CGDThemeBackground(theme, self.tableView.bounds);
    [self.tableView setEditing:YES animated:NO];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.moduleOrder.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDL(@"拖动右侧排序柄调整顺序");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDL(@"开关控制显示与隐藏。修改自动保存，返回导赏面板立即生效；关闭的模块也会保留排序。全部 AI 模块关闭时不生成新内容。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CGDModuleCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CGDModuleCell"];
    NSString *identifier = self.moduleOrder[indexPath.row];
    cell.textLabel.text = CGDL(CGDGuideModuleTitle(identifier));
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.showsReorderControl = YES;
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    cell.backgroundColor = CGDResolvedCardColor(theme, self.traitCollection);
    cell.overrideUserInterfaceStyle = CGDCardInterfaceStyle(cell.backgroundColor);
    cell.textLabel.textColor = CGDReadableCardText(cell.backgroundColor, NO);
    UISwitch *toggle = [[UISwitch alloc] init];
    // Identify by stable module ID, not row number: rows move while cells live.
    toggle.accessibilityIdentifier = identifier;
    toggle.accessibilityLabel = CGDL(CGDGuideModuleTitle(identifier));
    toggle.on = ![self.hiddenModules containsObject:identifier];
    [toggle addTarget:self action:@selector(toggleModule:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.editingAccessoryView = toggle;
    return cell;
}
- (void)toggleModule:(UISwitch *)toggle {
    NSString *identifier = toggle.accessibilityIdentifier;
    if (![self.moduleOrder containsObject:identifier]) return;
    [self.hiddenModules removeObject:identifier];
    if (!toggle.on) [self.hiddenModules addObject:identifier];
    CGDSaveModuleLayout(self.moduleOrder, self.hiddenModules);
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return YES;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return UITableViewCellEditingStyleNone;
}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return NO;
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    (void)tableView;
    NSString *identifier = self.moduleOrder[source.row];
    [self.moduleOrder removeObjectAtIndex:source.row];
    [self.moduleOrder insertObject:identifier atIndex:destination.row];
    CGDSaveModuleLayout(self.moduleOrder, self.hiddenModules);
}
@end

@interface CGDLanguageController : UITableViewController
@property(nonatomic, copy) NSDictionary *selection;
@property(nonatomic, copy) NSString *languageError;
@end

@implementation CGDLanguageController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGDL(@"导赏语言");
    self.selection = CGDLoadGuideLanguage();
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    if (theme) self.tableView.backgroundView = CGDThemeBackground(theme, self.tableView.bounds);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDGuideLanguageOptions().count + 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDL(@"选择 AI 导赏内容的语言");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDLocalizedMessage(self.languageError) ?: CGDL(@"选择后自动保存。返回导赏页时应用新语言，优先读取对应缓存；缺少内容时生成已开启的模块。界面语言独立设置。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CGDLanguageCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"CGDLanguageCell"];
    NSArray *options = CGDGuideLanguageOptions();
    BOOL custom = indexPath.row == (NSInteger)options.count;
    NSString *code = custom ? @"custom" : options[indexPath.row][@"code"];
    cell.textLabel.text = custom ? CGDL(@"自定义语言…") : CGDL(options[indexPath.row][@"name"]);
    cell.detailTextLabel.text = custom ? (self.selection[@"custom"] ?: CGDL(@"例如：繁体中文、阿拉伯语")) : nil;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.backgroundColor = CGDResolvedCardColor(CGDControllerTheme(self), self.traitCollection);
    cell.overrideUserInterfaceStyle = CGDCardInterfaceStyle(cell.backgroundColor);
    cell.textLabel.textColor = CGDReadableCardText(cell.backgroundColor, NO);
    cell.detailTextLabel.textColor = CGDReadableCardText(cell.backgroundColor, YES);
    cell.tintColor = cell.textLabel.textColor;
    cell.accessoryType = [self.selection[@"code"] isEqual:code] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)saveLanguage:(NSString *)code custom:(NSString *)custom {
    self.languageError = CGDSaveGuideLanguage(code, custom);
    self.selection = CGDLoadGuideLanguage();
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDLocalizedMessage(self.languageError) ?: CGDL(@"导赏语言已保存"));
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *options = CGDGuideLanguageOptions();
    if (indexPath.row < (NSInteger)options.count) {
        [self saveLanguage:options[indexPath.row][@"code"] custom:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CGDL(@"自定义导赏语言")
        message:CGDL(@"填写语言名称，例如“繁体中文”或“阿拉伯语”。") preferredStyle:UIAlertControllerStyleAlert];
    NSString *current = self.selection[@"custom"];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = CGDL(@"语言名称");
        field.text = current;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    __weak CGDLanguageController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"使用") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [weakSelf saveLanguage:@"custom" custom:weakAlert.textFields.firstObject.text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface CGDPromptEditorController : UIViewController <UITextViewDelegate>
@property(nonatomic, copy) NSString *module;
@property(nonatomic, strong) UITextView *editor;
@property(nonatomic, strong) UILabel *counter;
@property(nonatomic, strong) NSLayoutConstraint *editorBottom;
@end

@implementation CGDPromptEditorController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGDL(CGDPromptModuleTitle(self.module));
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CGDL(@"取消") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:CGDL(@"保存") style:UIBarButtonItemStyleDone target:self action:@selector(savePrompt)];
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    self.view.backgroundColor = theme.colors.firstObject ?: UIColor.systemGroupedBackgroundColor;
    if (theme) [self.view addSubview:CGDThemeBackground(theme, self.view.bounds)];
    UIStackView *header = CGDCard(nil);
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [header addArrangedSubview:CGDLabel(CGDL(@"修改这个模块的写法、重点和篇幅。输出语言沿用设置。保存后，下次生成此模块时生效。提示词正文保留原文，可用中文或英文编辑。"), UIFontTextStyleFootnote, YES)];
    [header addArrangedSubview:CGDAction(CGDL(@"恢复默认"), self, @selector(resetDraft))];
    self.counter = CGDLabel(@"", UIFontTextStyleFootnote, YES);
    [header addArrangedSubview:self.counter];
    [self.view addSubview:header];
    self.editor = [[UITextView alloc] init];
    self.editor.translatesAutoresizingMaskIntoConstraints = NO;
    self.editor.delegate = self;
    self.editor.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.editor.adjustsFontForContentSizeCategory = YES;
    UIColor *card = CGDResolvedCardColor(theme, self.traitCollection);
    self.editor.backgroundColor = card;
    self.editor.textColor = CGDReadableCardText(card, NO);
    self.editor.tintColor = self.editor.textColor;
    self.editor.overrideUserInterfaceStyle = CGDCardInterfaceStyle(card);
    self.editor.layer.cornerRadius = 16;
    self.editor.textContainerInset = UIEdgeInsetsMake(16, 12, 16, 12);
    self.editor.alwaysBounceVertical = YES;
    self.editor.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.editor.autocorrectionType = UITextAutocorrectionTypeNo;
    self.editor.smartQuotesType = UITextSmartQuotesTypeNo;
    self.editor.smartDashesType = UITextSmartDashesTypeNo;
    self.editor.accessibilityLabel = CGDL(@"模块提示词编辑框");
    self.editor.text = CGDLoadGuidePrompts()[self.module];
    UIToolbar *toolbar = [[UIToolbar alloc] init];
    [toolbar sizeToFit];
    toolbar.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL],
        [[UIBarButtonItem alloc] initWithTitle:CGDL(@"收起键盘") style:UIBarButtonItemStyleDone target:self action:@selector(endEditing)]];
    self.editor.inputAccessoryView = toolbar;
    [self.view addSubview:self.editor];
    self.editorBottom = [self.editor.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [header.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.editor.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],
        [self.editor.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [self.editor.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], self.editorBottom]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [self textViewDidChange:self.editor];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)textViewDidChange:(UITextView *)textView {
    self.counter.text = [NSString stringWithFormat:CGDL(@"%lu / %lu 字符"), (unsigned long)textView.text.length, (unsigned long)CGDGuidePromptLimit];
}
- (void)keyboardChanged:(NSNotification *)notification {
    if (!self.viewIfLoaded.window || self.navigationController.topViewController != self) return;
    CGRect frame = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
    CGRect overlap = CGRectIntersection(safe, frame);
    CGFloat height = CGRectIsNull(overlap) ? 0 : overlap.size.height;
    if ([notification.name isEqual:UIKeyboardWillHideNotification]) height = 0;
    self.editorBottom.constant = -12 - height;
    [self.view layoutIfNeeded];
    [self.editor scrollRangeToVisible:self.editor.selectedRange];
}
- (void)endEditing { [self.view endEditing:YES]; }
- (void)cancel { [self endEditing]; [self.navigationController popViewControllerAnimated:YES]; }
- (void)resetDraft {
    self.editor.text = CGDDefaultModulePrompt(self.module);
    [self textViewDidChange:self.editor];
    self.counter.text = [self.counter.text stringByAppendingString:CGDL(@" · 已填入默认内容，保存后生效")];
}
- (void)savePrompt {
    NSString *failure = CGDSaveModulePrompt(self.module, self.editor.text);
    if (failure) {
        self.counter.text = CGDLocalizedMessage(failure);
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDLocalizedMessage(failure));
        return;
    }
    [self endEditing];
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface CGDPromptSettingsController : UITableViewController
@end
@implementation CGDPromptSettingsController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGDL(@"模块提示词");
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    CGDPlaybackTheme *theme = CGDControllerTheme(self);
    if (theme) self.tableView.backgroundView = CGDThemeBackground(theme, self.tableView.bounds);
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return CGDPromptModuleIDs().count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return CGDL(@"选择模块查看和修改提示词，可恢复默认。保存不发起请求；返回导赏后可单独重生成这个模块。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CGDPromptCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"CGDPromptCell"];
    NSString *module = CGDPromptModuleIDs()[indexPath.row];
    cell.textLabel.text = CGDL(CGDPromptModuleTitle(module));
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = [CGDLoadGuidePrompts()[module] isEqual:CGDDefaultModulePrompt(module)] ? CGDL(@"默认提示词") : CGDL(@"已自定义");
    cell.backgroundColor = CGDResolvedCardColor(CGDControllerTheme(self), self.traitCollection);
    cell.overrideUserInterfaceStyle = CGDCardInterfaceStyle(cell.backgroundColor);
    cell.textLabel.textColor = CGDReadableCardText(cell.backgroundColor, NO);
    cell.detailTextLabel.textColor = CGDReadableCardText(cell.backgroundColor, YES);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CGDPromptEditorController *editor = [[CGDPromptEditorController alloc] init];
    editor.module = CGDPromptModuleIDs()[indexPath.row];
    [self.navigationController pushViewController:editor animated:YES];
}
@end

@interface CGDSettingsController : CGDScrollController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField *keyField;
@property(nonatomic, strong) UITextField *modelField;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *deleteButton;
@property(nonatomic, strong) UISlider *cardBrightnessSlider;
@property(nonatomic, strong) UILabel *cardBrightnessLabel;
@property(nonatomic, strong) UIButton *clearCacheButton;
@property(nonatomic, strong) UILabel *cacheStatusLabel;
@property(nonatomic, strong) UIButton *languageButton;
@property(nonatomic, strong) UISegmentedControl *interfaceLanguageControl;
@property(nonatomic) BOOL busy;
@end

@implementation CGDSettingsController
- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.textColor = UIColor.labelColor;
    field.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES;
    field.secureTextEntry = secure;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.smartQuotesType = UITextSmartQuotesTypeNo;
    field.smartDashesType = UITextSmartDashesTypeNo;
    field.keyboardType = UIKeyboardTypeASCIICapable;
    field.textContentType = @"";
    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    return field;
}

- (void)buildSettingsContent {
    for (UIView *view in [self.content.arrangedSubviews copy]) {
        [self.content removeArrangedSubview:view]; [view removeFromSuperview];
    }
    self.title = CGDL(@"设置");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:CGDL(@"保存") style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIStackView *interface = CGDCard(CGDL(@"界面语言"));
    self.interfaceLanguageControl = [[UISegmentedControl alloc] initWithItems:@[@"简体中文", @"English"]];
    self.interfaceLanguageControl.selectedSegmentIndex = [CGDInterfaceLanguage() isEqual:@"en"] ? 1 : 0;
    self.interfaceLanguageControl.accessibilityLabel = CGDL(@"界面语言");
    [self.interfaceLanguageControl.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self.interfaceLanguageControl addTarget:self action:@selector(changeInterfaceLanguage:) forControlEvents:UIControlEventValueChanged];
    [interface addArrangedSubview:self.interfaceLanguageControl];
    [interface addArrangedSubview:CGDLabel(CGDL(@"仅切换插件的按钮、菜单和提示文字，立即生效并自动保存。导赏内容的语言在下方单独设置。"), UIFontTextStyleFootnote, YES)];
    [self.content addArrangedSubview:interface];

    UIStackView *intro = CGDCard(CGDL(@"使用你的 DeepSeek API"));
    [intro addArrangedSubview:CGDLabel(CGDL(@"打开或返回导赏页时，会按当前设置复用缓存，只生成已开启且缺少缓存的模块。生成新内容会使用你的 API 额度；保存设置本身不会发起请求。"), UIFontTextStyleBody, NO)];
    [self.content addArrangedSubview:intro];

    UIStackView *modules = CGDCard(CGDL(@"阅读偏好"));
    self.cardBrightnessLabel = CGDLabel(@"", UIFontTextStyleBody, NO);
    [modules addArrangedSubview:self.cardBrightnessLabel];
    self.cardBrightnessSlider = [[UISlider alloc] init];
    self.cardBrightnessSlider.minimumValue = 0;
    self.cardBrightnessSlider.maximumValue = 100;
    self.cardBrightnessSlider.minimumTrackTintColor = UIColor.labelColor;
    self.cardBrightnessSlider.value = CGDCardBrightness() * 100;
    self.cardBrightnessSlider.accessibilityLabel = CGDL(@"卡片明暗");
    self.cardBrightnessSlider.accessibilityHint = CGDL(@"向右调浅，向左调深，松手后自动保存");
    [self.cardBrightnessSlider.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self.cardBrightnessSlider addTarget:self action:@selector(previewCardBrightness:) forControlEvents:UIControlEventValueChanged];
    [self.cardBrightnessSlider addTarget:self action:@selector(saveCardBrightness) forControlEvents:
        UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [modules addArrangedSubview:self.cardBrightnessSlider];
    [modules addArrangedSubview:CGDLabel(CGDL(@"左边更深，右边更浅。拖动即时预览，松手自动保存；仅改变文字卡片，歌曲背景保持原样。"), UIFontTextStyleFootnote, YES)];
    [self updateCardBrightnessLabel];
    [modules addArrangedSubview:CGDAction(CGDL(@"导赏模块：排序与开关"), self, @selector(openModules))];
    [self.content addArrangedSubview:modules];

    UIStackView *language = CGDCard(CGDL(@"导赏语言"));
    self.languageButton = CGDAction(CGDGuideLanguageDisplayName(CGDLoadGuideLanguage()), self, @selector(openLanguages));
    [language addArrangedSubview:self.languageButton];
    [language addArrangedSubview:CGDLabel(CGDL(@"10 种常用语言及自定义语言。选择后自动保存，下一次生成或打开导赏时使用；已有回答保留其原语言。"), UIFontTextStyleFootnote, YES)];
    [self.content addArrangedSubview:language];

    UIStackView *prompts = CGDCard(CGDL(@"AI 写作偏好"));
    [prompts addArrangedSubview:CGDAction(CGDL(@"分模块修改提示词"), self, @selector(openPrompts))];
    [self.content addArrangedSubview:prompts];

    UIStackView *credentials = CGDCard(@"DeepSeek API Key");
    self.statusLabel = CGDLabel(CGDL(@"正在读取本机配置…"), UIFontTextStyleSubheadline, YES);
    [credentials addArrangedSubview:self.statusLabel];
    self.keyField = [self fieldWithPlaceholder:CGDL(@"输入或粘贴新密钥") secure:YES];
    self.keyField.accessibilityLabel = CGDL(@"DeepSeek API Key，新密钥输入框");
    [credentials addArrangedSubview:self.keyField];
    [credentials addArrangedSubview:CGDLabel(CGDL(@"密钥保存到本机钥匙串，不回显、不写入诊断。留空保存会保留原密钥；填写新值会替换原密钥。"), UIFontTextStyleFootnote, YES)];
    self.deleteButton = CGDAction(CGDL(@"删除已保存的密钥"), self, @selector(confirmDelete));
    [self.deleteButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [credentials addArrangedSubview:self.deleteButton];
    [self.content addArrangedSubview:credentials];

    UIStackView *model = CGDCard(CGDL(@"模型"));
    self.modelField = [self fieldWithPlaceholder:@"deepseek-flash" secure:NO];
    self.modelField.accessibilityLabel = CGDL(@"DeepSeek 模型名称");
    [model addArrangedSubview:self.modelField];
    [model addArrangedSubview:CGDLabel(CGDL(@"默认 deepseek-flash，可改为账户可用且支持 JSON 输出的 DeepSeek 模型。关闭思考模式。更换模型后使用独立缓存。"), UIFontTextStyleFootnote, YES)];
    [self.content addArrangedSubview:model];

    UIStackView *cache = CGDCard(CGDL(@"本地缓存"));
    self.cacheStatusLabel = CGDLabel(CGDL(@"模块缓存最多保留 100 组曲目、4 MB。只生成已开启且缺少缓存的模块；修改一个模块的提示词，只更新该模块。收藏独立保存，不随缓存清除。"), UIFontTextStyleFootnote, YES);
    [cache addArrangedSubview:self.cacheStatusLabel];
    self.clearCacheButton = CGDAction(CGDL(@"清除导赏缓存"), self, @selector(clearGuideCache));
    [cache addArrangedSubview:self.clearCacheButton];
    [self.content addArrangedSubview:cache];
    [self.content addArrangedSubview:CGDAction(CGDL(@"我的收藏"), self, @selector(openLibrary))];

    UIStackView *about = CGDCard(CGDL(@"关于与诊断"));
    [about addArrangedSubview:CGDLabel([NSString stringWithFormat:@"%@ %@", CGD_PLUGIN_NAME, CGD_PLUGIN_VERSION], UIFontTextStyleBody, NO)];
    [about addArrangedSubview:CGDLabel(CGDL(@"发送曲名、艺术家、专辑、导赏语言和所选模块提示词给 DeepSeek，不发送账号或诊断数据。关闭面板后已提交的请求可能继续完成并保存到缓存；不会自动重试。AI 生成，背景信息未经资料核验。"), UIFontTextStyleFootnote, YES)];
    [about addArrangedSubview:CGDAction(CGDL(@"曲目与接入诊断"), self, @selector(openDiagnostics))];
    [self.content addArrangedSubview:about];

}
- (void)changeInterfaceLanguage:(UISegmentedControl *)control {
    if (self.busy) return;
    NSString *code = control.selectedSegmentIndex == 1 ? @"en" : @"zh-Hans";
    if ([code isEqual:CGDInterfaceLanguage()]) return;
    // Retain unsaved fields only in memory while rebuilding this settings page.
    NSString *modelDraft = [self.modelField.text copy], *keyDraft = [self.keyField.text copy];
    NSString *status = self.statusLabel.text, *cacheStatus = self.cacheStatusLabel.text;
    BOOL clearing = !self.clearCacheButton.enabled;
    CGPoint offset = self.scrollView.contentOffset;
    [self.view endEditing:YES];
    if (!CGDSaveInterfaceLanguage(code)) return;
    [self buildSettingsContent];
    self.modelField.text = modelDraft; self.keyField.text = keyDraft;
    self.statusLabel.text = CGDLocalizedMessage(status);
    self.cacheStatusLabel.text = CGDLocalizedMessage(cacheStatus);
    [self setControlsBusy:NO]; self.clearCacheButton.enabled = !clearing;
    for (UIViewController *controller in self.navigationController.viewControllers)
        controller.navigationItem.backBarButtonItem.title = CGDL(@"返回");
    // Re-created bar items also need the explicit colors that prevent the
    // host app's global appearance from making our Save title unreadable.
    if ([self.navigationController isKindOfClass:CGDNavigationController.class]) {
        CGDNavigationController *navigation = (CGDNavigationController *)self.navigationController;
        [navigation navigationController:navigation willShowViewController:self animated:NO];
    }
    [self.view layoutIfNeeded];
    [self.scrollView setContentOffset:offset animated:NO];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDL(@"界面语言已保存"));
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildSettingsContent];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)
        name:UIKeyboardWillHideNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clearDraft:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [self setControlsBusy:YES];
    __weak CGDSettingsController *weakSelf = self;
    dispatch_async(CGDSettingsQueue(), ^{
        NSString *modelName = CGDSettingsModelName();
        NSString *status = CGDSettingsKeyStatusText(CGDSettingsKeyStatus());
        dispatch_async(dispatch_get_main_queue(), ^{
            CGDSettingsController *controller = weakSelf;
            if (!controller) return;
            controller.modelField.text = modelName;
            controller.statusLabel.text = CGDLocalizedMessage(status);
            [controller setControlsBusy:NO];
        });
    });
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)clearDraft:(NSNotification *)notification {
    (void)notification;
    CGDSaveCardBrightness();
    self.keyField.text = @"";
    [self.view endEditing:YES];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    CGDSaveCardBrightness();
    self.keyField.text = @"";
    [self.view endEditing:YES];
}
- (void)updateCardBrightnessLabel {
    NSInteger value = (NSInteger)lround(CGDCardBrightness() * 100);
    self.cardBrightnessLabel.text = [NSString stringWithFormat:CGDL(@"卡片明暗 · %ld%%"), (long)value];
    self.cardBrightnessSlider.accessibilityValue = [NSString stringWithFormat:@"%ld%%", (long)value];
}
- (void)previewCardBrightness:(UISlider *)slider {
    CGDPreviewCardBrightness(slider.value / 100.0);
    [self updateCardBrightnessLabel];
    // VoiceOver adjusts without a touch-up event. Save each accessible step.
    if (!slider.tracking) CGDSaveCardBrightness();
}
- (void)saveCardBrightness { CGDSaveCardBrightness(); }
- (void)keyboardChanged:(NSNotification *)notification {
    if (!self.view.window) return;
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboard = [self.view convertRect:frame fromView:nil];
    CGRect overlap = CGRectIntersection(self.scrollView.frame, keyboard);
    CGFloat inset = CGRectIsNull(overlap) ? 0 : overlap.size.height;
    if ([notification.name isEqualToString:UIKeyboardWillHideNotification]) inset = 0;
    self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, inset, 0);
    self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset;
    UITextField *field = self.keyField.isFirstResponder ? self.keyField : self.modelField;
    if (field.isFirstResponder) {
        [self.scrollView scrollRectToVisible:CGRectInset([field convertRect:field.bounds toView:self.scrollView], 0, -16) animated:YES];
    }
}
- (void)setControlsBusy:(BOOL)busy {
    self.busy = busy;
    self.interfaceLanguageControl.enabled = !busy;
    self.navigationItem.rightBarButtonItem.enabled = !busy;
    self.deleteButton.enabled = !busy;
    self.keyField.enabled = !busy;
    self.modelField.enabled = !busy;
}
- (void)finishWithError:(NSString *)error status:(NSString *)status success:(NSString *)success {
    [self setControlsBusy:NO];
    // An authorized storage operation may finish after dismissal. No UI work or
    // alerts are sent to a controller that is no longer on screen.
    if (!self.view.window || self.navigationController.topViewController != self ||
        self.isBeingDismissed || self.navigationController.isBeingDismissed) return;
    self.statusLabel.text = CGDLocalizedMessage(error ?: [NSString stringWithFormat:@"%@\n%@", success, status]);
    self.statusLabel.textColor = error ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    if (!error && [self.statusLabel.superview isKindOfClass:CGDCardStack.class]) {
        [(CGDCardStack *)self.statusLabel.superview refreshCardStyle];
    }
    [self.view layoutIfNeeded];
    [self.scrollView scrollRectToVisible:[self.statusLabel convertRect:self.statusLabel.bounds toView:self.scrollView] animated:YES];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
}
- (void)save {
    if (self.busy) return;
    NSString *model = [self.modelField.text copy];
    NSString *replacementKey = [self.keyField.text copy];
    self.keyField.text = @"";
    [self.view endEditing:YES];
    [self setControlsBusy:YES];
    __weak CGDSettingsController *weakSelf = self;
    dispatch_async(CGDSettingsQueue(), ^{
        NSString *error = CGDSettingsSave(model, replacementKey);
        NSString *status = CGDSettingsKeyStatusText(CGDSettingsKeyStatus());
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishWithError:error status:status success:CGDL(@"配置已保存，尚未请求 API。")];
        });
    });
}
- (void)confirmDelete {
    if (self.busy) return;
    [self.view endEditing:YES];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CGDL(@"删除本机密钥？")
        message:CGDL(@"生成新的导赏时需要重新填写 API Key。已生成的缓存仍可阅读，模型设置保留。")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    __weak CGDSettingsController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:CGDL(@"删除") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        CGDSettingsController *controller = weakSelf;
        if (!controller || controller.busy) return;
        controller.keyField.text = @"";
        [controller setControlsBusy:YES];
        dispatch_async(CGDSettingsQueue(), ^{
            NSString *error = CGDSettingsDeleteKey();
            NSString *status = CGDSettingsKeyStatusText(CGDSettingsKeyStatus());
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishWithError:error status:status success:CGDL(@"已清除保存的密钥。")];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openDiagnostics {
    if (self.busy) return;
    // Close our own sheet before probing so the diagnostic captures Spotify.
    __weak UIViewController *host = self.navigationController.presentingViewController;
    [self.navigationController dismissViewControllerAnimated:YES completion:^{ CGDPresentDiagnostics(host); }];
}
- (void)clearGuideCache {
    if (!self.clearCacheButton.enabled) return;
    self.clearCacheButton.enabled = NO;
    self.cacheStatusLabel.text = CGDL(@"正在清除…");
    __weak CGDSettingsController *weakSelf = self;
    [[CGDGuideService shared] clearCache:^(NSString *failure) {
        CGDSettingsController *controller = weakSelf;
        if (!controller) return;
        controller.clearCacheButton.enabled = YES;
        controller.cacheStatusLabel.text = CGDLocalizedMessage(failure) ?: CGDL(@"已清除缓存。当前已经打开的导赏可继续阅读；下次打开时重新生成。");
    }];
}
- (void)openModules {
    [self.navigationController pushViewController:[[CGDModuleSettingsController alloc] init] animated:YES];
}
- (void)openLanguages {
    [self.navigationController pushViewController:[[CGDLanguageController alloc] init] animated:YES];
}
- (void)openPrompts {
    [self.navigationController pushViewController:[[CGDPromptSettingsController alloc] init] animated:YES];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.languageButton setTitle:CGDGuideLanguageDisplayName(CGDLoadGuideLanguage()) forState:UIControlStateNormal];
}
- (void)openLibrary { [self.navigationController pushViewController:[[CGDLibraryController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; }
@end

@interface CGDGuideController : CGDScrollController
@property(nonatomic, copy) NSDictionary *trackSnapshot;
@property(nonatomic, strong) NSDate *captureDate;
@property(nonatomic, strong) UIStackView *moduleStack;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UIStackView *> *moduleCards;
@property(nonatomic, strong) UILabel *trackLabel;
@property(nonatomic, strong) UILabel *progressLabel;
@property(nonatomic, strong) UILabel *sourceLabel;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) UIButton *generateButton;
@property(nonatomic, strong) UIButton *closeGuideButton;
@property(nonatomic, strong) NSMutableArray<CGDRegenerateButton *> *moduleButtons;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) NSDictionary *resultEvent;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic, copy) NSString *activeModule;
@property(nonatomic, strong) NSUUID *subscription;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL busy;
@property(nonatomic, strong) NSMutableDictionary *previousModules;
@property(nonatomic, copy) NSDictionary *lastConfiguration;
@property(nonatomic) BOOL statusIsError;
@end

@implementation CGDGuideController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = CGD_PLUGIN_NAME;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:CGDL(@"关闭") style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:CGDL(@"设置") style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"] style:UIBarButtonItemStylePlain target:self action:@selector(showMore)]];
    self.navigationItem.rightBarButtonItems.lastObject.accessibilityLabel = CGDL(@"更多导赏操作");
    self.previousModules = [NSMutableDictionary dictionary];
    UIStackView *notice = CGDCard(nil);
    self.trackLabel = CGDLabel(@"", UIFontTextStyleHeadline, NO);
    [notice addArrangedSubview:self.trackLabel];
    self.sourceLabel = CGDLabel(@"", UIFontTextStyleFootnote, YES);
    [notice addArrangedSubview:self.sourceLabel];
    self.progressLabel = CGDLabel(@"", UIFontTextStyleBody, NO);
    [notice addArrangedSubview:self.progressLabel];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [notice addArrangedSubview:self.spinner];
    self.generateButton = CGDAction(CGDL(@"生成导赏"), self, @selector(generate));
    [notice addArrangedSubview:self.generateButton];
    [self.content addArrangedSubview:notice];
    self.moduleStack = [[UIStackView alloc] init];
    self.moduleStack.axis = UILayoutConstraintAxisVertical;
    self.moduleStack.spacing = 16;
    [self.content addArrangedSubview:self.moduleStack];
    self.emptyLabel = CGDLabel(CGDL(@"所有导赏模块已关闭，可在设置中重新开启。"), UIFontTextStyleBody, NO);
    [self.content addArrangedSubview:self.emptyLabel];
    self.closeGuideButton = CGDAction(CGDL(@"关闭导赏，继续聆听"), self, @selector(close));
    [self.content addArrangedSubview:self.closeGuideButton];
    [self rebuildCards];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.leftBarButtonItem.title = CGDL(@"关闭");
    self.navigationItem.rightBarButtonItems.firstObject.title = CGDL(@"设置");
    self.navigationItem.rightBarButtonItems.lastObject.accessibilityLabel = CGDL(@"更多导赏操作");
    self.emptyLabel.text = CGDL(@"所有导赏模块已关闭，可在设置中重新开启。");
    [self.closeGuideButton setTitle:CGDL(@"关闭导赏，继续聆听") forState:UIControlStateNormal];
    // Layout first; changed settings are applied by viewDidAppear.
    [self rebuildCards];
    [self renderState];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Saving settings itself never requests. Returning to the guide explicitly
    // applies enabled-module/prompt changes, reusing unchanged module entries.
    if (!self.started || (!self.busy && ![self.lastConfiguration isEqual:[self currentConfiguration]])) {
        self.started = YES; [self loadGuide:NO];
    }
}
- (NSArray *)enabledModules {
    NSMutableArray *modules = [CGDPromptModuleIDs() mutableCopy];
    [modules removeObjectsInArray:CGDLoadModuleLayout()[@"hidden"]]; return modules;
}
- (NSDictionary *)currentConfiguration {
    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    NSDictionary *prompts = CGDLoadGuidePrompts();
    for (NSString *module in [self enabledModules]) keys[module] = prompts[module];
    return @{@"model": CGDSettingsModelName(), @"language": CGDGuideLanguageName(CGDLoadGuideLanguage()), @"modules": keys};
}
- (void)applyPendingConfiguration {
    if (!self.busy && self.viewIfLoaded.window && self.navigationController.topViewController == self &&
        !self.presentedViewController && !self.isBeingDismissed && !self.navigationController.isBeingDismissed &&
        ![self.lastConfiguration isEqual:[self currentConfiguration]]) [self loadGuide:NO];
}
- (BOOL)needsModules {
    if (!self.resultEvent || ![self.resultEvent[@"model"] isEqual:CGDSettingsModelName()] ||
        ![self.resultEvent[@"language"] isEqual:CGDGuideLanguageName(CGDLoadGuideLanguage())]) return YES;
    NSDictionary *prompts = CGDLoadGuidePrompts();
    for (NSString *module in [self enabledModules]) {
        if (![self.resultEvent[@"availableModules"] containsObject:module] ||
            [self.resultEvent[@"failedModules"] containsObject:module] ||
            ![self.resultEvent[@"prompts"][module] isEqual:prompts[module]]) return YES;
    }
    return NO;
}
- (void)dealloc { [[CGDGuideService shared] cancelSubscription:_subscription]; }
- (BOOL)hasVisibleAIModule {
    NSArray *hidden = CGDLoadModuleLayout()[@"hidden"];
    for (NSString *identifier in CGDGuideModuleIDs()) {
        if (![identifier isEqual:@"original"] && ![hidden containsObject:identifier]) return YES;
    }
    return NO;
}
- (void)applyModuleLayout {
    NSDictionary *layout = CGDLoadModuleLayout();
    for (UIView *view in [self.moduleStack.arrangedSubviews copy]) {
        [self.moduleStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSString *identifier in layout[@"order"]) {
        if ([layout[@"hidden"] containsObject:identifier]) continue;
        UIStackView *card = self.moduleCards[identifier];
        if (card) [self.moduleStack addArrangedSubview:card];
    }
    self.emptyLabel.hidden = [layout[@"hidden"] count] != CGDGuideModuleIDs().count;
    self.moduleStack.hidden = self.moduleStack.arrangedSubviews.count == 0;
}
- (void)rebuildCards {
    self.moduleCards = [NSMutableDictionary dictionary];
    self.moduleButtons = [NSMutableArray array];
    UIStackView *original = CGDCard(CGDL(@"当前曲目 · 原始信息"));
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    [original addArrangedSubview:CGDLabel([NSString stringWithFormat:CGDL(@"读取于 %@ · 本面板保留这次快照"), [formatter stringFromDate:self.captureDate]], UIFontTextStyleFootnote, YES)];
    NSArray *keys = @[@"title", @"artist", @"album"];
    NSArray *titles = @[CGDL(@"曲名"), CGDL(@"艺术家"), CGDL(@"专辑")];
    for (NSUInteger i = 0; i < keys.count; i++) {
        [original addArrangedSubview:CGDLabel(titles[i], UIFontTextStyleSubheadline, YES)];
        NSString *value = self.trackSnapshot[keys[i]];
        [original addArrangedSubview:CGDLabel(value.length ? value : CGDL(@"未取得"), i == 0 ? UIFontTextStyleHeadline : UIFontTextStyleBody, NO)];
    }
    self.moduleCards[@"original"] = original;
    NSDictionary *guide = self.resultEvent[@"guide"];
    if (guide) {
        NSArray *available = self.resultEvent[@"availableModules"] ?: @[];
        UIStackView *translation = CGDCard(CGDL(@"曲名翻译"));
        [translation addArrangedSubview:CGDLabel(guide[@"translated_title"], UIFontTextStyleTitle3, NO)];
        if ([guide[@"title_original"] boolValue]) [translation addArrangedSubview:CGDLabel(CGDL(@"译名未完整保留编号或调性，已保留原题；可尝试重新生成。"), UIFontTextStyleFootnote, YES)];
        if ([available containsObject:@"translation"]) self.moduleCards[@"translation"] = translation;
        UIStackView *terms = CGDCard(CGDL(@"标题拆解"));
        for (NSDictionary *term in guide[@"title_breakdown"]) {
            [terms addArrangedSubview:CGDLabel(term[@"term"], UIFontTextStyleSubheadline, YES)];
            [terms addArrangedSubview:CGDLabel(term[@"explanation"], UIFontTextStyleBody, NO)];
        }
        if ([guide[@"title_breakdown"] count]) self.moduleCards[@"breakdown"] = terms;
        if ([guide[@"background"] length]) {
            UIStackView *background = CGDCard(CGDL(@"作品背景"));
            [background addArrangedSubview:CGDLabel(guide[@"background"], UIFontTextStyleBody, NO)];
            self.moduleCards[@"background"] = background;
        }
        if ([guide[@"performer_info"] length]) {
            UIStackView *performers = CGDCard(CGDL(CGDGuideModuleTitle(@"performers")));
            [performers addArrangedSubview:CGDLabel(guide[@"performer_info"], UIFontTextStyleBody, NO)];
            self.moduleCards[@"performers"] = performers;
        }
        UIStackView *listening = CGDCard(CGDL(@"欣赏提示"));
        for (NSString *item in guide[@"listening_tips"]) [listening addArrangedSubview:CGDLabel([@"• " stringByAppendingString:item], UIFontTextStyleBody, NO)];
        if ([guide[@"listening_tips"] count]) self.moduleCards[@"listening"] = listening;
        for (NSString *module in CGDPromptModuleIDs()) {
            UIStackView *card = self.moduleCards[module];
            if (!card) continue;
            CGDRegenerateButton *button = [[CGDRegenerateButton alloc] initWithFrame:CGRectZero];
            [button addTarget:self action:@selector(regenerateTapped:) forControlEvents:UIControlEventTouchUpInside];
            button.tag = [CGDPromptModuleIDs() indexOfObject:module];
            button.accessibilityLabel = [NSString stringWithFormat:CGDL(@"重新生成%@"), CGDL(CGDPromptModuleTitle(module))];
            [card addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(moduleLongPressed:)]];
            card.tag = button.tag;
            button.enabled = !self.busy;
            [self.moduleButtons addObject:button];
            UIView *heading = card.arrangedSubviews.firstObject;
            [card removeArrangedSubview:heading];
            [heading removeFromSuperview];
            [heading setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
            UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[heading, button]];
            header.axis = UILayoutConstraintAxisHorizontal;
            header.alignment = UIStackViewAlignmentCenter;
            header.spacing = 8;
            [card insertArrangedSubview:header atIndex:0];
        }
    }
}
- (void)renderState {
    self.trackLabel.text = self.trackSnapshot[@"title"] ?: CGDL(@"尚未读到曲名");
    self.progressLabel.text = CGDLocalizedMessage(self.statusMessage) ?: CGDL(@"即将读取缓存或生成导赏…");
    self.generateButton.enabled = !self.busy;
    [self.generateButton setTitle:self.busy ? CGDL(@"正在生成，请稍候…") : (self.resultEvent ? CGDL(@"补齐 / 重试未完成模块") : CGDL(@"生成 / 重试")) forState:UIControlStateNormal];
    BOOL ready = self.resultEvent && ![self needsModules];
    self.sourceLabel.hidden = YES;
    self.trackLabel.hidden = ready && !self.busy && !self.statusIsError;
    self.progressLabel.hidden = ready && !self.busy && !self.statusIsError;
    self.generateButton.hidden = (ready && !self.busy) || ![self hasVisibleAIModule];
    ((UIStackView *)self.trackLabel.superview).hidden = ready && !self.busy && !self.statusIsError;
    for (CGDRegenerateButton *button in self.moduleButtons) {
        button.enabled = !self.busy;
        BOOL updating = self.busy && [CGDPromptModuleIDs()[button.tag] isEqual:self.activeModule];
        [button setGenerating:updating];
    }
    self.spinner.hidden = !self.busy;
    if (self.busy) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    if (self.resultEvent) {
        NSString *source = [self.resultEvent[@"source"] isEqual:@"cache"] ? CGDL(@"本地缓存") :
            ([self.resultEvent[@"source"] isEqual:@"module"] ? CGDL(@"模块已更新") : CGDL(@"DeepSeek 生成"));
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm";
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[self.resultEvent[@"generatedAt"] doubleValue]];
        self.sourceLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ · %@", source, self.resultEvent[@"model"], self.resultEvent[@"language"], [formatter stringFromDate:date]];
    } else self.sourceLabel.text = [NSString stringWithFormat:CGDL(@"导赏语言：%@。生成新内容会使用你的 DeepSeek API 额度。"), CGDGuideLanguageDisplayName(CGDLoadGuideLanguage())];
    [self applyModuleLayout];
}
- (void)loadGuide:(BOOL)force {
    if (self.busy) return;
    self.activeModule = nil;
    self.lastConfiguration = [self currentConfiguration];
    self.statusIsError = NO;
    if (![self hasVisibleAIModule]) {
        self.statusMessage = CGDL(@"AI 导赏模块均已关闭，未发起生成。可在设置中开启后点击生成。");
        [self renderState];
        return;
    }
    self.busy = YES;
    self.statusMessage = force ? CGDL(@"正在重新生成；完成后替换下方内容。") : CGDL(@"正在读取缓存；没有缓存时请求 DeepSeek…");
    [self renderState];
    NSUInteger generation = ++self.generation;
    __weak CGDGuideController *weakSelf = self;
    self.subscription = [[CGDGuideService shared] requestSnapshot:self.trackSnapshot modules:[self enabledModules] force:force baseEvent:self.resultEvent completion:^(NSDictionary *event) {
        CGDGuideController *controller = weakSelf;
        if (!controller || controller.generation != generation) return;
        controller.subscription = nil;
        controller.busy = NO;
        if (event[@"guide"]) {
            [controller acceptEvent:event];
            controller.statusMessage = event[@"error"] ?: event[@"warning"] ?: ([event[@"source"] isEqual:@"cache"] ? CGDL(@"已读取缓存，本次未请求 API。") :
                [NSString stringWithFormat:CGDL(@"已生成 %@ 个模块，复用 %@ 个模块。"), event[@"generatedCount"], event[@"cachedCount"]]);
        } else {
            NSString *problem = event[@"error"] ?: CGDL(@"生成失败，请重试。");
            controller.statusMessage = controller.resultEvent ? [problem stringByAppendingString:CGDL(@"\n下方保留这首曲目上一次的导赏。")] : problem;
        }
        controller.statusIsError = event[@"error"] != nil || event[@"warning"] != nil;
        // A settings page may be visible. Store data now, render only on entry.
        if (controller.viewIfLoaded.window && controller.navigationController.topViewController == controller &&
            !controller.isBeingDismissed && !controller.navigationController.isBeingDismissed) {
            [controller rebuildCards];
            [controller renderState];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDLocalizedMessage(controller.statusMessage));
            [controller applyPendingConfiguration];
        }
    }];
}
- (void)generate { [self loadGuide:NO]; }
- (void)acceptEvent:(NSDictionary *)event {
    NSDictionary *old = self.resultEvent;
    if (![old[@"trackIdentity"] isEqual:event[@"trackIdentity"]]) [self.previousModules removeAllObjects];
    else for (NSString *module in CGDPromptModuleIDs()) {
        if ([old[@"availableModules"] containsObject:module] && [event[@"availableModules"] containsObject:module] &&
            ![event[@"failedModules"] containsObject:module] &&
            ![old[@"moduleDates"][module] isEqual:event[@"moduleDates"][module]]) self.previousModules[module] = old;
    }
    self.resultEvent = event;
}
- (void)regenerateTapped:(UIButton *)sender {
    NSArray *modules = CGDPromptModuleIDs();
    if (sender.tag >= 0 && sender.tag < (NSInteger)modules.count) [self regenerateModule:modules[sender.tag]];
}
- (void)regenerateModule:(NSString *)module {
    if (self.busy || !self.resultEvent || ![CGDPromptModuleIDs() containsObject:module]) return;
    self.activeModule = module;
    self.statusIsError = NO;
    self.busy = YES;
    self.statusMessage = [NSString stringWithFormat:CGDL(@"正在重新生成%@…"), CGDL(CGDPromptModuleTitle(module))];
    [self renderState];
    NSUInteger generation = ++self.generation;
    __weak CGDGuideController *weakSelf = self;
    self.subscription = [[CGDGuideService shared] regenerateModule:module snapshot:self.trackSnapshot baseEvent:self.resultEvent completion:^(NSDictionary *event) {
        CGDGuideController *controller = weakSelf;
        if (!controller || controller.generation != generation) return;
        controller.subscription = nil;
        controller.busy = NO;
        if (event[@"guide"]) {
            [controller acceptEvent:event];
            controller.statusMessage = event[@"error"] ?: event[@"warning"] ?: [NSString stringWithFormat:CGDL(@"%@已更新。"), CGDL(CGDPromptModuleTitle(module))];
        } else controller.statusMessage = [(event[@"error"] ?: CGDL(@"生成失败，请重试。")) stringByAppendingString:CGDL(@" 原内容已保留。")];
        controller.statusIsError = event[@"error"] != nil || event[@"warning"] != nil;
        if (controller.viewIfLoaded.window && controller.navigationController.topViewController == controller &&
            !controller.isBeingDismissed && !controller.navigationController.isBeingDismissed) {
            CGPoint position = controller.scrollView.contentOffset;
            [controller rebuildCards];
            [controller renderState];
            [controller.view layoutIfNeeded];
            CGFloat limit = MAX(0, controller.scrollView.contentSize.height - controller.scrollView.bounds.size.height);
            controller.scrollView.contentOffset = CGPointMake(position.x, MIN(MAX(0, position.y), limit));
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDLocalizedMessage(controller.statusMessage));
            [controller applyPendingConfiguration];
        }
    }];
}
- (void)refreshTrack {
    [[CGDGuideService shared] cancelSubscription:self.subscription];
    self.subscription = nil;
    self.generation++;
    self.busy = NO;
    self.resultEvent = nil;
    [self.previousModules removeAllObjects];
    self.trackSnapshot = [[CGDAdapter shared] snapshot];
    self.captureDate = NSDate.date;
    [self rebuildCards];
    [self loadGuide:NO];
}
- (void)moduleLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSInteger index = gesture.view.tag;
    if (index >= 0 && index < (NSInteger)CGDPromptModuleIDs().count) [self showModule:CGDPromptModuleIDs()[index] anchor:gesture.view];
}
- (void)showModule:(NSString *)module anchor:(UIView *)anchor {
    if (self.presentedViewController) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:CGDL(CGDPromptModuleTitle(module)) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak CGDGuideController *weakSelf = self;
    NSString *text = CGDGuideModuleText(self.resultEvent[@"guide"], module);
    if (text.length) [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"复制本模块") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; UIPasteboard.generalPasteboard.string = text;
    }]];
    if (!self.busy) {
        NSString *title = [self.resultEvent[@"availableModules"] containsObject:module] ? CGDL(@"重新生成本模块") : CGDL(@"生成本模块");
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; [weakSelf regenerateModule:module];
        }]];
        if (self.previousModules[module]) [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"恢复上一版及其提示词") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; [weakSelf restoreModule:module];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    CGDAnchorMenu(menu, self, anchor); [self presentViewController:menu animated:YES completion:nil];
}
- (void)chooseModuleAction {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:CGDL(@"模块操作") message:CGDL(@"空白模块也可以在这里重新生成。") preferredStyle:UIAlertControllerStyleActionSheet];
    __weak CGDGuideController *weakSelf = self;
    for (NSString *module in [self enabledModules]) [menu addAction:[UIAlertAction actionWithTitle:CGDL(CGDPromptModuleTitle(module)) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; CGDAfterMenu(weakSelf, ^{ [weakSelf showModule:module anchor:nil]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    CGDAnchorMenu(menu, self, nil); [self presentViewController:menu animated:YES completion:nil];
}
- (void)restoreModule:(NSString *)module {
    NSDictionary *previous = self.previousModules[module]; if (!previous || self.busy) return;
    self.busy = YES; self.activeModule = module; self.statusIsError = NO; self.statusMessage = CGDL(@"正在恢复上一版…"); [self renderState];
    NSUInteger generation = ++self.generation; __weak CGDGuideController *weakSelf = self;
    [[CGDGuideService shared] restoreModule:module snapshot:self.trackSnapshot previousEvent:previous currentEvent:self.resultEvent completion:^(NSDictionary *event) {
        CGDGuideController *controller = weakSelf; if (!controller || controller.generation != generation) return;
        controller.busy = NO;
        if (event[@"guide"]) {
            controller.resultEvent = event; [controller.previousModules removeObjectForKey:module];
            CGDSaveModulePrompt(module, event[@"prompts"][module]);
            controller.lastConfiguration = [controller currentConfiguration];
        }
        controller.statusMessage = event[@"error"] ?: event[@"warning"] ?: CGDL(@"已恢复上一版。");
        controller.statusIsError = event[@"error"] != nil || event[@"warning"] != nil;
        [controller rebuildCards]; [controller renderState];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, CGDLocalizedMessage(controller.statusMessage));
    }];
}
- (void)saveFavorite {
    NSDictionary *snapshot = self.trackSnapshot, *event = self.resultEvent;
    __weak CGDGuideController *weakSelf = self;
    dispatch_async(CGDLibraryQueue(), ^{
        CGDGuideLibrary *library = CGDLibrary();
        NSString *error = library ? [library saveSnapshot:snapshot event:event] : CGDL(@"收藏暂不可用。");
        dispatch_async(dispatch_get_main_queue(), ^{ CGDShowMessage(weakSelf, error ? CGDL(@"收藏失败") : CGDL(@"已收藏"), error ?: CGDL(@"可在“我的收藏”中离线阅读。再次收藏会更新这篇内容。")); });
    });
}
- (void)showMore {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak CGDGuideController *weakSelf = self;
    if (self.resultEvent[@"guide"]) {
        [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"收藏当前导赏") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; CGDAfterMenu(weakSelf, ^{ [weakSelf saveFavorite]; }); }]];
        [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"复制整篇导赏") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; UIPasteboard.generalPasteboard.string = CGDGuidePlainText(weakSelf.trackSnapshot, weakSelf.resultEvent); }]];
        [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"模块操作") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; CGDAfterMenu(weakSelf, ^{ [weakSelf chooseModuleAction]; }); }]];
        [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"生成详情") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; CGDGuideController *controller = weakSelf; NSMutableArray *lines = [NSMutableArray array];
            [lines addObject:[NSString stringWithFormat:@"%@ · %@", controller.resultEvent[@"model"], controller.resultEvent[@"language"]]];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.dateFormat = @"MM-dd HH:mm";
            for (NSString *module in controller.resultEvent[@"availableModules"]) {
                NSNumber *date = controller.resultEvent[@"moduleDates"][module];
                if (date) [lines addObject:[NSString stringWithFormat:@"%@ · %@", CGDL(CGDPromptModuleTitle(module)), [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date.doubleValue]]]];
            }
            [lines addObject:[NSString stringWithFormat:CGDL(@"本次生成 %@ 个模块，复用 %@ 个模块"), controller.resultEvent[@"generatedCount"] ?: @0, controller.resultEvent[@"cachedCount"] ?: @0]];
            CGDAfterMenu(controller, ^{ CGDShowMessage(controller, CGDL(@"生成详情"), [lines componentsJoinedByString:@"\n"]); });
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"我的收藏") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; CGDAfterMenu(weakSelf, ^{ [weakSelf.navigationController pushViewController:[[CGDLibraryController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; });
    }]];
    if (!self.busy) {
        [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"读取正在播放的曲目") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [weakSelf refreshTrack]; }]];
        if (self.resultEvent && [self hasVisibleAIModule]) [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"重新生成已开启模块") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [weakSelf loadGuide:YES]; }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:CGDL(@"取消") style:UIAlertActionStyleCancel handler:nil]];
    CGDAnchorMenu(menu, self, nil); [self presentViewController:menu animated:YES completion:nil];
}
- (void)openSettings {
    [self.navigationController pushViewController:[[CGDSettingsController alloc] init] animated:YES];
}
- (void)close {
    self.generation++;
    [[CGDGuideService shared] cancelSubscription:self.subscription];
    self.subscription = nil;
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}
@end
void CGDPresentGuide(UIViewController *page) {
    if (!NSThread.isMainThread || !page.viewIfLoaded.window) return;
    UIViewController *presenter = page.viewIfLoaded.window.rootViewController ?: page;
    while (presenter.parentViewController) presenter = presenter.parentViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    UIViewController *top = [presenter isKindOfClass:UINavigationController.class] ?
        ((UINavigationController *)presenter).topViewController : presenter;
    if ([top isKindOfClass:CGDScrollController.class] ||
        [top isKindOfClass:NSClassFromString(@"CGDDiagnosticsController")] ||
        [presenter isKindOfClass:UIAlertController.class] || presenter.isBeingPresented ||
        presenter.isBeingDismissed || !presenter.viewIfLoaded.window) return;
    CGDGuideController *controller = [[CGDGuideController alloc] init];
    controller.trackSnapshot = [[CGDAdapter shared] snapshot];
    controller.captureDate = NSDate.date;
    CGDPlaybackTheme *theme = CGDReadPlaybackTheme(page);
    CGDNavigationController *navigation = (CGDNavigationController *)CGDMakeNavigationController(controller);
    navigation.cgdTheme = theme;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
