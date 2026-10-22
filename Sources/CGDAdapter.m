#import "CGDLocalization.h"
#import "CGDAdapter.h"

@interface CGDAdapter ()
@property(nonatomic, weak) id player;
@property(nonatomic, copy) NSString *pageClassName;
@property(nonatomic, strong) NSMutableDictionary *hookStates;
@property(nonatomic, strong) NSMutableArray *issues;
@end

@implementation CGDAdapter
+ (instancetype)shared {
    static CGDAdapter *adapter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adapter = [[self alloc] init];
        adapter.hookStates = [NSMutableDictionary dictionary];
        adapter.issues = [NSMutableArray array];
    });
    return adapter;
}

- (void)capturePlayer:(id)player {
    @synchronized (self) {
        // Never keep a previous player after an invalid/new provider result.
        self.player = player && CGDMethodMatches(object_getClass(player),
            NSSelectorFromString(@"currentTrack"), "@@:") ? player : nil;
        self.hookStates[@"播放器捕获"] = self.player ? @"已捕获（弱引用）" : @"本次未取得兼容播放器";
        if (player && !self.player) [self recordIssue:@"播放器返回对象缺少兼容的 currentTrack"];
    }
}

- (void)capturePage:(id)page {
    if (![page isKindOfClass:UIViewController.class]) {
        [self recordIssue:@"播放页服务未返回 UIViewController"];
        return;
    }
    // Retain only until main-thread registration; UIKit owns the page afterward.
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self recordPageClass:object_getClass(page) source:@"服务返回"];
            CGDInstallPageLifecycle(page);
        } @catch (NSException *exception) {
            [self recordIssue:[@"播放页注册异常：" stringByAppendingString:exception.name]];
        }
    });
}

- (void)recordPageClass:(Class)pageClass source:(NSString *)source {
    @synchronized (self) {
        self.pageClassName = NSStringFromClass(pageClass);
        self.hookStates[@"播放页捕获"] = [@"已捕获，来源：" stringByAppendingString:source];
    }
}

- (NSDictionary *)snapshot {
    NSAssert(NSThread.isMainThread, @"Read Spotify getters on the main thread");
    id player;
    @synchronized (self) { player = self.player; }
    return CGDReadTrackSnapshot(player);
}

- (void)setHookState:(NSString *)state forKey:(NSString *)key {
    @synchronized (self) { self.hookStates[key] = state; }
}

- (void)recordIssue:(NSString *)issue {
    @synchronized (self) {
        if (![self.issues containsObject:issue]) [self.issues addObject:issue];
        if (self.issues.count > 12) [self.issues removeObjectAtIndex:0];
    }
}

- (NSString *)diagnosticsForSnapshot:(NSDictionary *)snapshot {
    NSMutableArray *lines = [NSMutableArray arrayWithArray:@[
        [NSString stringWithFormat:@"%@ %@", CGD_PLUGIN_NAME, CGD_PLUGIN_VERSION],
        [NSString stringWithFormat:CGDL(@"Spotify %@（构建 %@）"),
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: CGDL(@"未知"),
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: CGDL(@"未知")],
        [CGDL(@"读取状态：") stringByAppendingString:CGDLocalizedMessage(snapshot[@"status"])],
    ]];
    NSArray *fields = @[@"title", @"artist", @"album", @"playerClass", @"trackClass"];
    NSArray *labels = @[CGDL(@"曲名"), CGDL(@"艺术家"), CGDL(@"专辑"), CGDL(@"播放器类"), CGDL(@"曲目类")];
    for (NSUInteger i = 0; i < fields.count; i++) {
        NSString *value = snapshot[fields[i]];
        if (i >= 3 && ([value isEqual:@"未捕获"] || [value isEqual:@"未取得"])) value = CGDL(value);
        [lines addObject:[NSString stringWithFormat:CGDL(@"%@：%@"), labels[i],
            value.length ? value : CGDL(@"未取得")]];
    }
    @synchronized (self) {
        [lines addObject:[CGDL(@"播放页类：") stringByAppendingString:self.pageClassName ?: CGDL(@"未捕获")]];
        for (NSString *key in [self.hookStates.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [lines addObject:[NSString stringWithFormat:CGDL(@"%@：%@"), CGDLocalizedMessage(key), CGDLocalizedMessage(self.hookStates[key])]];
        }
        for (NSString *issue in self.issues) [lines addObject:CGDLocalizedMessage(issue)];
    }
    [lines addObject:[CGDL(@"曲目相关元数据键：") stringByAppendingString:
        [snapshot[@"metadataKeys"] componentsJoinedByString:@", "]]];
    for (NSString *note in snapshot[@"notes"]) [lines addObject:CGDLocalizedMessage(note)];
    return [lines componentsJoinedByString:@"\n"];
}
@end
