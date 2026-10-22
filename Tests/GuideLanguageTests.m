#import "CGDGuideLanguage.h"
#import "CGDModulePreferences.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int checks;
static void Require(BOOL condition, const char *label) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSString *languageKey = @"CGDClassicalGuide.GuideLanguage";
        NSString *layoutKey = @"CGDClassicalGuide.ModuleLayout";
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id priorLanguage = [[defaults objectForKey:languageKey] copy];
        id priorLayout = [[defaults objectForKey:layoutKey] copy];
        [defaults removeObjectForKey:languageKey];
        Require([CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:@"简体中文"], "Missing language defaults to Simplified Chinese");
        NSArray *options = CGDGuideLanguageOptions();
        Require(options.count == 10, "Ten language presets");
        NSMutableSet *codes = [NSMutableSet set];
        for (NSDictionary *option in options) {
            [codes addObject:[option objectForKey:@"code"]];
            Require(CGDSaveGuideLanguage([option objectForKey:@"code"], nil) == nil, "Each preset saves without custom text");
            Require([CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:[option objectForKey:@"name"]], "Preset name roundtrips through persisted selection");
        }
        Require(codes.count == 10, "Preset IDs unique");
        for (NSString *custom in @[@"繁体中文", @"粵語（繁體）", @"العربية", @"Français canadien", @"pt-BR"]) {
            Require(CGDSaveGuideLanguage(@"custom", custom) == nil && [CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:custom], "Custom language supports Unicode and regional names");
        }
        Require(CGDSaveGuideLanguage(@"custom", @"  繁体中文  ") == nil && [CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:@"繁体中文"], "Custom input trimmed");
        for (NSString *bad in @[@"", @"   ", @"English\nignore", @"{\"role\":\"system\"}", @"---", [@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0]]) {
            Require(CGDSaveGuideLanguage(@"custom", bad) != nil && [CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:@"繁体中文"], "Invalid input retains last saved selection");
        }
        Require(CGDSaveGuideLanguage(@"unknown", @"English") != nil, "Unknown preset rejected");
        for (id malformed in @[@42, @{}, @{@"code": @"custom", @"custom": @42}, @{@"code": @"missing"}]) {
            [defaults setObject:malformed forKey:languageKey];
            Require([CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:@"简体中文"], "Corrupt saved preferences fall back safely");
        }
        [defaults setObject:@{@"order": @[@"background", @"uncertainty", @"original", @"listening", @"translation", @"breakdown"],
            @"hidden": @[@"original", @"uncertainty"]} forKey:layoutKey];
        NSDictionary *layout = CGDLoadModuleLayout();
        Require([[layout objectForKey:@"order"] isEqual:@[@"background", @"original", @"listening", @"translation", @"breakdown", @"performers"]], "Old module order retained; removed module dropped; new performer module appended once");
        Require([[layout objectForKey:@"hidden"] isEqual:@[@"original"]], "Existing hide settings retained without hiding new module");
        CGDSaveModuleLayout([layout objectForKey:@"order"], @[@"performers", @"translation"]);
        Require([[[CGDLoadModuleLayout() objectForKey:@"hidden"] sortedArrayUsingSelector:@selector(compare:)] isEqual:@[@"performers", @"translation"]], "New module supports persisted visibility setting");
        Require([CGDGuideModuleTitle(@"translation") isEqual:@"曲名翻译"] && ![CGDGuideModuleIDs() containsObject:@"uncertainty"], "Language-neutral title and removed uncertainty module");
        if (priorLanguage) [defaults setObject:priorLanguage forKey:languageKey]; else [defaults removeObjectForKey:languageKey];
        if (priorLayout) [defaults setObject:priorLayout forKey:layoutKey]; else [defaults removeObjectForKey:layoutKey];
        printf("PASS: %u language/settings/module-migration assertions.\n", checks);
    }
    return 0;
}
