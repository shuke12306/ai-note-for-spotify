#import <UIKit/UIKit.h>

@interface CGDPlaybackTheme : NSObject
@property(nonatomic, copy) NSArray<UIColor *> *colors;
@property(nonatomic, readonly) UIColor *cardColor;
@property(nonatomic, strong) UIColor *navigationTextColor;
@property(nonatomic) BOOL dark;
@end

// One bounded inspection of the captured playback page, only when opening the
// guide. Uses known background views and public UIKit/Core Animation properties.
CGDPlaybackTheme *CGDReadPlaybackTheme(UIViewController *page);
UIView *CGDThemeBackground(CGDPlaybackTheme *theme, CGRect frame);

extern NSNotificationName const CGDCardAppearanceDidChangeNotification;
CGFloat CGDCardBrightness(void);
void CGDPreviewCardBrightness(CGFloat value);
void CGDSaveCardBrightness(void);
UIColor *CGDResolvedCardColor(CGDPlaybackTheme *theme, UITraitCollection *traits);
UIColor *CGDReadableCardText(UIColor *background, BOOL secondary);
UIUserInterfaceStyle CGDCardInterfaceStyle(UIColor *background);
