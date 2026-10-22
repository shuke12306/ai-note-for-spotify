#import "CGDTrackReader.h"
#include <string.h>
#include <stdlib.h>

static const char *CGDUnqualified(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL CGDTypeMatches(const char *type, char expected) {
    type = CGDUnqualified(type);
    return type[0] == expected && !(expected == '@' && type[1] == '?');
}

BOOL CGDMethodMatches(Class cls, SEL selector, const char *expected) {
    if (!cls || !selector || !expected || strlen(expected) < 3) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != strlen(expected) - 1) return NO;
    char *type = method_copyReturnType(method);
    BOOL matches = type && CGDTypeMatches(type, expected[0]);
    free(type);
    for (unsigned int i = 0; matches && i < method_getNumberOfArguments(method); i++) {
        type = method_copyArgumentType(method, i);
        matches = type && CGDTypeMatches(type, expected[i + 1]);
        free(type);
    }
    return matches;
}

static id CGDGetObject(id target, NSString *name, NSMutableArray *notes) {
    if (!target) return nil;
    SEL selector = NSSelectorFromString(name);
    if (!CGDMethodMatches(object_getClass(target), selector, "@@:")) {
        [notes addObject:[name stringByAppendingString:@"：方法缺失或签名不符"]];
        return nil;
    }
    @try {
        Method method = class_getInstanceMethod(object_getClass(target), selector);
        NSMethodSignature *signature =
            [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:target];
        [invocation setSelector:selector];
        [invocation invoke];
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        return result;
    } @catch (NSException *exception) {
        // Exception reasons can contain host data; only retain the exception name.
        [notes addObject:[NSString stringWithFormat:@"%@：读取异常（%@）", name, exception.name]];
        return nil;
    }
}

static NSString *CGDString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // A diagnostic panel should never try to render an unbounded host value.
    if (!text.length || text.length > 8192) return nil;
    return [NSString stringWithString:text];
}

static NSString *CGDFirstMetadata(NSDictionary *metadata, NSArray *keys) {
    for (NSString *key in keys) {
        NSString *text = CGDString([metadata objectForKey:key]);
        if (text) return text;
    }
    return nil;
}

static NSArray *CGDArtistMetadataKeys(void) {
    // Spotify's indexed track names are also documented in spicetify/cli
    // globals.d.ts (artist_name, artist_name:1). Inspect only these exact keys;
    // never treat album artists, composers or Canvas artists as track credits.
    NSMutableArray *keys = [NSMutableArray arrayWithObject:@"artist_name"];
    for (NSUInteger i = 0; i < 64; i++) {
        [keys addObject:[NSString stringWithFormat:@"artist_name:%lu", (unsigned long)i]];
    }
    return keys;
}

static NSArray *CGDReadArtistNames(NSDictionary *metadata, NSMutableArray *notes) {
    NSMutableArray *names = [NSMutableArray array];
    NSUInteger length = 0, rejected = 0;
    for (NSString *key in CGDArtistMetadataKeys()) {
        id raw = [metadata objectForKey:key];
        if (!raw) continue;
        NSString *name = CGDString(raw);
        if (!name) { rejected++; continue; }
        if ([names containsObject:name]) continue;
        NSUInteger added = name.length + (names.count ? 2 : 0);
        if (names.count >= 64 || length + added > 8192) { rejected++; continue; }
        [names addObject:name];
        length += added;
    }
    if (rejected) [notes addObject:[NSString stringWithFormat:
        @"艺术家元数据：%lu 项为空、类型不符或超过长度上限，已略过", (unsigned long)rejected]];
    return [NSArray arrayWithArray:names];
}

static NSString *CGDBase62ID(NSString *value) {
    if (value.length != 22) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
        @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"] invertedSet];
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound ? value : nil;
}

static NSString *CGDIDFromString(NSString *value) {
    if (!value) return nil;
    if ([value hasPrefix:@"spotify:track:"]) {
        return CGDBase62ID([value substringFromIndex:@"spotify:track:".length]);
    }
    NSURL *url = [NSURL URLWithString:value];
    if (![url.host.lowercaseString isEqualToString:@"open.spotify.com"]) return nil;
    NSArray *parts = url.pathComponents;
    // /track/id or /intl-xx/track/id; never include query strings in diagnostics.
    NSUInteger index = [parts indexOfObject:@"track"];
    if (index == NSNotFound || index + 2 != parts.count) return nil;
    return CGDBase62ID([parts objectAtIndex:index + 1]);
}

static NSString *CGDTrackID(id track, NSDictionary *metadata, NSMutableArray *notes) {
    id uri = CGDGetObject(track, @"URI", notes);
    NSString *identifier = nil;
    if ([uri isKindOfClass:NSString.class]) {
        identifier = CGDIDFromString(uri);
    } else if ([uri isKindOfClass:NSURL.class]) {
        identifier = CGDIDFromString([uri absoluteString]);
    } else if (uri) {
        identifier = CGDBase62ID(CGDString(CGDGetObject(uri, @"spt_trackIdentifier", notes)));
        if (!identifier) {
            identifier = CGDIDFromString(CGDString(CGDGetObject(uri, @"absoluteString", notes)));
        }
    }
    if (!identifier) identifier = CGDBase62ID(CGDFirstMetadata(metadata, @[@"track_id"]));
    if (!identifier) {
        identifier = CGDIDFromString(CGDFirstMetadata(metadata, @[@"track_uri", @"uri"]));
    }
    return identifier;
}

static NSArray *CGDRelevantKeys(NSDictionary *metadata) {
    // Only key names from this fixed allowlist are exportable. No raw dictionary.
    NSArray *allowed = @[@"title", @"track_title", @"artist_name", @"artist_title",
        @"album_title", @"album_name", @"album", @"track_id", @"track_uri", @"uri",
        @"composer", @"composer_name", @"disc_number", @"track_number",
        @"duration", @"duration_ms", @"movement", @"movement_number"];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in allowed) {
        if ([metadata objectForKey:key] != nil) [keys addObject:key];
    }
    for (NSString *key in CGDArtistMetadataKeys()) {
        if ([metadata objectForKey:key] != nil && ![keys containsObject:key]) [keys addObject:key];
    }
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary *CGDSnapshot(NSString *title, NSString *artist, NSString *album,
                                NSString *trackID, NSArray *artists, NSString *status, NSArray *notes,
                                NSArray *keys, id player, id track) {
    return @{@"title": title ?: @"", @"artist": artist ?: @"", @"album": album ?: @"",
        @"artists": artists ?: @[],
        @"trackID": trackID ?: @"", @"status": status,
        @"notes": [NSArray arrayWithArray:notes], @"metadataKeys": [NSArray arrayWithArray:keys],
        @"playerClass": player ? NSStringFromClass(object_getClass(player)) : @"未捕获",
        @"trackClass": track ? NSStringFromClass(object_getClass(track)) : @"未取得"};
}

NSDictionary *CGDReadTrackSnapshot(id player) {
    NSMutableArray *notes = [NSMutableArray array];
    if (!player) return CGDSnapshot(nil, nil, nil, nil, nil, @"尚未捕获播放器，请先打开完整播放页",
                                    notes, @[], nil, nil);
    id track = CGDGetObject(player, @"currentTrack", notes);
    if (!track) return CGDSnapshot(nil, nil, nil, nil, nil, @"未取得当前曲目", notes, @[], player, nil);
    @try {
        id metadataValue = CGDGetObject(track, @"metadata", notes);
        NSDictionary *metadata = [metadataValue isKindOfClass:NSDictionary.class] ?
            [NSDictionary dictionaryWithDictionary:metadataValue] : @{};
        if (metadataValue && ![metadataValue isKindOfClass:NSDictionary.class]) {
            [notes addObject:@"metadata：返回类型不是字典"];
        }
        NSString *title = CGDString(CGDGetObject(track, @"trackTitle", notes));
        if (!title) title = CGDFirstMetadata(metadata, @[@"title", @"track_title"]);
        NSArray *artists = CGDReadArtistNames(metadata, notes);
        NSString *artist = artists.count ? [artists componentsJoinedByString:@"; "] : nil;
        if (artist) {
            [notes addObject:[NSString stringWithFormat:
                @"艺术家读取：曲目元数据，%lu 个名称；已检查 artist_name 和 artist_name:0…63，角色未标注",
                (unsigned long)artists.count]];
        } else {
            artist = CGDString(CGDGetObject(track, @"artistTitle", notes));
            if (!artist) artist = CGDString(CGDGetObject(track, @"artistName", notes));
            if (!artist) artist = CGDFirstMetadata(metadata, @[@"artist_title"]);
            [notes addObject:artist ? @"艺术家读取：单个显示字段，未取得逐项名单" : @"艺术家读取：未取得"];
        }
        NSString *album = CGDFirstMetadata(metadata, @[@"album_title", @"album_name", @"album"]);
        NSString *identifier = CGDTrackID(track, metadata, notes);

        // A synchronous getter may trigger host work. Reject a change during reading.
        id endingTrack = CGDGetObject(player, @"currentTrack", notes);
        if (endingTrack != track) {
            [notes addObject:@"读取期间曲目对象发生变化；本次字段已清空，请刷新"];
            return CGDSnapshot(nil, nil, nil, nil, nil, @"曲目发生变化，请刷新", notes, @[], player, nil);
        }
        return CGDSnapshot(title, artist, album, identifier, artists,
            title ? @"已读取，待与 Spotify 页面核对" : @"已取得曲目对象，但未读取到标题",
            notes, CGDRelevantKeys(metadata), player, track);
    } @catch (NSException *exception) {
        [notes addObject:[NSString stringWithFormat:@"曲目解析异常（%@）；本次字段已清空", exception.name]];
        return CGDSnapshot(nil, nil, nil, nil, nil, @"读取失败", notes, @[], player, nil);
    }
}
