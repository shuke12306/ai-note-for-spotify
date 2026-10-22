// Host-only Security API double. Never included by the iOS build.
#import <Foundation/Foundation.h>
#include <stdint.h>

typedef int32_t OSStatus;
typedef const void *CFDictionaryRef;
typedef const void *CFTypeRef;
enum {
    errSecSuccess = 0, errSecDuplicateItem = -25299, errSecItemNotFound = -25300,
    errSecInteractionNotAllowed = -25308, errSecMissingEntitlement = -34018,
};
extern const void *const kSecClass;
extern const void *const kSecClassGenericPassword;
extern const void *const kSecAttrService;
extern const void *const kSecAttrAccount;
extern const void *const kSecAttrSynchronizable;
extern const void *const kSecMatchLimit;
extern const void *const kSecMatchLimitOne;
extern const void *const kSecReturnData;
extern const void *const kSecValueData;
extern const void *const kSecAttrAccessible;
extern const void *const kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes);
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemDelete(CFDictionaryRef query);
