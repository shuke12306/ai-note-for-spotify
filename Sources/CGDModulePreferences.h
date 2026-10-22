#import <Foundation/Foundation.h>

NSArray<NSString *> *CGDGuideModuleIDs(void);
NSString *CGDGuideModuleTitle(NSString *identifier);
// One preferences value holds both order and hidden IDs, independent of API settings.
NSDictionary *CGDLoadModuleLayout(void);
void CGDSaveModuleLayout(NSArray *order, NSArray *hidden);
