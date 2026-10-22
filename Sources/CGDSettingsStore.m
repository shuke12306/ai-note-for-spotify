#import "CGDSettingsStore.h"
#import <Security/Security.h>

static NSString *const CGDModelPreference = @"CGDClassicalGuide.DeepSeekModel";
static NSString *const CGDDefaultModel = @"deepseek-flash";

static NSDictionary *CGDKeyQuery(void) {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.classicalguide.deepseek",
        (__bridge id)kSecAttrAccount: @"api-key",
        (__bridge id)kSecAttrSynchronizable: @(NO),
    };
}

static NSString *CGDStorageError(OSStatus status) {
    if (status == errSecSuccess) return nil;
    if (status == errSecInteractionNotAllowed) return @"钥匙串暂不可访问，请解锁手机后重试。";
    if (status == errSecMissingEntitlement) return @"当前注入环境没有可用的钥匙串权限，密钥未保存。请反馈此提示。";
    return [NSString stringWithFormat:@"钥匙串操作失败（%ld），请重试。", (long)status];
}

static NSString *CGDNormalizeModel(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *model = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!model.length || model.length > 128) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-:/"];
    return [model rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? model : nil;
}

NSString *CGDSettingsModelName(void) {
    return CGDNormalizeModel([NSUserDefaults.standardUserDefaults objectForKey:CGDModelPreference]) ?: CGDDefaultModel;
}

NSInteger CGDSettingsKeyStatus(void) {
    NSMutableDictionary *query = [CGDKeyQuery() mutableCopy];
    [query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    // Existence check only: never request the stored password bytes for a label.
    [query setObject:@(NO) forKey:(__bridge id)kSecReturnData];
    return SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
}

NSString *CGDSettingsKeyStatusText(NSInteger status) {
    if (status == errSecSuccess) return @"API Key：已保存在本机钥匙串";
    if (status == errSecItemNotFound) return @"API Key：未配置，生成新导赏前请先填写并保存";
    return CGDStorageError((OSStatus)status);
}

NSString *CGDSettingsSave(NSString *model, NSString *replacementKey) {
    NSString *normalized = CGDNormalizeModel(model);
    if (!normalized) return @"模型名需为 1–128 位字母、数字或 . _ - : /，不能含空格。";
    NSString *key = [replacementKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (key.length) {
        if (key.length > 512) return @"API Key 过长，请检查是否误粘贴了其他内容。";
        for (NSUInteger i = 0; i < key.length; i++) {
            unichar ch = [key characterAtIndex:i];
            if (ch < 33 || ch > 126) return @"API Key 含空白或非英文字符，请检查复制的内容。";
        }
        NSDictionary *attributes = @{
            (__bridge id)kSecValueData: [key dataUsingEncoding:NSUTF8StringEncoding],
            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        };
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)CGDKeyQuery(),
                                       (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [CGDKeyQuery() mutableCopy];
            [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
        if (status != errSecSuccess) return CGDStorageError(status);
    }
    // Empty input retains the existing key. Model changes commit only after a
    // requested key update succeeds; errors never fall back to plaintext storage.
    [NSUserDefaults.standardUserDefaults setObject:normalized forKey:CGDModelPreference];
    return nil;
}

NSString *CGDSettingsDeleteKey(void) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)CGDKeyQuery());
    return status == errSecItemNotFound ? nil : CGDStorageError(status);
}

NSString *CGDSettingsReadAPIKey(NSString **failure) {
    if (failure) *failure = nil;
    NSMutableDictionary *query = [CGDKeyQuery() mutableCopy];
    [query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    [query setObject:@(YES) forKey:(__bridge id)kSecReturnData];
    CFTypeRef raw = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &raw);
#if __has_feature(objc_arc)
    id data = CFBridgingRelease(raw);
#else
    id data = [(id)raw autorelease];
#endif
    NSString *error = status == errSecItemNotFound ? @"尚未配置 API Key，请在右上角设置中填写并保存，再点击重试。" : CGDStorageError(status);
    NSString *key = !error && [data isKindOfClass:NSData.class] ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!error) {
        BOOL valid = key.length > 0 && key.length <= 512;
        for (NSUInteger i = 0; valid && i < key.length; i++) {
            unichar ch = [key characterAtIndex:i];
            valid = ch >= 33 && ch <= 126;
        }
        if (!valid) error = @"已保存的 API Key 格式异常，请在设置中重新保存密钥。";
    }
    if (failure) *failure = error;
    return error ? nil : key;
}
