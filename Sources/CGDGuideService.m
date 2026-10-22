#import "CGDGuideService.h"
#import "CGDGuideData.h"
#import "CGDGuideCache.h"
#import "CGDGuideModuleCache.h"
#import "CGDModulePreferences.h"
#import "CGDSettingsStore.h"
#import "CGDGuideLanguage.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *CGDNetworkFailure(NSError *error) {
    if (!error) return nil;
    if (![error.domain isEqual:NSURLErrorDomain]) return @"请求失败，请稍后重试。";
    switch (error.code) {
        case NSURLErrorTimedOut: return @"生成等待超时，请稍后手动重试。";
        case NSURLErrorNotConnectedToInternet: case NSURLErrorNetworkConnectionLost:
            return @"网络不可用或连接中断，请检查网络后重试。";
        case NSURLErrorCannotFindHost: case NSURLErrorCannotConnectToHost: case NSURLErrorDNSLookupFailed:
            return @"暂时无法连接 DeepSeek，请检查网络后重试。";
        case NSURLErrorSecureConnectionFailed: case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasBadDate: case NSURLErrorServerCertificateHasUnknownRoot:
            return @"无法建立安全连接，请检查网络与手机时间后重试。";
        default: return @"网络请求未完成，请手动重试。";
    }
}

// Ephemeral, bounded, one-shot transport. No redirects, automatic retries,
// disk response cache, cookie persistence, logging, or custom TLS trust rules.
@interface CGDGuideHTTP : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableData *bytes;
@property(nonatomic, copy) NSString *failure;
@property(nonatomic) NSInteger status;
@property(nonatomic, copy) void (^completion)(NSData *, NSInteger, NSString *);
- (void)start:(NSURLRequest *)request;
@end

@implementation CGDGuideHTTP
- (void)start:(NSURLRequest *)request {
    self.bytes = [NSMutableData data];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCredentialStorage = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 45;
    configuration.timeoutIntervalForResource = 90;
    NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
    delegateQueue.maxConcurrentOperationCount = 1;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:delegateQueue];
    [[self.session dataTaskWithRequest:request] resume];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    self.failure = @"接口返回了重定向，已停止请求，请稍后重试。";
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    (void)session; (void)task;
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    self.failure = self.failure ?: CGDGuideHTTPError(self.status);
    if (!self.failure && response.expectedContentLength > 512 * 1024) self.failure = @"接口响应过大，已停止读取，请重试。";
    completionHandler(self.failure ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;
    if (self.failure) return;
    if (data.length > 512 * 1024 - self.bytes.length) {
        self.failure = @"接口响应过大，已停止读取，请重试。";
        [task cancel];
        return;
    }
    [self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)task;
    void (^completion)(NSData *, NSInteger, NSString *) = self.completion;
    self.completion = nil;
    if (completion) completion([self.bytes copy], self.status, self.failure ?: CGDNetworkFailure(error));
    self.bytes = nil;
    [session finishTasksAndInvalidate];
    self.session = nil;
}
@end

@interface CGDGuideJob : NSObject
@property(nonatomic, strong) CGDGuideHTTP *transport;
@property(nonatomic, strong) NSMutableDictionary<NSUUID *, id> *listeners;
@property(nonatomic) NSUInteger cacheEpoch;
@property(nonatomic, copy) NSDictionary *moduleKeys;
@end
@implementation CGDGuideJob
@end

@interface CGDGuideTicket : NSObject
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, copy) NSDictionary *base;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *language;
@property(nonatomic, copy) NSDictionary *prompts;
@property(nonatomic, copy) NSData *trackIdentity;
@property(nonatomic, copy) NSArray *modules;
@property(nonatomic, copy) NSString *singleModule;
@property(nonatomic, copy) NSDictionary *moduleKeys;
@property(nonatomic, strong) NSMutableDictionary *entries;
@property(nonatomic, strong) NSMutableDictionary *errors;
@property(nonatomic, strong) NSMutableSet *waiting;
@property(nonatomic, strong) NSMutableSet *generated;
@property(nonatomic, copy) NSString *warning;
@property(nonatomic, copy) CGDGuideCompletion completion;
@property(nonatomic) BOOL finished;
@end
@implementation CGDGuideTicket
@end

@interface CGDGuideService ()
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) CGDGuideModuleCache *cache;
@property(nonatomic, strong) CGDGuideCache *legacyCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, CGDGuideJob *> *jobs;
@property(nonatomic) NSUInteger cacheEpoch;
- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot modules:(NSArray *)modules force:(BOOL)force singleModule:(NSString *)module baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion;
@end

static NSString *CGDDigest(NSData *identity) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(identity.bytes, (CC_LONG)identity.length, digest);
    NSMutableString *key = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}

@implementation CGDGuideService
+ (instancetype)shared {
    static CGDGuideService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ service = [[self alloc] init]; });
    return service;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.classicalguide.guide", DISPATCH_QUEUE_SERIAL);
        _jobs = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)prepareCache {
    if (self.cache) return;
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (directory.length) {
        self.cache = [[CGDGuideModuleCache alloc] initWithPath:
            [directory stringByAppendingPathComponent:@"com.classicalguide/modules-v2.json"]];
        self.legacyCache = [[CGDGuideCache alloc] initWithPath:
            [directory stringByAppendingPathComponent:@"com.classicalguide/guides-v1.json"]];
    }
}
- (void)deliver:(CGDGuideCompletion)completion event:(NSDictionary *)event {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(event); });
}
- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot force:(BOOL)force completion:(CGDGuideCompletion)completion {
    NSMutableArray *modules = [CGDPromptModuleIDs() mutableCopy];
    [modules removeObjectsInArray:CGDLoadModuleLayout()[@"hidden"]];
    return [self requestSnapshot:snapshot modules:modules force:force baseEvent:nil completion:completion];
}
- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot modules:(NSArray *)modules force:(BOOL)force baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion {
    return [self requestSnapshot:snapshot modules:modules force:force singleModule:nil baseEvent:baseEvent completion:completion];
}
- (NSUUID *)regenerateModule:(NSString *)module snapshot:(NSDictionary *)snapshot baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion {
    return [self requestSnapshot:snapshot modules:module ? @[module] : @[] force:YES singleModule:module baseEvent:baseEvent completion:completion];
}

- (void)finishTicket:(CGDGuideTicket *)ticket {
    if (ticket.finished || ticket.waiting.count) return;
    ticket.finished = YES;
    NSDictionary *guide = ticket.base[@"guide"] ?: CGDEmptyGuide(ticket.snapshot);
    NSMutableSet *available = [NSMutableSet setWithArray:CGDNormalizeRequestedModules(ticket.base[@"availableModules"])];
    NSMutableDictionary *keys = [ticket.base[@"moduleKeys"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *prompts = [CGDNormalizeGuidePrompts(ticket.base[@"prompts"] ?: ticket.prompts) mutableCopy];
    NSMutableDictionary *dates = [ticket.base[@"moduleDates"] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *module in ticket.entries) {
        NSDictionary *entry = ticket.entries[module];
        NSDictionary *merged = CGDMergeGuideModule(guide, entry[@"value"], module);
        if (!merged) {
            ticket.errors[module] = @"此模块与已有内容合并后过长，请缩短提示词中的篇幅要求后重试。";
            [ticket.generated removeObject:module];
            continue;
        }
        guide = merged;
        [available addObject:module];
        keys[module] = entry[@"key"];
        dates[module] = entry[@"generatedAt"];
        prompts[module] = ticket.prompts[module];
    }
    NSMutableSet *failed = [NSMutableSet setWithArray:CGDNormalizeRequestedModules(ticket.base[@"failedModules"])];
    for (NSString *module in ticket.modules) {
        if (ticket.errors[module]) [failed addObject:module];
        else [failed removeObject:module];
    }
    NSMutableDictionary *event = [@{@"model": ticket.model, @"language": ticket.language,
        @"prompts": prompts, @"trackIdentity": ticket.trackIdentity,
        @"moduleKeys": keys, @"moduleDates": dates, @"requestedModules": ticket.modules,
        @"availableModules": CGDNormalizeRequestedModules(available.allObjects),
        @"failedModules": CGDNormalizeRequestedModules(failed.allObjects)} mutableCopy];
    if (available.count) {
        event[@"guide"] = guide;
        double latest = 0;
        for (NSNumber *date in dates.allValues) latest = MAX(latest, date.doubleValue);
        event[@"generatedAt"] = @(latest ?: NSDate.date.timeIntervalSince1970);
    }
    NSUInteger cachedCount = 0;
    for (NSString *module in ticket.modules) if (ticket.entries[module] && ![ticket.generated containsObject:module]) cachedCount++;
    event[@"source"] = ticket.generated.count ? (ticket.singleModule ? @"module" : (cachedCount ? @"mixed" : @"network")) : @"cache";
    event[@"generatedCount"] = @(ticket.generated.count);
    event[@"cachedCount"] = @(cachedCount);
    if (ticket.singleModule) event[@"module"] = ticket.singleModule;
    if (ticket.warning) event[@"warning"] = ticket.warning;
    if (ticket.errors.count) {
        NSSet *unique = [NSSet setWithArray:ticket.errors.allValues];
        if (unique.count == 1) event[@"error"] = unique.anyObject;
        else {
            NSMutableArray *messages = [NSMutableArray array];
            for (NSString *module in ticket.modules) if (ticket.errors[module]) [messages addObject:
                [NSString stringWithFormat:@"%@：%@", CGDPromptModuleTitle(module), ticket.errors[module]]];
            event[@"error"] = [messages componentsJoinedByString:@"\n"];
        }
    }
    [self deliver:ticket.completion event:event];
    ticket.completion = nil;
}

- (void)failTicket:(CGDGuideTicket *)ticket modules:(NSArray *)modules reason:(NSString *)reason {
    for (NSString *module in modules) { ticket.errors[module] = reason; [ticket.waiting removeObject:module]; }
}

- (void)subscribeTicket:(CGDGuideTicket *)ticket token:(NSUUID *)token job:(CGDGuideJob *)job modules:(NSArray *)modules {
    if (job.listeners.count >= 16) {
        [self failTicket:ticket modules:modules reason:@"此曲目正在生成，请稍后重试。"];
        return;
    }
    job.listeners[token] = [^(NSDictionary *entries, NSDictionary *errors, NSString *warning) {
        for (NSString *module in modules) {
            if (![ticket.waiting containsObject:module]) continue;
            if (entries[module]) { ticket.entries[module] = entries[module]; [ticket.generated addObject:module]; }
            else ticket.errors[module] = errors[module] ?: @"模块未能生成，请重试。";
            [ticket.waiting removeObject:module];
        }
        if (warning) ticket.warning = warning;
        [self finishTicket:ticket];
    } copy];
}

- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot modules:(NSArray *)modules force:(BOOL)force singleModule:(NSString *)module baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion {
    NSUUID *token = NSUUID.UUID;
    NSDictionary *captured = [snapshot copy];
    NSDictionary *base = [baseEvent copy];
    NSString *language = (module ? base[@"language"] : nil) ?: CGDGuideLanguageName(CGDLoadGuideLanguage());
    NSString *model = (module ? base[@"model"] : nil) ?: CGDSettingsModelName();
    NSDictionary *prompts = CGDLoadGuidePrompts();
    NSArray *requested = CGDNormalizeRequestedModules(modules);
    dispatch_async(self.queue, ^{
        NSData *trackIdentity = CGDGuideTrackIdentity(captured, model, language);
        if (module && (![CGDPromptModuleIDs() containsObject:module] || !CGDValidateGuide(base[@"guide"]) ||
            ![base[@"trackIdentity"] isEqual:trackIdentity])) {
            [self deliver:completion event:@{@"error": @"请先为当前曲目生成导赏，再更新单个模块。"}];
            return;
        }
        if (!requested.count) {
            [self deliver:completion event:@{@"skipped": @(YES), @"availableModules": @[], @"model": model, @"language": language}];
            return;
        }
        if (!CGDGuideRequestBodyForModules(captured, model, language, prompts, requested)) {
            [self deliver:completion event:@{@"error": @"尚未读到完整曲名，请先播放歌曲，再点击“读取正在播放的曲目”。", @"model": model}];
            return;
        }
        [self prepareCache];
        NSString *trackKey = CGDDigest(trackIdentity);
        CGDGuideTicket *ticket = [[CGDGuideTicket alloc] init];
        ticket.snapshot = captured; ticket.model = model; ticket.language = language; ticket.prompts = prompts;
        ticket.modules = requested; ticket.singleModule = module; ticket.trackIdentity = trackIdentity;
        ticket.completion = completion; ticket.errors = [NSMutableDictionary dictionary];
        ticket.generated = [NSMutableSet set];
        if ([base[@"trackIdentity"] isEqual:trackIdentity] && CGDValidateGuide(base[@"guide"])) ticket.base = base;
        NSMutableDictionary *keys = [NSMutableDictionary dictionary], *cached = [NSMutableDictionary dictionary];
        NSMutableDictionary *owners = [NSMutableDictionary dictionary], *migrated = [NSMutableDictionary dictionary];
        // The legacy file has no separate prompt provenance: reuse it ONLY on
        // an exact match of its original whole-guide key. Never guess a match.
        NSDictionary *legacy = !force ? [self.legacyCache entryForKey:
            CGDDigest(CGDGuideIdentityWithPrompts(captured, model, language, prompts))] : nil;
        NSDictionary *legacyPrompts = prompts;
        if (!force && !legacy) {
            legacyPrompts = CGDGuidePromptsBefore050(prompts);
            legacy = [self.legacyCache entryForKey:CGDDigest(CGDGuideIdentityWithPrompts(captured, model, language, legacyPrompts))];
        }
        for (NSString *identifier in requested) {
            NSString *identity = CGDDigest(CGDGuideModuleIdentity(captured, model, language, prompts, identifier));
            keys[identifier] = identity;
            NSDictionary *entry = [self.cache entryForTrack:trackKey module:identifier key:identity];
            if (!entry && legacy && [legacyPrompts[identifier] isEqual:prompts[identifier]]) {
                NSDictionary *value = CGDValidateGuideModule(legacy[@"guide"], identifier);
                if (value) { entry = @{@"key": identity, @"value": value, @"generatedAt": legacy[@"generatedAt"]}; migrated[identifier] = entry; }
            }
            if (!entry && [ticket.base[@"moduleKeys"][identifier] isEqual:identity]) {
                NSDictionary *value = CGDValidateGuideModule(ticket.base[@"guide"], identifier);
                if (value) entry = @{@"key": identity, @"value": value,
                    @"generatedAt": ticket.base[@"moduleDates"][identifier] ?: ticket.base[@"generatedAt"]};
            }
            if (entry) cached[identifier] = entry;
            for (CGDGuideJob *running in self.jobs.allValues) if ([running.moduleKeys[identifier] isEqual:identity]) owners[identifier] = running;
        }
        if (migrated.count) ticket.warning = [self.cache storeEntries:migrated forTrack:trackKey];
        ticket.moduleKeys = keys;
        // Retain cached text as a fallback if an explicit refresh fails.
        ticket.entries = cached;
        // Keep fallback text for display, but a manual retry must really retry
        // a failed refresh instead of treating that old text as a fresh success.
        NSDictionary *plan = CGDPlanGuideModulesRetrying(requested, cached, [NSSet setWithArray:owners.allKeys], ticket.base[@"failedModules"], force);
        NSArray *fresh = plan[@"generate"];
        ticket.waiting = [NSMutableSet setWithArray:[plan[@"join"] arrayByAddingObjectsFromArray:fresh]];
        for (CGDGuideJob *running in [NSSet setWithArray:owners.allValues]) {
            NSMutableArray *joined = [NSMutableArray array];
            for (NSString *identifier in plan[@"join"]) if (owners[identifier] == running) [joined addObject:identifier];
            [self subscribeTicket:ticket token:token job:running modules:joined];
        }
        if (!fresh.count) { [self finishTicket:ticket]; return; }
        if (self.jobs.count >= 2) {
            [self failTicket:ticket modules:fresh reason:@"已有两项生成正在进行，请稍候重试未完成的模块。"];
            [self finishTicket:ticket];
            return;
        }
        NSString *failure = nil;
        NSString *secret = CGDSettingsReadAPIKey(&failure);
        if (!secret) {
            [self failTicket:ticket modules:fresh reason:failure ?: @"无法读取 API Key，请检查设置。"];
            [self finishTicket:ticket];
            return;
        }
        NSDictionary *body = CGDGuideRequestBodyForModules(captured, model, language, prompts, fresh);
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        if (!encoded) {
            [self failTicket:ticket modules:fresh reason:@"曲目信息无法编码，请重新读取曲目。"];
            [self finishTicket:ticket];
            return;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.deepseek.com/chat/completions"]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = encoded;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:[@"Bearer " stringByAppendingString:secret] forHTTPHeaderField:@"Authorization"];
        CGDGuideJob *job = [[CGDGuideJob alloc] init];
        job.listeners = [NSMutableDictionary dictionary];
        job.cacheEpoch = self.cacheEpoch;
        NSMutableDictionary *jobKeys = [NSMutableDictionary dictionary];
        for (NSString *identifier in fresh) jobKeys[identifier] = keys[identifier];
        job.moduleKeys = jobKeys;
        job.transport = [[CGDGuideHTTP alloc] init];
        NSString *key = NSUUID.UUID.UUIDString;
        self.jobs[key] = job;
        [self subscribeTicket:ticket token:token job:job modules:fresh];
        job.transport.completion = ^(NSData *data, NSInteger status, NSString *transportError) {
            dispatch_async(self.queue, ^{
                CGDGuideJob *finished = self.jobs[key];
                if (!finished) return;
                NSDictionary *errors = nil;
                NSDictionary *partials = transportError ? nil : CGDParseGuideModulesResponse(data, status, captured, fresh, &errors);
                if (transportError) {
                    NSMutableDictionary *transportErrors = [NSMutableDictionary dictionary];
                    for (NSString *identifier in fresh) transportErrors[identifier] = transportError;
                    errors = transportErrors;
                }
                NSMutableDictionary *entries = [NSMutableDictionary dictionary];
                NSNumber *date = @(NSDate.date.timeIntervalSince1970);
                for (NSString *identifier in fresh) if (partials[identifier]) entries[identifier] =
                    @{@"key": finished.moduleKeys[identifier], @"value": partials[identifier], @"generatedAt": date};
                NSString *warning = nil;
                // Each write merges only its own modules. Concurrent disjoint
                // requests cannot overwrite another module or resurrect clears.
                if (entries.count && finished.cacheEpoch == self.cacheEpoch) warning = self.cache ?
                    [self.cache storeEntries:entries forTrack:trackKey] : @"本地缓存暂不可用；本次仍可阅读。";
                NSArray *callbacks = finished.listeners.allValues;
                [finished.listeners removeAllObjects];
                [self.jobs removeObjectForKey:key];
                for (void (^callback)(NSDictionary *, NSDictionary *, NSString *) in callbacks) callback(entries, errors, warning);
            });
        };
        [job.transport start:request];
        [self finishTicket:ticket];
    });
    return token;
}
- (void)cancelSubscription:(NSUUID *)token {
    if (!token) return;
    dispatch_async(self.queue, ^{
        for (CGDGuideJob *job in self.jobs.allValues) [job.listeners removeObjectForKey:token];
        // An already submitted request may be billable. Finish it for cache reuse;
        // detaching UI does not cancel and then accidentally submit it again.
    });
}
- (void)restoreModule:(NSString *)module snapshot:(NSDictionary *)snapshot previousEvent:(NSDictionary *)previous currentEvent:(NSDictionary *)current completion:(CGDGuideCompletion)completion {
    dispatch_async(self.queue, ^{
        NSDictionary *restored = CGDRestoreGuideModuleEvent(module, previous, current);
        NSData *identity = CGDGuideTrackIdentity(snapshot, current[@"model"], current[@"language"]);
        if (!restored || ![identity isEqual:current[@"trackIdentity"]]) {
            [self deliver:completion event:@{@"error": @"上一版与当前曲目不匹配，未恢复。"}]; return;
        }
        for (CGDGuideJob *job in self.jobs.allValues) {
            if ([job.moduleKeys[module] isEqual:current[@"moduleKeys"][module]] || [job.moduleKeys[module] isEqual:previous[@"moduleKeys"][module]]) {
                [self deliver:completion event:@{@"error": @"此模块正在生成，请完成后再恢复上一版。"}]; return;
            }
        }
        [self prepareCache];
        NSDictionary *entry = @{@"key": restored[@"moduleKeys"][module], @"generatedAt": restored[@"moduleDates"][module],
            @"value": CGDValidateGuideModule(restored[@"guide"], module)};
        NSString *failure = self.cache ? [self.cache storeEntries:@{module: entry} forTrack:CGDDigest(identity)] : @"本地缓存暂不可用。";
        NSMutableDictionary *event = [restored mutableCopy];
        if (failure) event[@"warning"] = failure;
        [self deliver:completion event:event];
    });
}
- (void)clearCache:(void (^)(NSString *))completion {
    dispatch_async(self.queue, ^{
        [self prepareCache];
        self.cacheEpoch++;
        NSString *failure = [self.cache clear];
        NSString *legacyFailure = [self.legacyCache clear];
        failure = failure ?: legacyFailure;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(failure); });
    });
}
@end
