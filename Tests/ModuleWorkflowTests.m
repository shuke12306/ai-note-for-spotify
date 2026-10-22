#import "CGDGuideData.h"
#import "CGDGuideModuleCache.h"
#import "CGDGuideLibrary.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int checks;
static void Require(BOOL value, const char *message) { checks++; if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
static NSString *Key(NSUInteger value) { return [NSString stringWithFormat:@"%064lu", (unsigned long)value]; }
static NSData *Envelope(id value) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
    return [NSJSONSerialization dataWithJSONObject:@{@"choices": @[@{@"finish_reason": @"stop", @"message": @{@"content": [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]}}]} options:0 error:NULL];
}
static NSDictionary *Guide(NSString *title) {
    return @{@"translated_title": title, @"title_breakdown": @[@{@"term": @"BWV", @"explanation": @"作品目录"}],
        @"background": @"旧背景", @"performer_info": @"演奏者介绍", @"listening_tips": @[@"留意旋律交接"]};
}
static NSDictionary *Entry(NSDictionary *guide, NSString *module, NSUInteger key) {
    return @{@"key": Key(key), @"generatedAt": @(NSDate.date.timeIntervalSince1970), @"value": CGDValidateGuideModule(guide, module)};
}

static void CheckQualityFixtures(void) {
    // Metadata fixtures, not model-generated factual claims. Guards assert
    // catalog/movement preservation; human listening/factual review is separate.
    NSArray *titles = @[
        @"Goldberg Variations, BWV 988: I. Aria",
        @"Goldberg Variations, BWV 988: II. Variation 1",
        @"Piano Concerto No. 21 in C Major, K. 467: II. Andante",
        @"Nocturnes, Op. 9: II. Andante in E-Flat Major",
        @"Bach, JS / Orch. Marriner: BWV 208: IX. Schafe können sicher weiden",
        @"Symphony No. 5 in C Minor, Op. 67: I. Allegro con brio",
        @"Violin Concerto in D Minor, BWV 1043: II. Largo ma non tanto",
        @"Concerto in D Major, RV 93: II. Largo"
    ];
    for (NSString *title in titles) {
        NSDictionary *track = @{@"title": title};
        NSString *failure = nil;
        NSDictionary *good = CGDParseGuideModuleResponse(Envelope(@{@"translated_title": title}), 200, track, @"translation", &failure);
        Require(good && !failure && ![good objectForKey:@"title_original"], "Quality fixture preserves complete source markers");
        NSDictionary *bad = CGDParseGuideModuleResponse(Envelope(@{@"translated_title": @"优美的古典音乐"}), 200, track, @"translation", &failure);
        Require([[bad objectForKey:@"translated_title"] isEqual:title] && [[bad objectForKey:@"title_original"] boolValue], "Omitted work/movement markers fall back to original title");
    }
    NSDictionary *first = @{@"title": [titles objectAtIndex:0], @"artist": @"Johann Sebastian Bach", @"artists": @[@"Johann Sebastian Bach", @"Glenn Gould"]};
    NSDictionary *other = @{@"title": [titles objectAtIndex:0], @"artist": @"Johann Sebastian Bach", @"artists": @[@"Johann Sebastian Bach", @"András Schiff"]};
    for (NSString *module in CGDPromptModuleIDs()) Require(![CGDGuideModuleIdentity(first, @"m", @"中文", nil, module) isEqual:CGDGuideModuleIdentity(other, @"m", @"中文", nil, module)], "Two recordings never share a performer-sensitive module identity");
}

int main(void) {
    @autoreleasepool {
        NSDictionary *track = @{@"title": @"Suite in D Major, BWV 1068: II. Air", @"artist": @"Bach; Orchestra", @"album": @"Fixture", @"trackID": @"recording-1", @"artists": @[@"Bach", @"Orchestra"], @"notes": @"private diagnostic"};
        NSDictionary *guide = Guide([track objectForKey:@"title"]);
        NSDictionary *prompts = CGDNormalizeGuidePrompts(nil);
        NSDictionary *oldPrompts = CGDGuidePromptsBefore050(prompts);
        Require([[oldPrompts objectForKey:@"translation"] isEqual:[prompts objectForKey:@"translation"]] &&
            [[oldPrompts objectForKey:@"breakdown"] isEqual:[prompts objectForKey:@"breakdown"]], "Upgrade can reuse unchanged legacy modules after exact full-key verification");
        for (NSString *module in @[@"background", @"performers", @"listening"]) Require(![[oldPrompts objectForKey:module] isEqual:[prompts objectForKey:module]], "Improved default prompt does not silently reuse old content");
        NSArray *selected = @[@"translation", @"listening"];
        NSDictionary *body = CGDGuideRequestBodyForModules(track, @"model", @"English", prompts, selected);
        NSString *system = [[[body objectForKey:@"messages"] firstObject] objectForKey:@"content"];
        NSRange start = [system rangeOfString:@"本次只生成以下模块，严格遵守写作要求：\n"];
        NSRange end = [system rangeOfString:@"\n只输出这些键，结构如下"];
        NSString *writing = [system substringWithRange:NSMakeRange(NSMaxRange(start), end.location - NSMaxRange(start))];
        NSArray *instructions = [NSJSONSerialization JSONObjectWithData:[writing dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require(instructions.count == 2, "Two enabled modules share one request");
        Require([[[instructions firstObject] objectForKey:@"module"] isEqual:@"translation"] && [[[instructions lastObject] objectForKey:@"module"] isEqual:@"listening"], "Disabled module instructions are excluded");
        Require(CGDGuideRequestBodyForModules(track, @"m", @"English", prompts, @[]) == nil, "All modules off cannot create a network request");
        Require([CGDNormalizeRequestedModules(@[@"original", @"listening", @"listening", @"unknown"]) isEqual:@[@"listening"]], "Only unique AI modules accepted");
        NSMutableDictionary *changed = [prompts mutableCopy]; [changed setObject:@"A new performer prompt" forKey:@"performers"];
        Require([[CGDGuidePromptsBefore050(changed) objectForKey:@"performers"] isEqual:@"A new performer prompt"], "Legacy candidate preserves custom prompts");
        for (NSString *module in CGDPromptModuleIDs()) {
            BOOL same = [CGDGuideModuleIdentity(track, @"m", @"English", prompts, module) isEqual:CGDGuideModuleIdentity(track, @"m", @"English", changed, module)];
            Require(same != [module isEqual:@"performers"], "Editing one prompt invalidates only its own module");
            Require(![CGDGuideModuleIdentity(track, @"m", @"English", prompts, module) isEqual:CGDGuideModuleIdentity(track, @"m", @"日本語", prompts, module)], "Output languages remain isolated per module");
        }
        NSDictionary *errors = nil;
        NSMutableDictionary *response = [guide mutableCopy]; [response setObject:[NSNull null] forKey:@"performer_info"];
        NSDictionary *partials = CGDParseGuideModulesResponse(Envelope(response), 200, track, CGDPromptModuleIDs(), &errors);
        Require(partials.count == 4 && errors.count == 1 && [errors objectForKey:@"performers"], "One malformed module does not discard four valid modules");
        NSDictionary *empty = CGDParseGuideModulesResponse(Envelope(@{@"performer_info": @""}), 200, track, @[@"performers"], &errors);
        Require([empty objectForKey:@"performers"] != nil && !errors.count, "Intentional empty result counts as generated");
        NSDictionary *restricted = CGDParseGuideModulesResponse(Envelope(guide), 200, track, selected, &errors);
        Require(restricted.count == 2 && ![restricted objectForKey:@"background"], "Unexpected extra model output is ignored");
        CGDParseGuideModulesResponse([NSData data], 200, track, selected, &errors);
        Require(errors.count == 2, "Empty transport response fails each requested module");
        CGDParseGuideModulesResponse(Envelope(guide), 401, track, selected, &errors);
        Require(errors.count == 2, "Authentication failure never yields fake cached content");

        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"classicalguide-workflow-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *path = [folder stringByAppendingPathComponent:@"modules.json"];
        NSString *libraryPath = [folder stringByAppendingPathComponent:@"favorites.json"];
        CGDGuideModuleCache *cache = [[CGDGuideModuleCache alloc] initWithPath:path];
        NSDictionary *firstEntries = @{@"translation": Entry(guide, @"translation", 1), @"listening": Entry(guide, @"listening", 2)};
        Require([cache storeEntries:firstEntries forTrack:Key(9)] == nil, "Selected modules persist atomically");
        cache = [[CGDGuideModuleCache alloc] initWithPath:path];
        Require([cache entryForTrack:Key(9) module:@"translation" key:Key(1)] != nil && [cache entryForTrack:Key(9) module:@"performers" key:Key(3)] == nil, "Reopening restores generated modules without inventing missing ones");
        NSMutableDictionary *cached = [firstEntries mutableCopy];
        NSDictionary *plan = CGDPlanGuideModules(selected, cached, [NSSet set], NO);
        Require([[plan objectForKey:@"generate"] count] == 0, "Reopening same enabled modules makes no API call");
        plan = CGDPlanGuideModules(@[@"translation", @"listening", @"performers"], cached, [NSSet set], NO);
        Require([[plan objectForKey:@"generate"] isEqual:@[@"performers"]], "Enabling a new module requests only that module");
        plan = CGDPlanGuideModules(selected, cached, [NSSet setWithObject:@"translation"], YES);
        Require([[plan objectForKey:@"join"] isEqual:@[@"translation"]] && [[plan objectForKey:@"generate"] isEqual:@[@"listening"]], "Force during in-flight request joins rather than double billing");
        plan = CGDPlanGuideModulesRetrying(selected, cached, [NSSet set], @[@"translation"], NO);
        Require([[plan objectForKey:@"generate"] isEqual:@[@"translation"]] && [[plan objectForKey:@"reuse"] isEqual:@[@"listening"]], "Failed refresh retries despite old cached fallback without regenerating successful modules");
        plan = CGDPlanGuideModulesRetrying(selected, cached, [NSSet setWithObject:@"translation"], @[@"translation"], NO);
        Require([[plan objectForKey:@"join"] isEqual:@[@"translation"]] && ![[plan objectForKey:@"generate"] count], "Failed refresh joins an already running retry");
        plan = CGDPlanGuideModulesRetrying(@[], cached, [NSSet set], selected, YES);
        Require(![[plan objectForKey:@"generate"] count] && ![[plan objectForKey:@"join"] count], "Disabled modules never generate even on force or retry");
        Require([cache storeEntries:@{@"performers": Entry(guide, @"performers", 3)} forTrack:Key(9)] == nil && [cache entryForTrack:Key(9) module:@"translation" key:Key(1)], "Disjoint batch completion preserves previous modules");
        Require([cache storeEntries:@{@"performers": Entry(guide, @"performers", 4)} forTrack:Key(9)] == nil && ![cache entryForTrack:Key(9) module:@"performers" key:Key(3)] && [cache entryForTrack:Key(9) module:@"listening" key:Key(2)], "Changed prompt replaces only that module slot");
        Require([cache storeEntries:@{@"performers": @{@"key": Key(5), @"generatedAt": @1, @"value": @{@"performer_info": [NSNull null]}}} forTrack:Key(9)] != nil && [cache entryForTrack:Key(9) module:@"performers" key:Key(4)], "Bad refresh cannot erase usable content");
        for (NSUInteger i = 10; i < 112; i++) @autoreleasepool { [cache storeEntries:firstEntries forTrack:Key(i)]; }
        NSDictionary *disk = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
        Require([[disk objectForKey:@"entries"] count] == 100 && ![cache entryForTrack:Key(9) module:@"translation" key:Key(1)], "Module cache remains bounded by 100 track groups");

        NSMutableDictionary *keys = [NSMutableDictionary dictionary], *dates = [NSMutableDictionary dictionary];
        for (NSString *module in CGDPromptModuleIDs()) { [keys setObject:Key(1) forKey:module]; [dates setObject:@1 forKey:module]; }
        NSDictionary *previous = @{@"guide": guide, @"trackIdentity": CGDGuideTrackIdentity(track, @"m", @"中文"), @"model": @"m", @"language": @"中文",
            @"prompts": prompts, @"moduleKeys": keys, @"moduleDates": dates, @"availableModules": CGDPromptModuleIDs()};
        NSMutableDictionary *current = [previous mutableCopy];
        NSMutableDictionary *newGuide = [guide mutableCopy]; [newGuide setObject:@"新背景" forKey:@"background"]; [newGuide setObject:@"新演奏者" forKey:@"performer_info"];
        [current setObject:newGuide forKey:@"guide"];
        NSDictionary *restored = CGDRestoreGuideModuleEvent(@"background", previous, current);
        Require([[[restored objectForKey:@"guide"] objectForKey:@"background"] isEqual:@"旧背景"] && [[[restored objectForKey:@"guide"] objectForKey:@"performer_info"] isEqual:@"新演奏者"], "Undo changes only selected module, retaining other updates");
        [current setObject:[NSData data] forKey:@"trackIdentity"];
        Require(CGDRestoreGuideModuleEvent(@"background", previous, current) == nil, "Undo cannot mix tracks");

        CGDGuideLibrary *library = [[CGDGuideLibrary alloc] initWithPath:libraryPath];
        Require([library saveSnapshot:track event:previous] == nil, "Favorite saves valid guide");
        library = [[CGDGuideLibrary alloc] initWithPath:libraryPath];
        Require(library.items.count == 1 && [library saveSnapshot:track event:previous] == nil && library.items.count == 1, "Favorites persist and saving again updates instead of duplicating");
        NSDictionary *favorite = library.items.firstObject;
        Require(![[favorite objectForKey:@"event"] objectForKey:@"prompts"] && ![[favorite objectForKey:@"snapshot"] objectForKey:@"notes"], "Favorites exclude custom prompts and diagnostics");
        [cache clear];
        Require([NSFileManager.defaultManager fileExistsAtPath:libraryPath] && library.items.count == 1, "Clearing cache leaves favorites intact");
        NSString *plain = CGDGuidePlainText([favorite objectForKey:@"snapshot"], [favorite objectForKey:@"event"]);
        Require([plain rangeOfString:@"旧背景"].location != NSNotFound && [plain rangeOfString:@"private diagnostic"].location == NSNotFound && [plain rangeOfString:@"recording-1"].location == NSNotFound, "Copied guide contains content without internal metadata");
        Require([library removeItem:[favorite objectForKey:@"id"]] == nil && !library.items.count, "Explicit favorite removal persists");
        library = [[CGDGuideLibrary alloc] initWithPath:libraryPath];
        Require(!library.items.count && !library.loadError, "Favorite deletion survives reopening");
        NSMutableArray *full = [NSMutableArray array];
        for (NSUInteger i = 0; i < 200; i++) {
            NSMutableDictionary *item = [favorite mutableCopy], *snapshot = [[favorite objectForKey:@"snapshot"] mutableCopy];
            [item setObject:[NSString stringWithFormat:@"item-%lu", (unsigned long)i] forKey:@"id"];
            [snapshot setObject:[NSString stringWithFormat:@"recording-%lu", (unsigned long)i + 10] forKey:@"trackID"];
            [item setObject:snapshot forKey:@"snapshot"]; [full addObject:item];
        }
        NSData *fullData = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"items": full} options:0 error:NULL];
        [fullData writeToFile:libraryPath atomically:YES];
        library = [[CGDGuideLibrary alloc] initWithPath:libraryPath];
        Require(library.items.count == 200 && [library saveSnapshot:track event:previous] != nil && library.items.count == 200 &&
            [[NSData dataWithContentsOfFile:libraryPath] isEqual:fullData], "Full favorites refuse additions instead of silently evicting saved work");
        NSString *blocked = [folder stringByAppendingPathComponent:@"blocked"];
        [@"keep" writeToFile:blocked atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        CGDGuideLibrary *unwritable = [[CGDGuideLibrary alloc] initWithPath:[blocked stringByAppendingPathComponent:@"favorites.json"]];
        Require([unwritable saveSnapshot:track event:previous] != nil && !unwritable.items.count, "Failed disk write does not report an unsaved favorite as saved");
        [@"[]" writeToFile:libraryPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        library = [[CGDGuideLibrary alloc] initWithPath:libraryPath];
        Require(library.loadError && [library saveSnapshot:track event:previous] != nil && [[NSString stringWithContentsOfFile:libraryPath encoding:NSUTF8StringEncoding error:NULL] isEqual:@"[]"], "Corrupt durable library is preserved instead of silently overwritten");
        [@"[]" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        cache = [[CGDGuideModuleCache alloc] initWithPath:path];
        Require(![cache entryForTrack:Key(9) module:@"translation" key:Key(1)] && [cache storeEntries:firstEntries forTrack:Key(9)] == nil, "Disposable corrupt cache can safely rebuild");
        CheckQualityFixtures();
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        printf("PASS: %u module workflow, favorites, undo and quality-fixture assertions (no network).\n", checks);
    }
    return 0;
}
