#import "CGDGuideLanguage.h"

static NSString *const CGDLanguagePreference = @"CGDClassicalGuide.GuideLanguage";

NSArray<NSDictionary *> *CGDGuideLanguageOptions(void) {
    return @[
        @{@"code": @"zh-Hans", @"name": @"简体中文"},
        @{@"code": @"en", @"name": @"英语 (English)"},
        @{@"code": @"ja", @"name": @"日语 (日本語)"},
        @{@"code": @"ko", @"name": @"韩语 (한국어)"},
        @{@"code": @"fr", @"name": @"法语 (Français)"},
        @{@"code": @"de", @"name": @"德语 (Deutsch)"},
        @{@"code": @"es", @"name": @"西班牙语 (Español)"},
        @{@"code": @"it", @"name": @"意大利语 (Italiano)"},
        @{@"code": @"pt", @"name": @"葡萄牙语 (Português)"},
        @{@"code": @"ru", @"name": @"俄语 (Русский)"},
    ];
}

static NSString *CGDCustomLanguageName(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > 64) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    NSMutableCharacterSet *allowed = [NSCharacterSet.letterCharacterSet mutableCopy];
    [allowed formUnionWithCharacterSet:NSCharacterSet.nonBaseCharacterSet];
    [allowed addCharactersInString:@" -_()（）·/."];
    if ([trimmed rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound ||
        [trimmed rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return nil;
    return trimmed;
}

NSDictionary *CGDLoadGuideLanguage(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:CGDLanguagePreference];
    if ([stored isKindOfClass:NSDictionary.class]) {
        id code = [stored objectForKey:@"code"];
        for (NSDictionary *option in CGDGuideLanguageOptions()) {
            if ([[option objectForKey:@"code"] isEqual:code]) return @{@"code": code};
        }
        NSString *custom = CGDCustomLanguageName([stored objectForKey:@"custom"]);
        if ([code isEqual:@"custom"] && custom) return @{@"code": @"custom", @"custom": custom};
    }
    return @{@"code": @"zh-Hans"};
}

NSString *CGDGuideLanguageName(NSDictionary *selection) {
    for (NSDictionary *option in CGDGuideLanguageOptions()) {
        if ([[option objectForKey:@"code"] isEqual:[selection objectForKey:@"code"]]) return [option objectForKey:@"name"];
    }
    if ([[selection objectForKey:@"code"] isEqual:@"custom"]) {
        NSString *custom = CGDCustomLanguageName([selection objectForKey:@"custom"]);
        if (custom) return custom;
    }
    return @"简体中文";
}

NSString *CGDSaveGuideLanguage(NSString *code, NSString *customName) {
    for (NSDictionary *option in CGDGuideLanguageOptions()) {
        if ([[option objectForKey:@"code"] isEqual:code]) {
            [NSUserDefaults.standardUserDefaults setObject:@{@"code": code} forKey:CGDLanguagePreference];
            return nil;
        }
    }
    NSString *custom = CGDCustomLanguageName(customName);
    if (![code isEqual:@"custom"] || !custom) return @"请输入 1–64 个字符的语言名称，例如“繁体中文”或“阿拉伯语”；不要填写指令或换行。";
    [NSUserDefaults.standardUserDefaults setObject:@{@"code": @"custom", @"custom": custom} forKey:CGDLanguagePreference];
    return nil;
}
