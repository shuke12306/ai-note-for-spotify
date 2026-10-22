#import "CGDGuideModuleCache.h"
#import "CGDGuideData.h"
#include <math.h>

static const NSUInteger CGDModuleCacheMaxBytes = 4 * 1024 * 1024;
static const NSUInteger CGDModuleCacheMaxTracks = 100;

static BOOL CGDModuleKeyValid(id key) {
    if (![key isKindOfClass:NSString.class] || [key length] != 64) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [key rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}
static BOOL CGDModuleDateValid(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) && [value doubleValue] > 0 &&
        [value doubleValue] <= NSDate.date.timeIntervalSince1970 + 86400;
}
static NSDictionary *CGDCheckedModuleEntry(id entry, NSString *module) {
    if (![entry isKindOfClass:NSDictionary.class] || !CGDModuleKeyValid([entry objectForKey:@"key"]) ||
        !CGDModuleDateValid([entry objectForKey:@"generatedAt"])) return nil;
    NSDictionary *value = CGDValidateGuideModule([entry objectForKey:@"value"], module);
    return value ? @{@"key": [entry objectForKey:@"key"], @"value": value, @"generatedAt": [entry objectForKey:@"generatedAt"]} : nil;
}

@implementation CGDGuideModuleCache
- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy];
        _entries = [[NSMutableDictionary alloc] init];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:_path error:NULL];
        if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > CGDModuleCacheMaxBytes) return self;
        NSData *data = [NSData dataWithContentsOfFile:_path];
        id root = data.length && data.length <= CGDModuleCacheMaxBytes ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![root isKindOfClass:NSDictionary.class] || ![[root objectForKey:@"version"] isEqual:@2]) return self;
        id tracks = [root objectForKey:@"entries"];
        if (![tracks isKindOfClass:NSDictionary.class] || [tracks count] > CGDModuleCacheMaxTracks) return self;
        for (id trackKey in tracks) {
            id group = [tracks objectForKey:trackKey];
            if (!CGDModuleKeyValid(trackKey) || ![group isKindOfClass:NSDictionary.class] || !CGDModuleDateValid([group objectForKey:@"usedAt"])) continue;
            id raw = [group objectForKey:@"modules"];
            if (![raw isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *modules = [NSMutableDictionary dictionary];
            for (NSString *module in CGDPromptModuleIDs()) {
                NSDictionary *entry = CGDCheckedModuleEntry([raw objectForKey:module], module);
                if (entry) [modules setObject:entry forKey:module];
            }
            if (modules.count) [_entries setObject:@{@"modules": modules, @"usedAt": [group objectForKey:@"usedAt"]} forKey:trackKey];
        }
    }
    return self;
}
- (NSDictionary *)entryForTrack:(NSString *)trackKey module:(NSString *)module key:(NSString *)key {
    NSDictionary *group = [_entries objectForKey:trackKey];
    NSDictionary *entry = [[group objectForKey:@"modules"] objectForKey:module];
    if (![[entry objectForKey:@"key"] isEqual:key]) return nil;
    [_entries setObject:@{@"modules": [group objectForKey:@"modules"], @"usedAt": @(NSDate.date.timeIntervalSince1970)} forKey:trackKey];
    return entry;
}
- (void)evictOldest {
    NSString *oldestKey = nil;
    double oldest = INFINITY;
    for (NSString *key in _entries) {
        double used = [[[_entries objectForKey:key] objectForKey:@"usedAt"] doubleValue];
        if (used < oldest) { oldestKey = key; oldest = used; }
    }
    if (oldestKey) [_entries removeObjectForKey:oldestKey];
}
- (NSData *)encoded {
    return [NSJSONSerialization dataWithJSONObject:@{@"version": @2, @"entries": _entries} options:0 error:NULL];
}
- (NSString *)storeEntries:(NSDictionary *)entries forTrack:(NSString *)trackKey {
    if (!CGDModuleKeyValid(trackKey) || ![entries isKindOfClass:NSDictionary.class] || !entries.count) return @"本次模块未能写入缓存。";
    NSMutableDictionary *updates = [NSMutableDictionary dictionary];
    for (NSString *module in entries) {
        NSDictionary *entry = CGDCheckedModuleEntry([entries objectForKey:module], module);
        if (!entry) return @"本次模块未能写入缓存。";
        [updates setObject:entry forKey:module];
    }
    NSMutableDictionary *modules = [[[_entries objectForKey:trackKey] objectForKey:@"modules"] mutableCopy];
    if (!modules) modules = [NSMutableDictionary dictionary];
    [modules addEntriesFromDictionary:updates];
    [_entries setObject:@{@"modules": modules, @"usedAt": @(NSDate.date.timeIntervalSince1970)} forKey:trackKey];
    while (_entries.count > CGDModuleCacheMaxTracks) [self evictOldest];
    NSData *data = [self encoded];
    while (data.length > CGDModuleCacheMaxBytes && _entries.count) { [self evictOldest]; data = [self encoded]; }
    BOOL directory = [NSFileManager.defaultManager createDirectoryAtPath:[_path stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!directory || !data || ![data writeToFile:_path options:NSDataWritingAtomic error:NULL]) return @"导赏已生成，但模块缓存保存失败；本次仍可阅读。";
    return nil;
}
- (NSString *)clear {
    [_entries removeAllObjects];
    if (![NSFileManager.defaultManager fileExistsAtPath:_path]) return nil;
    return [NSFileManager.defaultManager removeItemAtPath:_path error:NULL] ? nil : @"缓存文件删除失败，请稍后重试。";
}
@end
