#import "CGDGuideData.h"
#import "CGDGuideCache.h"
#include <stdio.h>
#include <stdlib.h>

static NSDictionary *Request(NSDictionary *snapshot, NSString *model) { return CGDGuideRequestBody(snapshot, model, @"简体中文"); }
static NSData *Identity(NSDictionary *snapshot, NSString *model) { return CGDGuideIdentity(snapshot, model, @"简体中文"); }
static unsigned int checks;
static void Require(BOOL condition, const char *label) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}
static NSDictionary *Guide(NSString *title) {
    return @{@"translated_title": title, @"title_breakdown": @[@{@"term": @"BWV", @"explanation": @"巴赫作品目录编号"}],
        @"background": @"背景测试内容。", @"listening_tips": @[@"留意旋律"], @"performer_info": @"测试乐团介绍；结合当前作品，留意各声部之间的旋律交接。"};
}
static NSData *Envelope(id content, NSString *finish) {
    return [NSJSONSerialization dataWithJSONObject:@{@"choices": @[@{@"finish_reason": finish,
        @"message": @{@"content": content}}]} options:0 error:NULL];
}
static NSString *JSON(id value) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL] encoding:NSUTF8StringEncoding];
}
static NSString *CacheKey(NSUInteger n) { return [NSString stringWithFormat:@"%064lu", (unsigned long)n]; }

static void CheckModules(NSDictionary *track, NSDictionary *good) {
    NSString *preference = @"CGDClassicalGuide.ModulePrompts";
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id prior = [[defaults objectForKey:preference] copy];
    [defaults removeObjectForKey:preference];
    NSDictionary *initial = CGDLoadGuidePrompts();
    Require(initial.count == 5, "Five editable prompt modules load without prior settings");
    NSMutableDictionary *draft = [initial mutableCopy];
    NSString *custom = @"只写两句，结合当前乐章。\nKeep names; quote \"solo\". 日本語🎻";
    for (NSString *module in CGDPromptModuleIDs()) {
        Require(CGDSaveModulePrompt(module, custom) == nil && [[CGDLoadGuidePrompts() objectForKey:module] isEqual:custom], "Each module saves multilingual multiline prompt text");
        CGDResetModulePrompt(module);
        Require([CGDLoadGuidePrompts() isEqual:initial], "Reset restores selected module default");
        [draft setObject:custom forKey:module];
        Require(![CGDGuideIdentityWithPrompts(track, @"model", @"English", initial) isEqual:CGDGuideIdentityWithPrompts(track, @"model", @"English", draft)], "Every module prompt affects cache identity");
        [draft setObject:[initial objectForKey:module] forKey:module];
    }
    Require(CGDSaveModulePrompt(@"performers", custom) == nil, "Save custom performer prompt");
    NSDictionary *saved = CGDLoadGuidePrompts();
    for (id invalid in @[@"", @"  \n", @42, [NSNull null], [@"x" stringByPaddingToLength:CGDGuidePromptLimit + 1 withString:@"x" startingAtIndex:0]]) {
        Require(CGDSaveModulePrompt(@"performers", invalid) != nil && [CGDLoadGuidePrompts() isEqual:saved], "Invalid edits do not overwrite saved prompts");
    }
    Require(CGDSaveModulePrompt(@"unknown", custom) != nil, "Unknown module cannot create arbitrary preference keys");
    CGDResetModulePrompt(@"background");
    Require([CGDLoadGuidePrompts() isEqual:saved], "Reset of one module preserves other custom instructions");
    for (id corrupt in @[@42, @[], @{@"performers": @42}, @{@"performers": @"", @"unexpected": @"secret"}]) {
        [defaults setObject:corrupt forKey:preference];
        Require([CGDLoadGuidePrompts() isEqual:initial], "Corrupt preferences fall back to bounded known defaults");
    }
    NSMutableString *mutableText = [NSMutableString stringWithString:custom];
    NSDictionary *captured = CGDNormalizeGuidePrompts(@{@"performers": mutableText});
    [mutableText appendString:@" changed later"];
    Require([[captured objectForKey:@"performers"] isEqual:custom], "Captured prompt cannot change during an in-flight request");
    [draft setObject:@"SPECIAL performer instructions" forKey:@"performers"];
    [draft setObject:@"UNRELATED background instructions" forKey:@"background"];
    NSDictionary *changedGuide = @{@"translated_title": [track objectForKey:@"title"],
        @"title_breakdown": @[@{@"term": @"BWV", @"explanation": @"new explanation"}],
        @"background": @"new background", @"performer_info": @"new performer paragraph", @"listening_tips": @[@"new listening tip"]};
    for (NSString *module in CGDPromptModuleIDs()) {
        NSString *field = CGDPromptModuleField(module);
        NSDictionary *body = CGDGuideRequestBodyForModule(track, @"model", @"English", draft, module);
        NSString *system = [[[[body objectForKey:@"messages"] firstObject] objectForKey:@"content"] copy];
        NSRange start = [system rangeOfString:@"本次只生成以下模块，严格遵守写作要求：\n"];
        NSRange end = [system rangeOfString:@"\n只输出这些键，结构如下"];
        Require(start.location != NSNotFound && end.location != NSNotFound, "Module request contains isolated instruction payload");
        NSString *instructionJSON = [system substringWithRange:NSMakeRange(NSMaxRange(start), end.location - NSMaxRange(start))];
        NSArray *instructions = [NSJSONSerialization JSONObjectWithData:[instructionJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require(instructions.count == 1 && [[[instructions firstObject] objectForKey:@"module"] isEqual:module] &&
            [[[instructions firstObject] objectForKey:@"instructions"] isEqual:[draft objectForKey:module]], "Only requested module prompt reaches a single-module request");
        NSMutableDictionary *response = [changedGuide mutableCopy];
        [response setObject:@(YES) forKey:@"title_original"];
        NSString *failure = nil;
        NSDictionary *partial = CGDParseGuideModuleResponse(Envelope(JSON(response), @"stop"), 200, track, module, &failure);
        Require(partial.count == 1 && [[partial objectForKey:field] isEqual:[changedGuide objectForKey:field]] && !failure, "Unexpected model fields and forged marker cannot overwrite other modules");
        NSDictionary *merged = CGDMergeGuideModule(good, partial, module);
        for (NSString *other in CGDPromptModuleIDs()) {
            NSString *otherField = CGDPromptModuleField(other);
            Require([[merged objectForKey:otherField] isEqual:[otherField isEqual:field] ? [partial objectForKey:field] : [good objectForKey:otherField]], "Merge replaces exactly one module and retains every other module");
        }
        [response removeObjectForKey:field];
        Require(CGDParseGuideModuleResponse(Envelope(JSON(response), @"stop"), 200, track, module, &failure) == nil, "Missing requested field is not accepted as success");
        [response setObject:[NSNull null] forKey:field];
        Require(CGDParseGuideModuleResponse(Envelope(JSON(response), @"stop"), 200, track, module, &failure) == nil, "Null requested field rejected");
        Require(CGDParseGuideModuleResponse(Envelope(JSON(changedGuide), @"length"), 200, track, module, &failure) == nil, "Single-module truncation preserves previous answer");
        Require(CGDMergeGuideModule(good, @{}, module) == nil, "Failed module merge cannot erase old text");
    }
    NSString *failure = nil;
    NSDictionary *empty = CGDParseGuideModuleResponse(Envelope(JSON(@{@"performer_info": @""}), @"stop"), 200, track, @"performers", &failure);
    Require(empty != nil && [[CGDMergeGuideModule(good, empty, @"performers") objectForKey:@"performer_info"] isEqual:@""], "Intentional empty module can be merged and hidden");
    NSDictionary *guarded = CGDParseGuideModuleResponse(Envelope(JSON(@{@"translated_title": @"Air"}), @"stop"), 200, track, @"translation", &failure);
    Require([[guarded objectForKey:@"translated_title"] isEqual:[track objectForKey:@"title"]] && [[guarded objectForKey:@"title_original"] boolValue], "Single-module title retains catalog movement and key safeguards");
    NSDictionary *marked = CGDMergeGuideModule(good, guarded, @"translation");
    NSDictionary *repaired = CGDMergeGuideModule(marked, @{@"translated_title": [good objectForKey:@"translated_title"]}, @"translation");
    Require([repaired objectForKey:@"title_original"] == nil, "Successful title regeneration clears stale fallback marker");
    Require([[CGDMergeGuideModule(marked, empty, @"performers") objectForKey:@"title_original"] boolValue], "Other module updates preserve title fallback marker");
    Require(CGDGuideRequestBodyForModule(track, @"model", @"English", draft, @"unknown") == nil &&
        CGDParseGuideModuleResponse(Envelope(JSON(good), @"stop"), 200, track, @"unknown", &failure) == nil &&
        CGDMergeGuideModule(good, empty, @"unknown") == nil, "Unknown modules rejected throughout request parse merge");
    if (prior) [defaults setObject:prior forKey:preference]; else [defaults removeObjectForKey:preference];
}

int main(void) {
    @autoreleasepool {
        NSDictionary *track = @{@"title": @"Orchestral Suite No. 3 in D Major, BWV 1068: II. Air",
            @"artist": @"artist fixture", @"album": @"album fixture", @"trackID": @"opaque-id", @"notes": @[@"private diagnostic fixture"]};
        NSDictionary *body = Request(track, @"deepseek-flash");
        Require([[body objectForKey:@"model"] isEqual:@"deepseek-flash"] && ![[body objectForKey:@"stream"] boolValue], "Configured model and nonstreaming body");
        Require([[[body objectForKey:@"thinking"] objectForKey:@"type"] isEqual:@"disabled"], "Thinking explicitly disabled");
        Require([[[body objectForKey:@"response_format"] objectForKey:@"type"] isEqual:@"json_object"], "JSON output requested");
        NSArray *messages = [body objectForKey:@"messages"];
        NSString *user = [[messages lastObject] objectForKey:@"content"];
        id payload = [NSJSONSerialization JSONObjectWithData:[user dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require([payload count] == 3 && [[payload objectForKey:@"title"] isEqual:[track objectForKey:@"title"]], "Only title, artist, album go to API");
        Require([JSON(body) rangeOfString:@"opaque-id"].location == NSNotFound && [JSON(body) rangeOfString:@"private diagnostic"].location == NSNotFound, "ID and diagnosis never leave phone");
        NSMutableDictionary *multiTrack = [track mutableCopy];
        NSArray *artistNames = @[@"Johann Sebastian Bach", @"Sir Neville Marriner", @"Choir of King's College, Cambridge"];
        [multiTrack setObject:artistNames forKey:@"artists"];
        NSDictionary *multiBody = Request(multiTrack, @"deepseek-flash");
        NSString *multiUser = [[[multiBody objectForKey:@"messages"] lastObject] objectForKey:@"content"];
        NSDictionary *multiPayload = [NSJSONSerialization JSONObjectWithData:[multiUser dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require([[multiPayload objectForKey:@"artists"] isEqual:artistNames], "all track artist names reach AI with commas inside names preserved");
        Require([multiPayload count] == 4 && [multiPayload objectForKey:@"trackID"] == nil && [multiPayload objectForKey:@"notes"] == nil, "expanded request contains only track text");
        Require(![Identity(track, @"model") isEqual:Identity(multiTrack, @"model")], "full artists invalidate old primary-artist cache");
        NSData *multiIdentity = Identity(multiTrack, @"model");
        [multiTrack setObject:@[@"Johann Sebastian Bach", @"Another performer"] forKey:@"artists"];
        Require(![multiIdentity isEqual:Identity(multiTrack, @"model")], "performer changes invalidate cache even with same ID and display title");
        for (id invalid in @[@"not an array", @[@42], @[[NSNull null]], @[@" "],
            @[[ @"x" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0]],
            @[[ @"x" stringByPaddingToLength:5000 withString:@"x" startingAtIndex:0], [ @"y" stringByPaddingToLength:5000 withString:@"y" startingAtIndex:0]]]) {
            [multiTrack setObject:invalid forKey:@"artists"];
            NSString *content = [[[[Request(multiTrack, @"model") objectForKey:@"messages"] lastObject] objectForKey:@"content"] copy];
            NSDictionary *safe = [NSJSONSerialization JSONObjectWithData:[content dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            Require([safe objectForKey:@"artists"] == nil, "malformed or oversized artist arrays excluded from API");
            Require([Identity(multiTrack, @"model") isEqual:Identity(track, @"model")], "request and cache normalize malformed artists consistently");
        }
        Require(Request(@{}, @"deepseek-flash") == nil && Request(@{@"title": [NSNull null]}, @"model") == nil, "Missing/invalid titles block generation");
        NSDictionary *minimal = Request(@{@"title": @"Solo"}, @"model");
        id minimalPayload = [NSJSONSerialization JSONObjectWithData:[[[[minimal objectForKey:@"messages"] lastObject] objectForKey:@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Require([minimalPayload count] == 1, "Missing optional fields stay absent");
        NSData *identity = Identity(track, @"model");
        Require(![identity isEqual:Identity(track, @"other-model")], "Model changes invalidate cache identity");
        for (NSString *language in @[@"英语 (English)", @"法语 (Français)", @"繁体中文", @"العربية"]) {
            Require(![identity isEqual:CGDGuideIdentity(track, @"model", language)], "Each output language has a separate cache identity");
            NSDictionary *localized = CGDGuideRequestBody(track, @"model", language);
            NSString *system = [[[localized objectForKey:@"messages"] firstObject] objectForKey:@"content"];
            NSRange settingStart = [system rangeOfString:@"本次语言设置（JSON）："];
            NSString *setting = settingStart.location == NSNotFound ? @"" : [system substringFromIndex:NSMaxRange(settingStart)];
            NSDictionary *languageJSON = [NSJSONSerialization JSONObjectWithData:[setting dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            Require([system isEqual:CGDGuideSystemPrompt(language)] && [[languageJSON objectForKey:@"output_language"] isEqual:language], "Selected preset/custom language reaches exact production system prompt including Unicode JSON escaping");
        }
        Require(CGDGuideRequestBody(track, @"model", @"") == nil, "Invalid empty language blocks malformed request");
        Require([CGDGuideSystemPrompt(@"简体中文") rangeOfString:@"performer_info"].location != NSNotFound &&
            [CGDGuideSystemPrompt(@"简体中文") rangeOfString:@"uncertainties"].location == NSNotFound, "Prompt requests performer information without uncertainty schema");
        for (NSString *key in @[@"title", @"artist", @"album", @"trackID"]) {
            NSMutableDictionary *other = [track mutableCopy];
            [other setObject:@"different recording" forKey:key];
            Require(![identity isEqual:Identity(other, @"model")], "Track metadata/recording changes invalidate identity");
        }
        Require([[[NSString alloc] initWithData:identity encoding:NSUTF8StringEncoding] rangeOfString:CGDPromptVersion].location != NSNotFound, "Prompt version in cache identity");
        Require(![Identity(@{@"title": @"a|b", @"artist": @"c"}, @"m") isEqual:Identity(@{@"title": @"a", @"artist": @"b|c"}, @"m")], "Delimiter collisions impossible");

        NSString *translated = @"D 大调第三管弦乐组曲，BWV 1068：II. 咏叹调";
        NSDictionary *good = Guide(translated);
        Require(CGDValidateGuide(good) != nil, "Valid complete schema accepted");
        CheckModules(track, good);
        NSMutableDictionary *omitted = [good mutableCopy];
        [omitted setObject:@"" forKey:@"performer_info"];
        [omitted setObject:@" \n " forKey:@"background"];
        [omitted setObject:@[] forKey:@"title_breakdown"];
        [omitted setObject:@[] forKey:@"listening_tips"];
        NSDictionary *sparse = CGDValidateGuide(omitted);
        Require(sparse != nil && [[sparse objectForKey:@"performer_info"] isEqual:@""], "No reliable performer content can be omitted without a disclaimer");
        Require([[sparse objectForKey:@"background"] isEqual:@""], "Whitespace-only paragraphs normalize to empty for hidden cards");
        Require([[sparse objectForKey:@"translated_title"] isEqual:translated] && [[sparse objectForKey:@"title_breakdown"] count] == 0 && [[sparse objectForKey:@"listening_tips"] count] == 0, "Sparse guide preserves title and empty arrays");
        for (NSString *key in @[@"background", @"performer_info"]) {
            for (id invalid in @[@42, @[], @{}, [NSNull null], [@"x" stringByPaddingToLength:6001 withString:@"x" startingAtIndex:0]]) {
                NSMutableDictionary *malformed = [sparse mutableCopy];
                [malformed setObject:invalid forKey:key];
                Require(CGDValidateGuide(malformed) == nil, "Optional paragraphs still reject nonstrings and oversized text");
            }
        }
        NSMutableDictionary *emptyTitle = [sparse mutableCopy];
        [emptyTitle setObject:@"" forKey:@"translated_title"];
        Require(CGDValidateGuide(emptyTitle) == nil, "Omitting optional paragraphs does not permit an empty translated title");
        NSMutableDictionary *oldSchema = [good mutableCopy];
        [oldSchema removeObjectForKey:@"performer_info"];
        [oldSchema setObject:@[@"old uncertainty fixture"] forKey:@"uncertainties"];
        Require(CGDValidateGuide(oldSchema) == nil, "Previous cache schema cannot masquerade as new performer content");
        NSMutableDictionary *extra = [good mutableCopy];
        [extra setObject:@[@"unwanted uncertainty fixture"] forKey:@"uncertainties"];
        Require([CGDValidateGuide(extra) objectForKey:@"uncertainties"] == nil, "Unexpected uncertainty field stripped from model result");
        for (NSString *key in good) {
            NSMutableDictionary *bad = [good mutableCopy];
            [bad removeObjectForKey:key];
            Require(CGDValidateGuide(bad) == nil, "Missing required field rejected");
            [bad setObject:[NSNull null] forKey:key];
            Require(CGDValidateGuide(bad) == nil, "Null required field rejected");
        }
        NSMutableDictionary *bad = [good mutableCopy];
        [bad setObject:@[@{@"term": @"BWV"}] forKey:@"title_breakdown"];
        Require(CGDValidateGuide(bad) == nil, "Broken term object rejected");
        [bad setObject:@[@{@"term": @"BWV", @"explanation": @"编号"}] forKey:@"title_breakdown"];
        [bad setObject:@[@42] forKey:@"listening_tips"];
        Require(CGDValidateGuide(bad) == nil, "Nonstring list content rejected");
        [bad setObject:@[] forKey:@"listening_tips"];

        Require(CGDValidateGuide(bad) != nil, "Empty optional-content arrays supported");
        [bad setObject:[@"x" stringByPaddingToLength:6001 withString:@"x" startingAtIndex:0] forKey:@"background"];
        Require(CGDValidateGuide(bad) == nil, "Oversized fields rejected");

        NSString *error = nil;
        NSDictionary *parsed = CGDParseGuideResponse(Envelope(JSON(good), @"stop"), 200, track, &error);
        Require([[parsed objectForKey:@"translated_title"] isEqual:translated] && !error, "Full valid API envelope parsed");
        NSDictionary *parsedSparse = CGDParseGuideResponse(Envelope(JSON(omitted), @"stop"), 200, track, &error);
        Require([parsedSparse isEqual:sparse] && !error, "A complete JSON response can deliberately omit unreliable paragraphs");
        Require(CGDParseGuideResponse(Envelope(JSON(omitted), @"length"), 200, track, &error) == nil, "Sparse schema does not accidentally accept truncated responses");
        [extra setObject:@(YES) forKey:@"title_original"];
        parsed = CGDParseGuideResponse(Envelope(JSON(extra), @"stop"), 200, track, &error);
        Require([parsed objectForKey:@"title_original"] == nil, "Model cannot set client preservation marker");
        Require(CGDParseGuideResponse(Envelope(JSON(good), @"length"), 200, track, &error) == nil && [error rangeOfString:@"截断"].location != NSNotFound, "Truncated output never displayed");
        Require(CGDParseGuideResponse(Envelope(@"  ", @"stop"), 200, track, &error) == nil && [error rangeOfString:@"空回答"].location != NSNotFound, "Empty JSON-mode response offers retry");
        Require(CGDParseGuideResponse(Envelope(@"{\"broken\":", @"stop"), 200, track, &error) == nil, "Malformed inner JSON rejected");
        Require(CGDParseGuideResponse([@"not json" dataUsingEncoding:NSUTF8StringEncoding], 200, track, &error) == nil, "Malformed envelope rejected");
        for (NSString *finish in @[@"content_filter", @"tool_calls", @"aborted", @"insufficient_system_resource"]) {
            Require(CGDParseGuideResponse(Envelope(JSON(good), finish), 200, track, &error) == nil, "Incomplete response reasons rejected");
        }
        Require(CGDParseGuideResponse(Envelope([NSNull null], @"stop"), 200, track, &error) == nil, "Null content handled");
        for (NSNumber *status in @[@401, @402, @403, @404, @400, @422, @429, @500, @502, @503, @504, @418]) {
            Require(CGDParseGuideResponse([@"sensitive server error fixture" dataUsingEncoding:NSUTF8StringEncoding], [status integerValue], track, &error) == nil && error.length && [error rangeOfString:@"sensitive"].location == NSNotFound, "HTTP failure is safe, actionable, and does not echo body");
        }
        Require(CGDParseGuideResponse([NSMutableData dataWithLength:512 * 1024 + 1], 200, track, &error) == nil, "Response byte cap enforced");
        parsed = CGDParseGuideResponse(Envelope(JSON(Guide(@"咏叹调")), @"stop"), 200, track, &error);
        Require([[parsed objectForKey:@"translated_title"] isEqual:[track objectForKey:@"title"]] && [[parsed objectForKey:@"title_original"] boolValue], "Lost catalog/movement falls back to original with warning");
        for (NSString *wrong in @[@"D 大调，BWV 10688：II. 咏叹调", @"D 大调，BWV 1068：III. 咏叹调", @"D 小调，BWV 1068：II. 咏叹调"]) {
            parsed = CGDParseGuideResponse(Envelope(JSON(Guide(wrong)), @"stop"), 200, track, &error);
            Require([[parsed objectForKey:@"translated_title"] isEqual:[track objectForKey:@"title"]], "Wrong number prefix, movement or key cannot pass preservation guard");
        }
        for (NSArray *pair in @[@[@"Sonata in B-flat Major, K. 570", @"降 B 大调奏鸣曲，K. 570"],
            @[@"Prelude in F-sharp Minor, Op. 28/8", @"升 F 小调前奏曲，Op. 28/8"],
            @[@"Prelude in C Minor, BWV 847", @"C 小调前奏曲，BWV 847"]]) {
            parsed = CGDParseGuideResponse(Envelope(JSON(Guide([pair objectAtIndex:1])), @"stop"), 200, @{@"title": [pair objectAtIndex:0]}, &error);
            Require([[parsed objectForKey:@"translated_title"] isEqual:[pair objectAtIndex:1]], "Chinese key and accidental notation accepted");
        }
        for (NSString *multilingual in @[@"Suite pour orchestre en ré majeur (D Major), BWV 1068 : II. Air",
            @"管弦楽組曲 ニ長調 (D Major), BWV 1068: II. アリア",
            @"Оркестровая сюита ре мажор (D Major), BWV 1068: II. Ария",
            @"متتالية أوركسترالية (D Major), BWV 1068: II. آريا"]) {
            parsed = CGDParseGuideResponse(Envelope(JSON(Guide(multilingual)), @"stop"), 200, track, &error);
            Require([[parsed objectForKey:@"translated_title"] isEqual:multilingual] && ![parsed objectForKey:@"title_original"], "Multilingual title with source key/codes survives preservation guard");
        }
        for (NSString *title in @[@"Sonata, K. 331: III. Allegro", @"Sonata, KV 331: III. Allegro", @"Prelude, Op. 28/4: IV. Largo", @"Cantata, BWV 140: IV. Chorale"]) {
            parsed = CGDParseGuideResponse(Envelope(JSON(Guide(@"不完整曲名")), @"stop"), 200, @{@"title": title}, &error);
            Require([[parsed objectForKey:@"translated_title"] isEqual:title], "BWV/K/KV/Op and Roman movements retained on omission");
        }

        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"classicalguide-cache-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *path = [folder stringByAppendingPathComponent:@"guides.json"];
        CGDGuideCache *cache = [[CGDGuideCache alloc] initWithPath:path];
        Require([cache entryForKey:CacheKey(1)] == nil, "Cache starts empty");
        Require([cache storeGuide:sparse key:CacheKey(0) date:NSDate.date] == nil, "Cache accepts intentional empty modules");
        cache = [[CGDGuideCache alloc] initWithPath:path];
        Require([[[cache entryForKey:CacheKey(0)] objectForKey:@"guide"] isEqual:sparse], "Omitted modules survive disk cache reload without placeholder text");
        [cache clear];
        Require([cache storeGuide:good key:CacheKey(1) date:NSDate.date] == nil, "Cache writes valid result");
        Require([[[cache entryForKey:CacheKey(1)] objectForKey:@"guide"] isEqual:good], "Cache hit returns matching complete result");
        cache = [[CGDGuideCache alloc] initWithPath:path];
        Require([cache entryForKey:CacheKey(1)] != nil && [cache entryForKey:CacheKey(2)] == nil, "Cache persists and isolates identities");
        for (NSUInteger i = 2; i <= 101; i++) {
            @autoreleasepool { [cache storeGuide:good key:CacheKey(i) date:NSDate.date]; }
        }
        id disk = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
        Require([[disk objectForKey:@"entries"] count] == 100 && [cache entryForKey:CacheKey(1)] == nil, "Entry cap evicts least recently used item");
        [cache entryForKey:CacheKey(2)];
        [cache storeGuide:good key:CacheKey(102) date:NSDate.date];
        Require([cache entryForKey:CacheKey(2)] != nil && [cache entryForKey:CacheKey(3)] == nil, "Cache read refreshes eviction priority");
        Require([cache storeGuide:good key:@"../not-a-digest" date:NSDate.date] != nil, "Invalid cache identity rejected");
        Require([cache clear] == nil && ![NSFileManager.defaultManager fileExistsAtPath:path] && [cache entryForKey:CacheKey(2)] == nil, "Clear removes both disk and memory data");
        [@"invalid json" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        cache = [[CGDGuideCache alloc] initWithPath:path];
        Require([cache entryForKey:CacheKey(1)] == nil && [cache storeGuide:good key:CacheKey(1) date:NSDate.date] == nil, "Corrupt cache ignored and repaired by next valid write");
        NSMutableDictionary *big = [good mutableCopy];
        NSMutableArray *terms = [NSMutableArray array];
        NSString *chunk = [@"x" stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0];
        for (NSUInteger i = 0; i < 24; i++) [terms addObject:@{@"term": chunk, @"explanation": chunk}];
        [big setObject:terms forKey:@"title_breakdown"];
        Require(CGDValidateGuide(big) != nil, "Large but valid fixture accepted");
        for (NSUInteger i = 200; i < 300; i++) {
            @autoreleasepool { [cache storeGuide:big key:CacheKey(i) date:NSDate.date]; }
        }
        NSData *bounded = [NSData dataWithContentsOfFile:path];
        Require(bounded.length <= 4 * 1024 * 1024, "4 MiB byte cap enforced in addition to entry cap");
        Require([cache entryForKey:CacheKey(299)] != nil, "Newest large result retained");
        [cache clear];
        [[NSMutableData dataWithLength:4 * 1024 * 1024 + 1] writeToFile:path atomically:YES];
        cache = [[CGDGuideCache alloc] initWithPath:path];
        Require([cache entryForKey:CacheKey(299)] == nil, "Oversized disk cache ignored");
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        printf("PASS: %u guide request/parser/cache assertions (synthetic responses; no network).\n", checks);
    }
    return 0;
}
