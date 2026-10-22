#ifndef CGD_ENTRY_PLACEMENT_H
#define CGD_ENTRY_PLACEMENT_H
#include <math.h>
#include <stdbool.h>

// UIKit-independent geometry shared by the actual entry and host regressions.
typedef struct { double x, y, width, height; } CGDEntryRect;
typedef enum { CGDEntryHidden, CGDEntryBelowCover, CGDEntryAboveTrack } CGDEntryPosition;
static inline bool CGDEntryValidRect(CGDEntryRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.width) && isfinite(r.height) && r.width > 0 && r.height > 0;
}
static inline CGDEntryPosition CGDPlaceEntry(CGDEntryRect safe, CGDEntryRect information,
    CGDEntryRect cover, double contentRight, double width, double height, CGDEntryRect *result) {
    if (!result || !CGDEntryValidRect(safe) || !CGDEntryValidRect(information) ||
        !isfinite(width) || !isfinite(height) || width < 44 || height < 44 ||
        information.y < safe.y || information.y >= safe.y + safe.height ||
        information.x >= safe.x + safe.width || information.x + information.width <= safe.x) return CGDEntryHidden;
    CGDEntryPosition position = CGDEntryAboveTrack;
    double y = information.y - height - 12;
    double right = fmin(isfinite(contentRight) ? contentRight + 6 : safe.x + safe.width - 18, safe.x + safe.width - 8);
    // Only an actual large cover can constrain the gap. A thumbnail alongside
    // the title, or a full-height video, is not a replacement for this anchor.
    bool largeCover = CGDEntryValidRect(cover) && cover.width >= safe.width * .5 &&
        cover.height >= cover.width * .75 && cover.height <= cover.width * 1.3;
    if (largeCover) {
        double top = cover.y + cover.height + 2;
        double bottom = information.y - 4;
        if (bottom - top < height) return CGDEntryHidden;
        y = top + fmin(6, (bottom - top - height) / 2);
        right = cover.x + cover.width + 6;
        position = CGDEntryBelowCover;
    }
    CGDEntryRect frame = {right - width, y, width, height};
    // Reserve the playback header, and keep the entire 44 pt hit target clear
    // of the title/controls and outside the home-indicator safe area.
    if (frame.x < safe.x || frame.x + width > safe.x + safe.width ||
        frame.y < safe.y + 60 || frame.y + height > safe.y + safe.height ||
        frame.y + height > information.y - 4) return CGDEntryHidden;
    *result = frame;
    return position;
}
#endif
