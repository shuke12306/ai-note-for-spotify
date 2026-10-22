#import "CGDModulePreferences.h"

static NSString *const CGDLayoutKey = @"CGDClassicalGuide.ModuleLayout";

NSArray<NSString *> *CGDGuideModuleIDs(void) {
    return @[@"original", @"translation", @"breakdown", @"background", @"performers", @"listening"];
}

NSString *CGDGuideModuleTitle(NSString *identifier) {
    NSDictionary *titles = @{@"original": @"原始曲目信息", @"translation": @"曲名翻译",
        @"breakdown": @"标题拆解", @"background": @"作品背景", @"listening": @"欣赏提示",
        @"performers": @"演奏者 / 乐团介绍"};
    return [titles objectForKey:identifier] ?: identifier;
}

static NSDictionary *CGDNormalizeLayout(id value) {
    NSDictionary *stored = [value isKindOfClass:NSDictionary.class] ? value : @{};
    NSArray *known = CGDGuideModuleIDs();
    NSMutableArray *order = [NSMutableArray array];
    NSMutableArray *hidden = [NSMutableArray array];
    id storedOrder = [stored objectForKey:@"order"];
    if ([storedOrder isKindOfClass:NSArray.class]) {
        for (id identifier in storedOrder) {
            if ([identifier isKindOfClass:NSString.class] && [known containsObject:identifier] &&
                ![order containsObject:identifier]) [order addObject:identifier];
        }
    }
    // Newly introduced modules append once. Invalid/removed IDs never become views.
    for (NSString *identifier in known) {
        if (![order containsObject:identifier]) [order addObject:identifier];
    }
    id storedHidden = [stored objectForKey:@"hidden"];
    if ([storedHidden isKindOfClass:NSArray.class]) {
        for (id identifier in storedHidden) {
            if ([identifier isKindOfClass:NSString.class] && [known containsObject:identifier] &&
                ![hidden containsObject:identifier]) [hidden addObject:identifier];
        }
    }
    return @{@"order": [NSArray arrayWithArray:order], @"hidden": [NSArray arrayWithArray:hidden]};
}

NSDictionary *CGDLoadModuleLayout(void) {
    return CGDNormalizeLayout([NSUserDefaults.standardUserDefaults objectForKey:CGDLayoutKey]);
}

void CGDSaveModuleLayout(NSArray *order, NSArray *hidden) {
    NSDictionary *layout = CGDNormalizeLayout(@{@"order": order ?: @[], @"hidden": hidden ?: @[]});
    [NSUserDefaults.standardUserDefaults setObject:layout forKey:CGDLayoutKey];
}
