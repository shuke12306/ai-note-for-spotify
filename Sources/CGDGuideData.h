#import <Foundation/Foundation.h>
#import "CGDGuidePrompts.h"

extern NSString *const CGDPromptVersion;
NSString *CGDGuideSystemPrompt(NSString *language);
NSString *CGDGuideSystemPromptForModule(NSString *language, NSDictionary *prompts, NSString *module);
NSDictionary *CGDGuideRequestBody(NSDictionary *snapshot, NSString *model, NSString *language);
NSDictionary *CGDGuideRequestBodyForModule(NSDictionary *snapshot, NSString *model, NSString *language, NSDictionary *prompts, NSString *module);
NSArray *CGDNormalizeRequestedModules(id modules);
NSDictionary *CGDGuideRequestBodyForModules(NSDictionary *snapshot, NSString *model, NSString *language, NSDictionary *prompts, NSArray *modules);
NSData *CGDGuideTrackIdentity(NSDictionary *snapshot, NSString *model, NSString *language);
NSData *CGDGuideModuleIdentity(NSDictionary *snapshot, NSString *model, NSString *language, NSDictionary *prompts, NSString *module);
NSDictionary *CGDEmptyGuide(NSDictionary *snapshot);
NSDictionary *CGDValidateGuideModule(id partial, NSString *module);
NSDictionary *CGDParseGuideModulesResponse(NSData *data, NSInteger status, NSDictionary *snapshot, NSArray *modules, NSDictionary **failures);
NSDictionary *CGDPlanGuideModules(NSArray *modules, NSDictionary *cachedEntries, NSSet *runningModules, BOOL force);
NSDictionary *CGDPlanGuideModulesRetrying(NSArray *modules, NSDictionary *cachedEntries, NSSet *runningModules, NSArray *failedModules, BOOL force);
NSDictionary *CGDRestoreGuideModuleEvent(NSString *module, NSDictionary *previous, NSDictionary *current);
NSString *CGDGuideModuleText(NSDictionary *guide, NSString *module);
NSString *CGDGuidePlainText(NSDictionary *snapshot, NSDictionary *event);
NSData *CGDGuideIdentity(NSDictionary *snapshot, NSString *model, NSString *language);
NSData *CGDGuideIdentityWithPrompts(NSDictionary *snapshot, NSString *model, NSString *language, NSDictionary *prompts);
NSDictionary *CGDValidateGuide(id value);
NSDictionary *CGDParseGuideResponse(NSData *data, NSInteger status, NSDictionary *snapshot, NSString **failure);
NSDictionary *CGDParseGuideModuleResponse(NSData *data, NSInteger status, NSDictionary *snapshot, NSString *module, NSString **failure);
NSDictionary *CGDMergeGuideModule(NSDictionary *guide, NSDictionary *partial, NSString *module);
NSString *CGDGuideHTTPError(NSInteger status);
