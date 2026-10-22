#import <Foundation/Foundation.h>

// Synchronous storage calls run on background service/settings queues.
// No secret is returned to the UI or included in diagnostics.
NSString *CGDSettingsModelName(void);
NSInteger CGDSettingsKeyStatus(void);
NSString *CGDSettingsKeyStatusText(NSInteger status);
NSString *CGDSettingsSave(NSString *model, NSString *replacementKey);
NSString *CGDSettingsDeleteKey(void);
// Only the network service reads the secret; the UI only checks existence.
NSString *CGDSettingsReadAPIKey(NSString **failure);
