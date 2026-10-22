#import "CGDGuideCache.h"
#import "CGDGuideData.h"
#include <math.h>

static const NSUInteger CGDCacheMaxBytes = 4 * 1024 * 1024;
static const NSUInteger CGDCacheMaxEntries = 100;

static BOOL CGDCacheKeyValid(id key) {
    if (![key isKindOfClass:NSString.class] || [key length] != 64) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    return [key rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

@implementation CGDGuideCache
- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy];
        _entries = [[NSMutableDictionary alloc] init];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:_path error:NULL];
        if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > CGDCacheMaxBytes) return self;
        NSData *data = [NSData dataWithContentsOfFile:_path];
        id root = data.length && data.length <= CGDCacheMaxBytes ?
            [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![root isKindOfClass:NSDictionary.class] || ![[root objectForKey:@"version"] isEqual:@1]) return self;
        id entries = [root objectForKey:@"entries"];
        if (![entries isKindOfClass:NSDictionary.class] || [entries count] > CGDCacheMaxEntries) return self;
        for (id key in entries) {
            id entry = [entries objectForKey:key];
            if (!CGDCacheKeyValid(key) || ![entry isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *guide = CGDValidateGuide([entry objectForKey:@"guide"]);
            id date = [entry objectForKey:@"generatedAt"];
            id used = [entry objectForKey:@"usedAt"];
            if (!guide || ![date isKindOfClass:NSNumber.class] || ![used isKindOfClass:NSNumber.class] ||
                !isfinite([date doubleValue]) || !isfinite([used doubleValue]) || [date doubleValue] <= 0 ||
                [date doubleValue] > NSDate.date.timeIntervalSince1970 + 86400) continue;
            [_entries setObject:@{@"guide": guide, @"generatedAt": date, @"usedAt": used} forKey:key];
        }
    }
    return self;
}
- (NSDictionary *)entryForKey:(NSString *)key {
    NSDictionary *entry = [_entries objectForKey:key];
    if (!entry) return nil;
    NSMutableDictionary *touched = [entry mutableCopy];
    [touched setObject:@(NSDate.date.timeIntervalSince1970) forKey:@"usedAt"];
    [_entries setObject:touched forKey:key];
    // Touches stay in memory until the next write, avoiding a disk write per read.
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
    return [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"entries": _entries} options:0 error:NULL];
}
- (NSString *)storeGuide:(NSDictionary *)guide key:(NSString *)key date:(NSDate *)date {
    NSDictionary *checked = CGDValidateGuide(guide);
    if (!checked || !CGDCacheKeyValid(key) || !date) return @"本次结果未能写入缓存。";
    [_entries setObject:@{@"guide": checked, @"generatedAt": @(date.timeIntervalSince1970),
        @"usedAt": @(NSDate.date.timeIntervalSince1970)} forKey:key];
    while (_entries.count > CGDCacheMaxEntries) [self evictOldest];
    NSData *data = [self encoded];
    while (data.length > CGDCacheMaxBytes && _entries.count) { [self evictOldest]; data = [self encoded]; }
    BOOL directory = [NSFileManager.defaultManager createDirectoryAtPath:[_path stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!directory || !data || ![data writeToFile:_path options:NSDataWritingAtomic error:NULL]) {
        return @"导赏已生成，但本地缓存保存失败；本次仍可阅读。";
    }
    return nil;
}
- (NSString *)clear {
    [_entries removeAllObjects];
    if ([NSFileManager.defaultManager fileExistsAtPath:_path] &&
        ![NSFileManager.defaultManager removeItemAtPath:_path error:NULL]) return @"缓存文件未能删除，请重试。";
    return nil;
}
@end
