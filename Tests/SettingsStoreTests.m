#import "CGDSettingsStore.h"
#import <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

#define CGD_FAKE_CONSTANT(name) const void *const name = @#name
CGD_FAKE_CONSTANT(kSecClass);
CGD_FAKE_CONSTANT(kSecClassGenericPassword);
CGD_FAKE_CONSTANT(kSecAttrService);
CGD_FAKE_CONSTANT(kSecAttrAccount);
CGD_FAKE_CONSTANT(kSecAttrSynchronizable);
CGD_FAKE_CONSTANT(kSecMatchLimit);
CGD_FAKE_CONSTANT(kSecMatchLimitOne);
CGD_FAKE_CONSTANT(kSecReturnData);
CGD_FAKE_CONSTANT(kSecValueData);
CGD_FAKE_CONSTANT(kSecAttrAccessible);
CGD_FAKE_CONSTANT(kSecAttrAccessibleWhenUnlockedThisDeviceOnly);

static unsigned int checks;
static NSUInteger writes, reads;
static NSData *savedKey;
static OSStatus forcedWriteError, forcedAddError, forcedReadError, forcedDeleteError;

static void Require(BOOL condition, const char *label) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", label); exit(1); }
}
static void Scope(NSDictionary *query) {
    Require([[query objectForKey:(id)kSecClass] isEqual:(id)kSecClassGenericPassword] &&
        [[query objectForKey:(id)kSecAttrService] isEqual:@"com.classicalguide.deepseek"] &&
        [[query objectForKey:(id)kSecAttrAccount] isEqual:@"api-key"] &&
        [[query objectForKey:(id)kSecAttrSynchronizable] isEqual:@(NO)],
        "Every operation is scoped to the plugin's local password item");
}
static void AcceptData(NSDictionary *attributes) {
    Require([[attributes objectForKey:(id)kSecAttrAccessible]
        isEqual:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly], "Device-only unlocked accessibility");
    id data = [attributes objectForKey:(id)kSecValueData];
    Require([data isKindOfClass:NSData.class], "Key is stored as password bytes");
    savedKey = [data copy];
}
OSStatus SecItemCopyMatching(CFDictionaryRef raw, CFTypeRef *result) {
    NSDictionary *query = (id)raw;
    reads++;
    Scope(query);
    BOOL wantsData = [[query objectForKey:(id)kSecReturnData] boolValue];
    Require(wantsData ? result != NULL : result == NULL,
        "Only explicit network credential reads request secret data");
    if (forcedReadError) return forcedReadError;
    if (savedKey && wantsData) *result = (CFTypeRef)[savedKey retain];
    return savedKey ? errSecSuccess : errSecItemNotFound;
}
OSStatus SecItemUpdate(CFDictionaryRef raw, CFDictionaryRef attributes) {
    writes++;
    Scope((id)raw);
    if (forcedWriteError) return forcedWriteError;
    if (!savedKey) return errSecItemNotFound;
    AcceptData((id)attributes);
    return errSecSuccess;
}
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    (void)result;
    writes++;
    Scope((id)attributes);
    if (forcedWriteError) return forcedWriteError;
    if (forcedAddError) return forcedAddError;
    if (savedKey) return errSecDuplicateItem;
    AcceptData((id)attributes);
    return errSecSuccess;
}
OSStatus SecItemDelete(CFDictionaryRef query) {
    Scope((id)query);
    if (forcedDeleteError) return forcedDeleteError;
    if (!savedKey) return errSecItemNotFound;
    savedKey = nil;
    return errSecSuccess;
}

int main(void) {
    @autoreleasepool {
        NSString *preference = @"CGDClassicalGuide.DeepSeekModel";
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id prior = [[defaults objectForKey:preference] copy];
        [defaults removeObjectForKey:preference];
        Require([CGDSettingsModelName() isEqual:@"deepseek-flash"], "Planned model default");
        Require(CGDSettingsKeyStatus() == errSecItemNotFound, "Missing key status");
        Require(CGDSettingsSave(@"  custom-model  ", @"") == nil, "Model-only save succeeds");
        Require([CGDSettingsModelName() isEqual:@"custom-model"] && writes == 0, "Empty key does not write Keychain");
        NSString *fakeKey = @"sk-TEST-fixture-only-123";
        Require(CGDSettingsSave(@"custom-model", fakeKey) == nil, "First key save adds missing item");
        Require(writes == 2 && [savedKey isEqual:[fakeKey dataUsingEncoding:NSUTF8StringEncoding]], "Update-then-add saved correct bytes");
        Require(CGDSettingsKeyStatus() == errSecSuccess, "Saved key existence");
        Require([CGDSettingsKeyStatusText(errSecSuccess) rangeOfString:fakeKey].location == NSNotFound, "Status does not reveal secret");
        Require([[defaults objectForKey:preference] isEqual:@"custom-model"], "Ordinary preferences contain model only");
        NSUInteger before = writes;
        Require(CGDSettingsSave(@"model-2", @" \n ") == nil && writes == before, "Whitespace input retains key");
        Require([savedKey isEqual:[fakeKey dataUsingEncoding:NSUTF8StringEncoding]], "Existing secret is preserved");
        Require(CGDSettingsSave(@"model-2", @"  replacement-key  ") == nil && writes == before + 1, "Replacement updates one item");
        Require([savedKey isEqual:[@"replacement-key" dataUsingEncoding:NSUTF8StringEncoding]], "Trimmed replacement bytes");
        before = writes;
        Require(CGDSettingsSave(@"", fakeKey) != nil && writes == before, "Invalid model rejected before secret mutation");
        Require(CGDSettingsSave(@"bad model", fakeKey) != nil, "Model with internal space rejected");
        Require(CGDSettingsSave(@"model-3", @"bad\nkey") != nil, "Multiline key rejected");
        Require(CGDSettingsSave(@"model-3", @"中文密钥") != nil, "Accidental non-key paste rejected");
        Require(writes == before && [CGDSettingsModelName() isEqual:@"model-2"], "Validation failures preserve old configuration");
        forcedWriteError = errSecMissingEntitlement;
        NSString *error = CGDSettingsSave(@"model-3", fakeKey);
        Require(error != nil && [error rangeOfString:fakeKey].location == NSNotFound, "Permission failure safely reported");
        Require([CGDSettingsModelName() isEqual:@"model-2"] &&
            [savedKey isEqual:[@"replacement-key" dataUsingEncoding:NSUTF8StringEncoding]], "Failed update does not erase old key or commit new model");
        forcedWriteError = 0;
        forcedReadError = errSecInteractionNotAllowed;
        Require(CGDSettingsKeyStatus() == errSecInteractionNotAllowed, "Locked Keychain is not reported as missing");
        Require([CGDSettingsKeyStatusText(errSecInteractionNotAllowed) rangeOfString:@"解锁"].location != NSNotFound, "Actionable locked status");
        forcedReadError = 0;
        forcedDeleteError = errSecMissingEntitlement;
        Require(CGDSettingsDeleteKey() != nil && savedKey != nil, "Failed delete retains secret");
        forcedDeleteError = 0;
        Require(CGDSettingsDeleteKey() == nil && savedKey == nil, "Explicit delete removes plugin key");
        Require(CGDSettingsDeleteKey() == nil, "Deleting missing key is idempotent");
        Require([CGDSettingsModelName() isEqual:@"model-2"], "Deleting key keeps model");
        forcedAddError = errSecMissingEntitlement;
        Require(CGDSettingsSave(@"model-3", fakeKey) != nil, "First-time insertion failure reported");
        Require(savedKey == nil && [CGDSettingsModelName() isEqual:@"model-2"], "Failed insertion has no plaintext fallback or partial model commit");
        forcedAddError = 0;
        [defaults setObject:@123 forKey:preference];
        Require([CGDSettingsModelName() isEqual:@"deepseek-flash"], "Corrupt stored model falls back safely");
        Require(reads == 3, "Only explicit existence checks read Keychain");
        NSString *readError = nil;
        Require(CGDSettingsReadAPIKey(&readError) == nil && [readError rangeOfString:@"尚未配置"].location != NSNotFound, "Missing key has actionable network error");
        Require(CGDSettingsSave(@"deepseek-flash", fakeKey) == nil, "Prepare credential-read fixture");
        Require([CGDSettingsReadAPIKey(&readError) isEqual:fakeKey] && readError == nil, "Network reader obtains exact key bytes");
        forcedReadError = errSecInteractionNotAllowed;
        Require(CGDSettingsReadAPIKey(&readError) == nil && [readError rangeOfString:@"解锁"].location != NSNotFound, "Locked credential cannot start request");
        forcedReadError = 0;
        savedKey = [@"invalid\nkey" dataUsingEncoding:NSUTF8StringEncoding];
        Require(CGDSettingsReadAPIKey(&readError) == nil && readError != nil, "Corrupt stored secret cannot become an HTTP header");
        if (prior) [defaults setObject:prior forKey:preference];
        else [defaults removeObjectForKey:preference];
        printf("PASS: %u SettingsStore assertions (real storage logic; simulated Security API).\n", checks);
    }
    return 0;
}
