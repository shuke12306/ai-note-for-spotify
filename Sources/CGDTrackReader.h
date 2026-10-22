#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Compact encoding: return type, self, selector, then explicit arguments.
BOOL CGDMethodMatches(Class cls, SEL selector, const char *expected);

// Returns a new immutable snapshot. Never retains a Spotify player/track in it.
// Fields: title, artist (display text), album, trackID; missing strings are empty.
// artists contains separately supplied track artist names, or an empty array.
// Diagnostics: status, notes, metadataKeys, playerClass, trackClass.
NSDictionary *CGDReadTrackSnapshot(id player);
