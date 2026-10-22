#include "CGDEntryPlacement.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int checks;
static void Require(bool value, const char *message) {
    checks++; if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static bool Equal(CGDEntryRect a, CGDEntryRect b) {
    return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;
}
int main(void) {
    CGDEntryRect safe = {0, 59, 393, 759}, info = {24, 564, 270, 48};
    CGDEntryRect cover = {24, 145, 345, 345}, empty = {0}, frame = {0};
    CGDEntryPosition mode = CGDPlaceEntry(safe, info, cover, 369, 78, 44, &frame);
    Require(mode == CGDEntryBelowCover, "Static artwork keeps its existing below-cover entry");
    Require(frame.y >= 490 && frame.y + frame.height <= info.y - 4, "Static tap target fits between artwork and title");
    Require(frame.x + frame.width == 375, "Static entry retains right-edge alignment");
    CGDEntryRect staticFrame = frame;
    mode = CGDPlaceEntry(safe, info, empty, 369, 78, 44, &frame);
    Require(mode == CGDEntryAboveTrack, "No large cover still produces an entry for video layout");
    Require(frame.y == info.y - 56 && frame.y + frame.height == info.y - 12, "Video entry sits above track information with breathing room");
    Require(frame.width >= 44 && frame.height >= 44, "Subtle icon preserves a full-size tap target");
    CGDEntryRect videoFrame = frame;
    CGDEntryRect thumbnail = {24, 564, 48, 48};
    Require(CGDPlaceEntry(safe, info, thumbnail, 369, 78, 44, &frame) == CGDEntryAboveTrack && Equal(frame, videoFrame), "Small thumbnail cannot be mistaken for a large cover");
    CGDEntryRect video = {0, 0, 393, 852};
    Require(CGDPlaceEntry(safe, info, video, 369, 78, 44, &frame) == CGDEntryAboveTrack, "Fullscreen video bounds cannot replace the large cover anchor");
    Require(CGDPlaceEntry(safe, info, cover, 369, 78, 44, &frame) == CGDEntryBelowCover && Equal(frame, staticFrame), "Static-video-static transition does not retain stale placement");
    CGDEntryRect moved = info; moved.y -= 80;
    CGDPlaceEntry(safe, moved, empty, 369, 78, 44, &frame);
    Require(frame.y == videoFrame.y - 80, "Video entry follows the track when scrolling");
    moved.y = 130;
    Require(CGDPlaceEntry(safe, moved, empty, 369, 78, 44, &frame) == CGDEntryHidden, "Scrolling into header hides the entry instead of covering native buttons");
    moved.y = 830;
    Require(CGDPlaceEntry(safe, moved, empty, 369, 78, 44, &frame) == CGDEntryHidden, "Offscreen title cannot leave a stale tap target behind");
    moved = info; moved.y = 530;
    Require(CGDPlaceEntry(safe, moved, cover, 369, 78, 44, &frame) == CGDEntryHidden, "Tight static gap does not overlay artwork or title");
    Require(CGDPlaceEntry(safe, empty, empty, 369, 78, 44, &frame) == CGDEntryHidden, "Missing information anchor fails closed");
    moved = info; moved.x = 500;
    Require(CGDPlaceEntry(safe, moved, empty, 369, 78, 44, &frame) == CGDEntryHidden, "Horizontal page transition hides an offscreen anchor");
    moved = info; moved.y = NAN;
    Require(CGDPlaceEntry(safe, moved, empty, 369, 78, 44, &frame) == CGDEntryHidden, "Nonfinite layout does not create an invalid frame");
    Require(CGDPlaceEntry(safe, info, empty, 369, 120, 52, &frame) == CGDEntryAboveTrack && frame.height == 52 && frame.y + 52 < info.y, "Larger text remains clear of title");
    CGDEntryRect landscape = {59, 0, 700, 360};
    CGDEntryRect landscapeInfo = {430, 250, 260, 50};
    Require(CGDPlaceEntry(landscape, landscapeInfo, empty, 730, 90, 44, &frame) == CGDEntryAboveTrack && frame.x >= 59 && frame.x + 90 <= 759, "Landscape placement respects horizontal safe area");
    Require(CGDPlaceEntry(safe, info, empty, 369, 410, 44, &frame) == CGDEntryHidden, "Oversized target is hidden instead of overflowing the screen");
    printf("PASS: %u entry placement assertions (static/video, transitions, scroll and safe areas).\n", checks);
    return 0;
}
