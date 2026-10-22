#import "CGDPlaybackTheme.h"
#import "CGDAdapter.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@implementation CGDPlaybackTheme
- (UIColor *)cardColor { return CGDResolvedCardColor(self, UITraitCollection.currentTraitCollection); }
@end

NSNotificationName const CGDCardAppearanceDidChangeNotification = @"CGDClassicalGuide.CardAppearanceDidChange";
static NSString *const CGDCardBrightnessKey = @"CGDClassicalGuide.CardBrightness";
static CGFloat CGDCurrentCardBrightness = .65;
static CGFloat CGDLastSavedCardBrightness = .65;

CGFloat CGDCardBrightness(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:CGDCardBrightnessKey];
        if ([stored isKindOfClass:NSNumber.class] && isfinite([stored doubleValue])) {
            CGDCurrentCardBrightness = MIN(1, MAX(0, [stored doubleValue]));
        }
        CGDLastSavedCardBrightness = CGDCurrentCardBrightness;
    });
    return CGDCurrentCardBrightness;
}

void CGDPreviewCardBrightness(CGFloat value) {
    if (!NSThread.isMainThread || !isfinite(value)) return;
    CGFloat previous = CGDCardBrightness();
    value = MIN(1, MAX(0, value));
    if (fabs(previous - value) < .001) return;
    CGDCurrentCardBrightness = value;
    [NSNotificationCenter.defaultCenter postNotificationName:CGDCardAppearanceDidChangeNotification object:nil];
}

void CGDSaveCardBrightness(void) {
    CGFloat current = CGDCardBrightness();
    if (current == CGDLastSavedCardBrightness) return;
    [NSUserDefaults.standardUserDefaults setDouble:current forKey:CGDCardBrightnessKey];
    CGDLastSavedCardBrightness = current;
}

static double CGDLinear(double value) {
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}
static double CGDLuminance(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return .2126 * CGDLinear(r) + .7152 * CGDLinear(g) + .0722 * CGDLinear(b);
}
static UIColor *CGDBlend(UIColor *color, CGFloat neutral, CGFloat fraction) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:r * (1 - fraction) + neutral * fraction
        green:g * (1 - fraction) + neutral * fraction
        blue:b * (1 - fraction) + neutral * fraction alpha:1];
}

UIColor *CGDResolvedCardColor(CGDPlaybackTheme *theme, UITraitCollection *traits) {
    UIColor *base = theme.colors.firstObject ?: [UIColor.secondarySystemGroupedBackgroundColor resolvedColorWithTraitCollection:traits];
    CGFloat value = CGDCardBrightness();
    // At 0 use the old darkening; at 60 keep the cover color; above it tint
    // toward white. The default 65 is slightly lighter than the sampled color.
    return value <= .6 ? CGDBlend(base, 0, .72 * (1 - value / .6)) :
        CGDBlend(base, 1, .72 * (value - .6) / .4);
}

UIUserInterfaceStyle CGDCardInterfaceStyle(UIColor *background) {
    return CGDLuminance(background) < .179 ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}

UIColor *CGDReadableCardText(UIColor *background, BOOL secondary) {
    double luminance = CGDLuminance(background);
    CGFloat foreground = CGDCardInterfaceStyle(background) == UIUserInterfaceStyleDark ? 1 : 0;
    // Keep secondary text slightly softer when contrast permits; never rely on
    // the host's translucent gray text over an arbitrary cover-derived color.
    for (CGFloat amount = secondary ? .8 : 1; amount <= 1.001; amount += .05) {
        UIColor *candidate = CGDBlend(background, foreground, MIN(1, amount));
        double other = CGDLuminance(candidate);
        if ((fmax(other, luminance) + .05) / (fmin(other, luminance) + .05) >= 4.5) return candidate;
    }
    return foreground ? UIColor.whiteColor : UIColor.blackColor;
}

// Rendering only a verified background surface avoids sampling album art,
// account text or the floating guide button. Nothing is saved or transmitted.
static NSArray<UIColor *> *CGDSampleBackground(UIView *view) {
    const size_t width = 12, height = 64;
    if (CGRectIsEmpty(view.bounds) || !isfinite(view.bounds.size.width) || !isfinite(view.bounds.size.height)) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = NO;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // Composite a known opaque ancestor fill if this gradient is translucent.
        UIView *ancestor = view.superview;
        for (NSUInteger i = 0; ancestor && i < 12; i++, ancestor = ancestor.superview) {
            UIColor *base = [ancestor.backgroundColor resolvedColorWithTraitCollection:view.traitCollection];
            if (base && CGColorGetAlpha(base.CGColor) > .99) {
                [base setFill];
                CGContextFillRect(context.CGContext, CGRectMake(0, 0, width, height));
                break;
            }
        }
        CGContextScaleCTM(context.CGContext, width / view.bounds.size.width, height / view.bounds.size.height);
        CGContextTranslateCTM(context.CGContext, -view.bounds.origin.x, -view.bounds.origin.y);
        CALayer *layer = view.layer.presentationLayer ?: view.layer;
        [layer renderInContext:context.CGContext];
    }];
    if (!image.CGImage) return nil;
    unsigned char pixels[12 * 64 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image.CGImage);
    CGContextRelease(bitmap);
    NSMutableArray *colors = [NSMutableArray array];
    for (NSUInteger band = 0; band < 5; band++) {
        NSUInteger row = band * (height - 1) / 4;
        double r = 0, g = 0, b = 0;
        for (NSUInteger x = 3; x < 9; x++) {
            const unsigned char *pixel = pixels + (row * width + x) * 4;
            if (pixel[3] < 245) return nil;
            r += (double)pixel[0] / pixel[3];
            g += (double)pixel[1] / pixel[3];
            b += (double)pixel[2] / pixel[3];
        }
        [colors addObject:[UIColor colorWithRed:r / 6 green:g / 6 blue:b / 6 alpha:1]];
    }
    return colors;
}

static BOOL CGDIsNamedClass(id object, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}

CGDPlaybackTheme *CGDReadPlaybackTheme(UIViewController *page) {
    if (!NSThread.isMainThread || !page.viewIfLoaded.window) return nil;
    @try {
        UIView *root = page.viewIfLoaded;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
        NSMutableArray<UIView *> *candidates = [NSMutableArray array];
        // Captured page only; no window scan, polling, new hook, or private getter.
        for (NSUInteger i = 0; i < queue.count && i < 384; i++) {
            UIView *view = queue[i];
            if (view.hidden || view.alpha < .95 || view.window != root.window) continue;
            BOOL background = CGDIsNamedClass(view.nextResponder, @"NowPlaying_ScrollImpl.NPVBackgroundV2ViewController");
            BOOL gradient = CGDIsNamedClass(view, @"NowPlaying_ScrollImpl.NPVGradientView");
            if ((background || gradient) && view.bounds.size.width >= root.bounds.size.width * .7 &&
                view.bounds.size.height >= root.bounds.size.height * .5) {
                if (background) [candidates insertObject:view atIndex:0];
                else [candidates addObject:view];
            }
            if (queue.count < 384) {
                NSUInteger remaining = 384 - queue.count;
                NSArray *children = view.subviews;
                [queue addObjectsFromArray:[children subarrayWithRange:NSMakeRange(0, MIN(remaining, children.count))]];
            }
        }
        for (NSUInteger index = 0; index < MIN((NSUInteger)3, candidates.count); index++) {
            UIView *view = candidates[index];
            NSArray<UIColor *> *colors = CGDSampleBackground(view);
            if (!colors.count) continue;
            CGDPlaybackTheme *theme = [[CGDPlaybackTheme alloc] init];
            theme.colors = colors;
            double whiteContrast = 100, blackContrast = 100;
            for (UIColor *color in colors) {
                double luminance = CGDLuminance(color);
                whiteContrast = fmin(whiteContrast, 1.05 / (luminance + .05));
                blackContrast = fmin(blackContrast, (luminance + .05) / .05);
            }
            theme.dark = whiteContrast >= blackContrast;
            UIColor *top = colors.firstObject;
            theme.navigationTextColor = CGDLuminance(top) < .179 ? UIColor.whiteColor : UIColor.blackColor;
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [top getRed:&r green:&g blue:&b alpha:&a];
            [[CGDAdapter shared] setHookState:[NSString stringWithFormat:@"已读取 %@ · 顶部 #%02X%02X%02X · 5 段渐变",
                NSStringFromClass(view.class), (unsigned int)lround(r * 255), (unsigned int)lround(g * 255),
                (unsigned int)lround(b * 255)] forKey:@"播放页配色"];
            return theme;
        }
        [[CGDAdapter shared] setHookState:@"未取得可用的背景色，使用默认配色" forKey:@"播放页配色"];
    } @catch (NSException *exception) {
        [[CGDAdapter shared] setHookState:[@"取色失败，使用默认配色：" stringByAppendingString:exception.name] forKey:@"播放页配色"];
    }
    return nil;
}

@interface CGDGradientBackground : UIView
@end
@implementation CGDGradientBackground
+ (Class)layerClass { return CAGradientLayer.class; }
@end

UIView *CGDThemeBackground(CGDPlaybackTheme *theme, CGRect frame) {
    CGDGradientBackground *background = [[CGDGradientBackground alloc] initWithFrame:frame];
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    background.userInteractionEnabled = NO;
    background.isAccessibilityElement = NO;
    CAGradientLayer *gradient = (CAGradientLayer *)background.layer;
    NSMutableArray *colors = [NSMutableArray array];
    for (UIColor *color in theme.colors) [colors addObject:(__bridge id)color.CGColor];
    gradient.colors = colors;
    gradient.startPoint = CGPointMake(.5, 0);
    gradient.endPoint = CGPointMake(.5, 1);
    return background;
}
