#import <Foundation/Foundation.h>

NSArray<NSDictionary *> *CGDGuideLanguageOptions(void);
NSDictionary *CGDLoadGuideLanguage(void);
NSString *CGDGuideLanguageName(NSDictionary *selection);
// Returns an error without changing the saved value if validation fails.
NSString *CGDSaveGuideLanguage(NSString *code, NSString *customName);
