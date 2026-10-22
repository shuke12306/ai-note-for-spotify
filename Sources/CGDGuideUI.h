#import <UIKit/UIKit.h>

// Uses only the already captured page and its presentation chain; no page scan.
void CGDPresentGuide(UIViewController *page);
// Isolated appearance for plugin sheets, including their pushed settings pages.
UINavigationController *CGDMakeNavigationController(UIViewController *root);
