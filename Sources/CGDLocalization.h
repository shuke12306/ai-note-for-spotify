#import <Foundation/Foundation.h>

// UI-only preference. Never use this value in AI requests or cache identities.
NSString *CGDInterfaceLanguage(void);
BOOL CGDSaveInterfaceLanguage(NSString *code);
extern NSString *const CGDInterfaceLanguageDidChangeNotification;
NSString *CGDL(NSString *key);
// Relocalize plugin-owned status/error text, including already formatted values.
// Do not pass track metadata, generated content or editable prompts here.
NSString *CGDLocalizedMessage(NSString *message);
NSDictionary *CGDLocalizationCatalog(void);
NSString *CGDGuideLanguageDisplayName(NSDictionary *selection);
