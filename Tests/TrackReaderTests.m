#import "CGDTrackReader.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int checks = 0;
static void Require(BOOL condition, const char *label) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}

@interface CGDFixtureTrack : NSObject {
@public
    id titleValue;
    id artistValue;
    id metadataValue;
    id uriValue;
}
@end
@implementation CGDFixtureTrack
- (id)trackTitle { return titleValue; }
- (id)artistTitle { return artistValue; }
- (id)artistName { return artistValue; }
- (id)metadata { return metadataValue; }
- (id)URI { return uriValue; }
@end

@interface CGDFixturePlayer : NSObject {
@public
    id firstTrack;
    id laterTrack;
    BOOL changing;
    NSUInteger calls;
}
@end
@implementation CGDFixturePlayer
- (id)currentTrack {
    calls++;
    return changing && calls > 1 ? laterTrack : firstTrack;
}
@end

static BOOL scalarCalled = NO;
@interface CGDScalarTitle : NSObject
@end
@implementation CGDScalarTitle
- (NSInteger)trackTitle { scalarCalled = YES; return 42; }
- (id)metadata { return @{@"title": @"Safe fallback", @"album_name": @"Album"}; }
@end

@interface CGDThrowingTrack : NSObject
@end
@implementation CGDThrowingTrack
- (id)trackTitle {
    [NSException raise:@"FixtureException" format:@"sensitive-reason-must-not-export"];
    return nil;
}
@end

@interface CGDFixtureURL : NSObject
@end
@implementation CGDFixtureURL
- (id)spt_trackIdentifier { return @"0123456789ABCDEFGHIJKL"; }
@end

@interface CGDSignatureFixture : NSObject
- (id)provider:(id)argument;
- (void)appearance:(BOOL)animated;
@end
@implementation CGDSignatureFixture
- (id)provider:(id)argument { return argument; }
- (void)appearance:(BOOL)animated { (void)animated; }
@end

static NSDictionary *Read(id track) {
    CGDFixturePlayer *player = [[CGDFixturePlayer alloc] init];
    player->firstTrack = track;
    NSDictionary *snapshot = CGDReadTrackSnapshot(player);
    Require(player->calls == 2, "read start and end track exactly once");
    [player release];
    return snapshot;
}

int main(void) {
    @autoreleasepool {
        Class signatureClass = [CGDSignatureFixture class];
        Require(CGDMethodMatches(signatureClass, @selector(provider:), "@@:@"), "object provider accepted");
        Require(!CGDMethodMatches(signatureClass, @selector(provider:), "@@:"), "wrong arity rejected");
        Require(!CGDMethodMatches(signatureClass, @selector(provider:), "v@:@"), "wrong return rejected");
        Require(!CGDMethodMatches(signatureClass, @selector(missing), "@@:"), "missing selector rejected");
        char booleanSignature[] = {'v', '@', ':', @encode(BOOL)[0], 0};
        Require(CGDMethodMatches(signatureClass, @selector(appearance:), booleanSignature), "BOOL encoding accepted");

        CGDFixtureTrack *track = [[CGDFixtureTrack alloc] init];
        NSMutableString *title = [NSMutableString stringWithString:
            @"Cello Suite No. 1 in G Major, BWV 1007: I. Prélude"];
        track->titleValue = title;
        track->artistValue = @"Performer";
        track->metadataValue = @{@"album_title": @"Bach: Cello Suites", @"track_number": @"1",
            @"access_token": @"SECRET", @"artist_token": @"SECRET", @"user_email": @"private"};
        track->uriValue = @"spotify:track:0123456789ABCDEFGHIJKL";
        NSDictionary *first = Read(track);
        Require([[first objectForKey:@"title"] isEqual:title], "complete title preserved");
        Require([[first objectForKey:@"artist"] isEqual:@"Performer"], "artist preserved");
        Require([[first objectForKey:@"artists"] count] == 0, "display-only artist is not split into guessed names");
        Require([[first objectForKey:@"album"] isEqual:@"Bach: Cello Suites"], "album_title extracted");
        Require([[first objectForKey:@"trackID"] isEqual:@"0123456789ABCDEFGHIJKL"], "track URI parsed");
        Require([[first objectForKey:@"metadataKeys"] count] == 2, "only allowlisted metadata key names");
        Require([[first description] rangeOfString:@"SECRET"].location == NSNotFound, "no raw metadata values");
        [title appendString:@" CHANGED"];
        Require([[first objectForKey:@"title"] rangeOfString:@"CHANGED"].location == NSNotFound,
                "snapshot owns a copy of mutable title");

        track->titleValue = nil;
        track->artistValue = nil;
        track->metadataValue = @{};
        track->uriValue = nil;
        NSDictionary *missing = Read(track);
        for (NSString *key in @[@"title", @"artist", @"album", @"trackID"]) {
            Require([[missing objectForKey:key] length] == 0, "missing fields never reuse previous snapshot");
        }
        Require([[missing objectForKey:@"artists"] count] == 0, "missing artist list cannot retain previous names");

        NSMutableString *performer = [NSMutableString stringWithString:@"Sir Neville Marriner"];
        track->artistValue = @"Johann Sebastian Bach";
        track->metadataValue = @{@"artist_name": @"Johann Sebastian Bach", @"artist_name:0": @"Johann Sebastian Bach",
            @"artist_name:1": performer, @"artist_name:2": @"Academy of St Martin in the Fields",
            @"artist_name:10": @"Choir of King's College, Cambridge",
            @"album_artist_name": @"Album-only artist", @"composer_name": @"Unverified role",
            @"canvas.artist.name": @"Canvas-only artist", @"artist_name:1:token": @"SECRET",
            @"artist_name:01": @"Not a canonical index", @"artist_name:64": @"Outside bound"};
        NSDictionary *multiple = Read(track);
        NSArray *expected = @[@"Johann Sebastian Bach", @"Sir Neville Marriner", @"Academy of St Martin in the Fields",
            @"Choir of King's College, Cambridge"];
        Require([[multiple objectForKey:@"artists"] isEqual:expected], "indexed artists read numerically with gaps and duplicates removed");
        Require([[multiple objectForKey:@"artist"] isEqual:[expected componentsJoinedByString:@"; "]], "primary getter cannot hide performers and orchestra");
        Require([[multiple objectForKey:@"metadataKeys"] containsObject:@"artist_name:10"], "indexed artist keys included in diagnosis");
        Require(![[multiple objectForKey:@"metadataKeys"] containsObject:@"artist_name:1:token"], "similar sensitive keys excluded from diagnosis");
        Require([[multiple description] rangeOfString:@"SECRET"].location == NSNotFound, "artist key prefix is not a raw dictionary export");
        [performer appendString:@" MUTATED"];
        Require([[[multiple objectForKey:@"artists"] objectAtIndex:1] isEqual:@"Sir Neville Marriner"], "artist names own immutable copies");

        track->metadataValue = @{@"artist_name": @"Bach", @"artist_name:1": @[],
            @"artist_name:2": @42, @"artist_name:3": [NSNull null], @"artist_name:4": @"  ",
            @"artist_name:5": @" Soloist ", @"artist_name:6": @"Bach"};
        NSDictionary *mixed = Read(track);
        Require([[mixed objectForKey:@"artists"] isEqual:@[@"Bach", @"Soloist"]], "invalid indexed values skipped, valid later names retained and trimmed");
        Require([[[mixed objectForKey:@"notes"] componentsJoinedByString:@" "] rangeOfString:@"4 项"].location != NSNotFound, "invalid entries explained without exporting their values");
        track->metadataValue = @{@"artist_name": @"Bach", @"artist_name:1": [@"x" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0],
            @"artist_name:2": @"Soloist"};
        Require([[Read(track) objectForKey:@"artists"] isEqual:@[@"Bach", @"Soloist"]], "oversized names rejected without discarding valid later artists");
        track->metadataValue = @{@"artist_name": [@"x" stringByPaddingToLength:8190 withString:@"x" startingAtIndex:0],
            @"artist_name:1": @"Soloist"};
        NSDictionary *bounded = Read(track);
        Require([[bounded objectForKey:@"artist"] length] <= 8192 && [[bounded objectForKey:@"artists"] count] == 1, "combined artist names remain bounded");

        // The same title with another recording must never retain the old performers.
        track->metadataValue = @{@"artist_name": @"Bach", @"artist_name:1": @"Second performer"};
        NSDictionary *second = Read(track);
        Require([[second objectForKey:@"artists"] isEqual:@[@"Bach", @"Second performer"]], "next recording replaces entire artist list");
        track->metadataValue = @{};
        track->artistValue = nil;
        Require([[Read(track) objectForKey:@"artists"] count] == 0, "next missing list clears previous performers");

        track->titleValue = @123;
        track->artistValue = @[@"wrong-type"];
        track->metadataValue = @{@"title": @"Fallback", @"artist_name": @"Artist B",
                                @"album_name": @"Album B"};
        track->uriValue = @"https://open.spotify.com/track/0123456789ABCDEFGHIJKL?si=private";
        NSDictionary *fallback = Read(track);
        Require([[fallback objectForKey:@"title"] isEqual:@"Fallback"], "wrong title type uses metadata");
        Require([[fallback objectForKey:@"artist"] isEqual:@"Artist B"], "artist metadata fallback");
        Require([[fallback objectForKey:@"album"] isEqual:@"Album B"], "album_name fallback");
        Require([[fallback objectForKey:@"trackID"] isEqual:@"0123456789ABCDEFGHIJKL"], "URL query omitted");
        track->uriValue = @"spotify:local:artist:album:title:123";
        Require([[Read(track) objectForKey:@"trackID"] length] == 0, "local track is not fabricated as Spotify ID");
        track->uriValue = @"https://example.com/track/0123456789ABCDEFGHIJKL";
        Require([[Read(track) objectForKey:@"trackID"] length] == 0, "non-Spotify URL rejected");
        track->uriValue = @"spotify:track:short";
        Require([[Read(track) objectForKey:@"trackID"] length] == 0, "malformed ID rejected");
        track->uriValue = [[[CGDFixtureURL alloc] init] autorelease];
        Require([[Read(track) objectForKey:@"trackID"] isEqual:@"0123456789ABCDEFGHIJKL"], "SPTURL getter supported");
        track->metadataValue = @[@"not-a-dictionary"];
        Require([[Read(track) objectForKey:@"album"] length] == 0, "wrong metadata type handled");

        CGDScalarTitle *scalar = [[[CGDScalarTitle alloc] init] autorelease];
        Require([[Read(scalar) objectForKey:@"title"] isEqual:@"Safe fallback"], "scalar getter skipped");
        Require(!scalarCalled, "wrong ABI getter never invoked");
        CGDThrowingTrack *throwing = [[[CGDThrowingTrack alloc] init] autorelease];
        NSDictionary *thrown = Read(throwing);
        Require([[thrown objectForKey:@"title"] length] == 0, "getter exception handled");
        Require([[thrown description] rangeOfString:@"sensitive-reason"].location == NSNotFound,
                "exception reason excluded");
        Require([[thrown description] rangeOfString:@"FixtureException"].location != NSNotFound,
                "exception name retained for diagnosis");

        CGDFixturePlayer *changing = [[[CGDFixturePlayer alloc] init] autorelease];
        changing->firstTrack = track;
        changing->laterTrack = scalar;
        changing->changing = YES;
        NSDictionary *changed = CGDReadTrackSnapshot(changing);
        for (NSString *key in @[@"title", @"artist", @"album", @"trackID"]) {
            Require([[changed objectForKey:key] length] == 0, "track change clears entire result");
        }
        Require([[changed objectForKey:@"artists"] count] == 0, "track change also clears artist array");
        Require([[CGDReadTrackSnapshot(nil) objectForKey:@"title"] length] == 0, "missing player handled");
        Require([[CGDReadTrackSnapshot([NSObject new]) objectForKey:@"title"] length] == 0,
                "player without currentTrack handled");
        [track release];
        printf("PASS: %u TrackReader assertions (GNUstep host runtime).\n", checks);
    }
    return 0;
}
