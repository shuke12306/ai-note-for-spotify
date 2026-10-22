#import <Foundation/Foundation.h>

extern NSUInteger const CGDGuidePromptLimit;
NSArray *CGDPromptModuleIDs(void);
NSString *CGDPromptModuleTitle(NSString *module);
NSString *CGDPromptModuleField(NSString *module);
NSString *CGDDefaultModulePrompt(NSString *module);
NSDictionary *CGDNormalizeGuidePrompts(id prompts);
// A known old configuration candidate; callers must verify its full cache key.
NSDictionary *CGDGuidePromptsBefore050(NSDictionary *prompts);
NSDictionary *CGDLoadGuidePrompts(void);
NSString *CGDSaveModulePrompt(NSString *module, NSString *text);
void CGDResetModulePrompt(NSString *module);
