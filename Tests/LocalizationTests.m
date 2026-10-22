#import "CGDLocalization.h"
#import "CGDGuideLanguage.h"
#import "CGDGuideData.h"
#import "CGDGuideModuleCache.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int checks, notifications;
static void Require(BOOL value, const char *label) {
    checks++; if (!value) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}
@interface CGDLanguageObserver : NSObject
- (void)changed:(NSNotification *)note;
@end
@implementation CGDLanguageObserver
- (void)changed:(NSNotification *)note { (void)note; notifications++; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            // A fresh process must see the same persisted choice.
            return [CGDInterfaceLanguage() isEqual:@"en"] &&
                [CGDGuideLanguageName(CGDLoadGuideLanguage()) isEqual:@"日本語"] ? 0 : 2;
        }
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *uiKey = @"CGDClassicalGuide.InterfaceLanguage", *guideKey = @"CGDClassicalGuide.GuideLanguage";
        id previousUI = [[defaults objectForKey:uiKey] copy], previousGuide = [[defaults objectForKey:guideKey] copy];
        [defaults removeObjectForKey:uiKey];
        Require([CGDInterfaceLanguage() isEqual:@"zh-Hans"] && [CGDL(@"设置") isEqual:@"设置"], "Existing installs keep Chinese by default");
        for (id bad in @[@42, @{}, @[@"en"], @"fr", @"EN"]) {
            [defaults setObject:bad forKey:uiKey];
            Require([CGDInterfaceLanguage() isEqual:@"zh-Hans"], "Malformed preferences fall back safely");
        }
        CGDLanguageObserver *observer = [[CGDLanguageObserver alloc] init];
        [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(changed:) name:CGDInterfaceLanguageDidChangeNotification object:nil];
        Require(!CGDSaveInterfaceLanguage(@"fr") && !CGDSaveInterfaceLanguage(nil) && notifications == 0, "Unsupported choices do not save or notify");
        Require(CGDSaveGuideLanguage(@"custom", @"日本語") == nil, "Independent guide language configured");
        NSDictionary *selection = CGDLoadGuideLanguage();
        NSDictionary *prompts = CGDLoadGuidePrompts();
        NSDictionary *track = @{@"title": @"设置", @"artist": @"作品背景", @"album": @"导赏"};
        NSString *language = CGDGuideLanguageName(selection);
        NSDictionary *request = CGDGuideRequestBodyForModules(track, @"deepseek-flash", language, prompts, CGDPromptModuleIDs());
        NSData *identity = CGDGuideTrackIdentity(track, @"deepseek-flash", language);
        NSMutableDictionary *moduleKeys = [NSMutableDictionary dictionary];
        for (NSString *module in CGDPromptModuleIDs()) [moduleKeys setObject:CGDGuideModuleIdentity(track, @"deepseek-flash", language, prompts, module) forKey:module];
        Require(CGDSaveInterfaceLanguage(@"en") && notifications == 1 && [CGDL(@"设置") isEqual:@"Settings"], "English choice updates UI and notifies once");
        Require(CGDSaveInterfaceLanguage(@"en") && notifications == 1, "Same choice does not notify again");
        Require([[defaults objectForKey:uiKey] isEqual:@"en"], "Choice is saved in its own preference");
        Require(CGDL(nil) == nil && [CGDL(@"AI Note") isEqual:@"AI Note"], "Missing and unlisted keys are safe");
        Require([CGDGuideLanguageDisplayName(@{@"code": @"en"}) isEqual:@"English"], "Known guide language gets an English display name");
        Require([CGDGuideLanguageDisplayName(@{@"code": @"custom", @"custom": @"设置"}) isEqual:@"设置"], "Custom language text is never translated");
        Require([CGDLoadGuideLanguage() isEqual:selection] && [CGDLoadGuidePrompts() isEqual:prompts], "UI choice leaves guide language and prompt settings unchanged");
        Require([CGDGuideRequestBodyForModules(track, @"deepseek-flash", CGDGuideLanguageName(CGDLoadGuideLanguage()), CGDLoadGuidePrompts(), CGDPromptModuleIDs()) isEqual:request], "Switching UI leaves the exact API request unchanged");
        Require([CGDGuideTrackIdentity(track, @"deepseek-flash", language) isEqual:identity], "Track cache identity is unchanged");
        for (NSString *module in CGDPromptModuleIDs()) Require([CGDGuideModuleIdentity(track, @"deepseek-flash", language, CGDLoadGuidePrompts(), module) isEqual:[moduleKeys objectForKey:module]], "Every module keeps its cached identity");

        // A response from a request started before the switch must use the current UI language.
        Require([CGDLocalizedMessage(CGDGuideHTTPError(401)) isEqual:@"API key authentication failed. Check or replace the key in Settings."], "Late authentication errors use current language");
        NSString *http = CGDLocalizedMessage(CGDGuideHTTPError(418));
        Require([http isEqual:@"Request failed (HTTP 418). Please retry later."], "Formatted HTTP errors retain status codes");
        Require([CGDLocalizedMessage(@"卡片明暗 · 65%") isEqual:@"Card brightness · 65%"], "Formatted percentages retain literal percent");
        Require([CGDLocalizedMessage(@"作品背景：DeepSeek 返回了空回答，请重试。") isEqual:@"Work background: DeepSeek returned an empty answer. Please retry."], "Section error headings and messages both translate");
        Require([CGDLocalizedMessage(@"作品背景已更新。") isEqual:@"Work background updated."], "Late section status translates its section name");
        Require([CGDLocalizedMessage(@"生成失败，请重试。 原内容已保留。") isEqual:@"Generation failed. Please retry. The previous content has been kept."], "Failure and retained-content suffix translate together");
        Require([CGDLocalizedMessage(@"artistTitle：方法缺失或签名不符") isEqual:@"artistTitle: method missing or signature mismatch"], "Diagnostics retain method identifiers");
        Require([CGDLocalizedMessage(@"Setting title not found 123") isEqual:@"Setting title not found 123"], "Unknown messages pass through unchanged");
        NSString *longText = [@"a" stringByPaddingToLength:33000 withString:@"a" startingAtIndex:0];
        Require(CGDLocalizedMessage(longText) == longText, "Oversized messages do not run template matching");

        NSDictionary *guide = @{@"translated_title": @"关闭", @"title_breakdown": @[], @"background": @"作品背景", @"performer_info": @"设置", @"listening_tips": @[]};
        NSDictionary *event = @{@"guide": guide, @"availableModules": @[@"translation", @"background", @"performers"]};
        NSString *export = CGDGuidePlainText(track, event);
        Require([export hasPrefix:@"设置\n\n作品背景\n\n导赏"], "Track metadata survives unchanged even when matching UI keys");
        Require([export containsString:@"Work background\n作品背景"] && [export containsString:@"\n关闭"], "Export changes section headings only, never AI content");
        NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ainote-language-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *trackKey = [@"1" stringByPaddingToLength:64 withString:@"1" startingAtIndex:0];
        NSString *moduleKey = [@"2" stringByPaddingToLength:64 withString:@"2" startingAtIndex:0];
        NSDictionary *entry = @{@"key": moduleKey, @"value": @{@"background": @"作品背景"}, @"generatedAt": @(NSDate.date.timeIntervalSince1970)};
        CGDGuideModuleCache *cache = [[CGDGuideModuleCache alloc] initWithPath:cachePath];
        Require([cache storeEntries:@{@"background": entry} forTrack:trackKey] == nil, "Cache fixture writes successfully");
        NSData *cacheBytes = [NSData dataWithContentsOfFile:cachePath];
        Require(CGDSaveInterfaceLanguage(@"zh-Hans") && notifications == 2, "Switching back to Chinese notifies once");
        Require([CGDLocalizedMessage(http) isEqual:CGDGuideHTTPError(418)], "Existing English status can switch back to Chinese");
        Require([CGDLocalizedMessage(@"Settings") isEqual:@"设置"], "Existing English static UI status switches back");
        Require([[NSData dataWithContentsOfFile:cachePath] isEqual:cacheBytes], "Switching UI does not rewrite or clear cache files");
        CGDGuideModuleCache *reopened = [[CGDGuideModuleCache alloc] initWithPath:cachePath];
        Require([[[[reopened entryForTrack:trackKey module:@"background" key:moduleKey] objectForKey:@"value"] objectForKey:@"background"] isEqual:@"作品背景"], "Cached AI content survives switching and reopening storage");
        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:NULL];
        CGDSaveInterfaceLanguage(@"en"); [defaults synchronize];
        NSTask *child = [[NSTask alloc] init];
        [child setLaunchPath:[NSString stringWithUTF8String:argv[0]]]; [child setArguments:@[@"--check-persisted"]];
        [child launch]; [child waitUntilExit];
        Require(child.terminationStatus == 0, "UI and guide language preferences survive a fresh process");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        if (previousUI) [defaults setObject:previousUI forKey:uiKey]; else [defaults removeObjectForKey:uiKey];
        if (previousGuide) [defaults setObject:previousGuide forKey:guideKey]; else [defaults removeObjectForKey:guideKey];
        [defaults synchronize];
        printf("PASS: %u interface-language assertions (preferences, messages, cache, request isolation and process restart).\n", checks);
    }
    return 0;
}
