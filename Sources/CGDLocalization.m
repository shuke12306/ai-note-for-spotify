#import "CGDLocalization.h"
#import "CGDGuideLanguage.h"
#import "CGDLocalizationCatalog.h"

static NSString *const CGDInterfaceLanguageKey = @"CGDClassicalGuide.InterfaceLanguage";
NSString *const CGDInterfaceLanguageDidChangeNotification = @"CGDClassicalGuide.InterfaceLanguageDidChange";

NSString *CGDInterfaceLanguage(void) {
    return [[NSUserDefaults.standardUserDefaults objectForKey:CGDInterfaceLanguageKey] isEqual:@"en"] ? @"en" : @"zh-Hans";
}
BOOL CGDSaveInterfaceLanguage(NSString *code) {
    if (![code isEqual:@"en"] && ![code isEqual:@"zh-Hans"]) return NO;
    BOOL changed = ![code isEqual:CGDInterfaceLanguage()];
    [NSUserDefaults.standardUserDefaults setObject:code forKey:CGDInterfaceLanguageKey];
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:CGDInterfaceLanguageDidChangeNotification object:nil];
    return YES;
}
NSDictionary *CGDLocalizationCatalog(void) {
    static NSDictionary *catalog;
    @synchronized (NSUserDefaults.class) {
        if (!catalog) catalog = [CGDCreateLocalizationCatalog() copy];
    }
    return catalog;
}
NSString *CGDL(NSString *key) {
    if (!key) return nil;
    return [CGDInterfaceLanguage() isEqual:@"en"] ? ([CGDLocalizationCatalog() objectForKey:key] ?: key) : key;
}
NSString *CGDGuideLanguageDisplayName(NSDictionary *selection) {
    NSString *name = CGDGuideLanguageName(selection);
    // A custom language is user data, even if it happens to equal a catalog key.
    return [[selection objectForKey:@"code"] isEqual:@"custom"] ? name : CGDL(name);
}

// Status text can outlive a language switch (including an in-flight request).
// Match only full, known message templates and preserve captured values.
static NSArray *CGDFormatParts(NSString *format) {
    NSRegularExpression *tokens = [NSRegularExpression regularExpressionWithPattern:
        @"%(?:[-+0 #]*[0-9]*(?:\\.[0-9]+)?(?:ll|l|z)?[dufX@]|%)" options:0 error:NULL];
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableString *literal = [NSMutableString string];
    NSUInteger offset = 0;
    for (NSTextCheckingResult *match in [tokens matchesInString:format options:0 range:NSMakeRange(0, format.length)]) {
        [literal appendString:[format substringWithRange:NSMakeRange(offset, match.range.location - offset)]];
        if ([[format substringWithRange:match.range] isEqual:@"%%"]) [literal appendString:@"%"];
        else { [parts addObject:[NSString stringWithString:literal]]; [literal setString:@""]; }
        offset = NSMaxRange(match.range);
    }
    [literal appendString:[format substringFromIndex:offset]];
    [parts addObject:[NSString stringWithString:literal]];
    return parts;
}
static NSArray *CGDMessageTemplates(void) {
    static NSArray *templates;
    @synchronized (NSUserDefaults.class) {
        if (!templates) {
            NSMutableArray *items = [NSMutableArray array];
            for (NSString *key in [[CGDLocalizationCatalog() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *english = [CGDLocalizationCatalog() objectForKey:key];
                NSArray *zh = CGDFormatParts(key), *en = CGDFormatParts(english);
                if (zh.count <= 1 || zh.count != en.count) continue;
                for (NSUInteger language = 0; language < 2; language++) {
                    NSArray *parts = language ? en : zh;
                    NSMutableString *pattern = [NSMutableString stringWithString:@"\\A"];
                    for (NSUInteger i = 0; i < parts.count; i++) {
                        if (i) [pattern appendString:@"(.*?)"];
                        [pattern appendString:[NSRegularExpression escapedPatternForString:[parts objectAtIndex:i]]];
                    }
                    [pattern appendString:@"\\z"];
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                        options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
                    NSUInteger length = 0;
                    for (NSString *literal in parts) length += literal.length;
                    if (regex) [items addObject:@{@"regex": regex, @"zh": zh, @"en": en, @"specificity": @(length)}];
                }
            }
            // Specific messages must win over the generic "section: error" form.
            NSSortDescriptor *specificity = [NSSortDescriptor sortDescriptorWithKey:@"specificity" ascending:NO];
            templates = [[items sortedArrayUsingDescriptors:@[specificity]] copy];
        }
    }
    return templates;
}
static NSString *CGDMessage(NSString *message, NSUInteger depth) {
    if (!message.length || depth > 4 || message.length > 32768) return message;
    NSDictionary *catalog = CGDLocalizationCatalog();
    if ([catalog objectForKey:message]) return CGDL(message);
    for (NSString *key in catalog) if ([[catalog objectForKey:key] isEqual:message]) return CGDL(key);
    for (NSDictionary *item in CGDMessageTemplates()) {
        NSTextCheckingResult *match = [[item objectForKey:@"regex"] firstMatchInString:message options:0 range:NSMakeRange(0, message.length)];
        if (!match) continue;
        NSArray *parts = [item objectForKey:[CGDInterfaceLanguage() isEqual:@"en"] ? @"en" : @"zh"];
        NSMutableString *output = [NSMutableString stringWithString:[parts firstObject]];
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *value = [message substringWithRange:[match rangeAtIndex:i]];
            [output appendString:CGDMessage(value, depth + 1)];
            [output appendString:[parts objectAtIndex:i]];
        }
        return output;
    }
    if ([message containsString:@"\n"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *line in [message componentsSeparatedByString:@"\n"]) [lines addObject:CGDMessage(line, depth + 1)];
        return [lines componentsJoinedByString:@"\n"];
    }
    for (NSString *suffix in @[@" 原内容已保留。", @" · 已填入默认内容，保存后生效"]) {
        for (NSString *candidate in @[suffix, [catalog objectForKey:suffix] ?: suffix]) {
            if ([message hasSuffix:candidate] && message.length > candidate.length)
                return [CGDMessage([message substringToIndex:message.length - candidate.length], depth + 1) stringByAppendingString:CGDL(suffix)];
        }
    }
    return message;
}
NSString *CGDLocalizedMessage(NSString *message) { return CGDMessage(message, 0); }
