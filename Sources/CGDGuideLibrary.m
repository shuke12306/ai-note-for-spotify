#import "CGDGuideLibrary.h"
#import "CGDGuideData.h"
#include <math.h>

static const NSUInteger CGDLibraryMaxBytes = 16 * 1024 * 1024;
static const NSUInteger CGDLibraryMaxItems = 200;
static NSString *CGDLibraryText(id text, NSUInteger limit) {
    return [text isKindOfClass:NSString.class] && [text length] && [text length] <= limit ? text : nil;
}
static NSDictionary *CGDLibraryItem(id raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    id snapshot = [raw objectForKey:@"snapshot"], event = [raw objectForKey:@"event"];
    if (![snapshot isKindOfClass:NSDictionary.class] || ![event isKindOfClass:NSDictionary.class]) return nil;
    NSString *title = CGDLibraryText([snapshot objectForKey:@"title"], 8192);
    NSString *identifier = CGDLibraryText([raw objectForKey:@"id"], 64);
    NSString *model = CGDLibraryText([event objectForKey:@"model"], 128), *language = CGDLibraryText([event objectForKey:@"language"], 64);
    NSDictionary *guide = CGDValidateGuide([event objectForKey:@"guide"]);
    NSNumber *savedAt = [raw objectForKey:@"savedAt"];
    NSArray *modules = CGDNormalizeRequestedModules([event objectForKey:@"availableModules"]);
    if (!title || !identifier || !model || !language || !guide || !modules.count ||
        ![savedAt isKindOfClass:NSNumber.class] || !isfinite(savedAt.doubleValue) || savedAt.doubleValue <= 0) return nil;
    NSMutableDictionary *track = [NSMutableDictionary dictionaryWithObject:title forKey:@"title"];
    for (NSString *key in @[@"artist", @"album", @"trackID"]) if (CGDLibraryText([snapshot objectForKey:key], 8192)) [track setObject:[snapshot objectForKey:key] forKey:key];
    id artists = [snapshot objectForKey:@"artists"];
    if ([artists isKindOfClass:NSArray.class] && [artists count] <= 64) {
        NSUInteger size = 0; BOOL valid = YES;
        for (id artist in artists) { if (!CGDLibraryText(artist, 8192)) { valid = NO; break; } size += [artist length] + 2; }
        if (valid && size <= 8192) [track setObject:artists forKey:@"artists"];
    }
    // Exclude diagnostics, request state, custom prompts and all credentials.
    NSDictionary *cleanEvent = @{@"guide": guide, @"availableModules": modules, @"model": model, @"language": language};
    return @{@"id": identifier, @"savedAt": savedAt, @"snapshot": track, @"event": cleanEvent};
}
@implementation CGDGuideLibrary
- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy]; _items = [[NSMutableDictionary alloc] init];
        if (![NSFileManager.defaultManager fileExistsAtPath:_path]) return self;
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:_path error:NULL];
        if ([[attrs objectForKey:NSFileSize] unsignedLongLongValue] > CGDLibraryMaxBytes) { _loadFailed = YES; return self; }
        NSData *data = [NSData dataWithContentsOfFile:_path];
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        id items = [root isKindOfClass:NSDictionary.class] ? [root objectForKey:@"items"] : nil;
        if (![root isKindOfClass:NSDictionary.class] || ![[root objectForKey:@"version"] isEqual:@1] || ![items isKindOfClass:NSArray.class] || [items count] > CGDLibraryMaxItems) { _loadFailed = YES; return self; }
        for (id raw in items) {
            NSDictionary *item = CGDLibraryItem(raw);
            if (!item || [_items objectForKey:[item objectForKey:@"id"]]) { _loadFailed = YES; return self; }
            [_items setObject:item forKey:[item objectForKey:@"id"]];
        }
    }
    return self;
}
- (NSString *)loadError { return _loadFailed ? @"收藏文件暂时无法读取，原文件已保留，未覆盖。" : nil; }
- (NSArray *)items {
    return [[_items allValues] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"savedAt" ascending:NO]]];
}
- (NSString *)commit:(NSMutableDictionary *)items {
    if (_loadFailed) return [self loadError];
    if (items.count > CGDLibraryMaxItems) return @"收藏已达 200 篇，请先移除不需要的收藏。";
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"items": items.allValues} options:0 error:NULL];
    if (!data || data.length > CGDLibraryMaxBytes) return @"收藏已达容量上限，请先移除不需要的收藏。";
    BOOL directory = [NSFileManager.defaultManager createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!directory || ![data writeToFile:_path options:NSDataWritingAtomic error:NULL]) return @"收藏保存失败，请稍后重试。";
    _items = items;
    return nil;
}
- (NSString *)saveSnapshot:(NSDictionary *)snapshot event:(NSDictionary *)event {
    if (_loadFailed) return [self loadError];
    NSString *identifier = NSUUID.UUID.UUIDString;
    for (NSDictionary *old in _items.allValues) {
        NSDictionary *oldEvent = [old objectForKey:@"event"];
        if ([CGDGuideTrackIdentity([old objectForKey:@"snapshot"], [oldEvent objectForKey:@"model"], [oldEvent objectForKey:@"language"])
            isEqual:CGDGuideTrackIdentity(snapshot, [event objectForKey:@"model"], [event objectForKey:@"language"])]) { identifier = [old objectForKey:@"id"]; break; }
    }
    NSDictionary *item = CGDLibraryItem(@{@"id": identifier, @"snapshot": snapshot ?: @{}, @"event": event ?: @{}, @"savedAt": @(NSDate.date.timeIntervalSince1970)});
    if (!item) return @"当前还没有可以收藏的导赏。";
    NSMutableDictionary *next = [_items mutableCopy]; [next setObject:item forKey:identifier];
    return [self commit:next];
}
- (NSString *)removeItem:(NSString *)identifier {
    NSMutableDictionary *next = [_items mutableCopy]; [next removeObjectForKey:identifier];
    return [self commit:next];
}
@end
