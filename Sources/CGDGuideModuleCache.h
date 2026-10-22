#import <Foundation/Foundation.h>

// One bounded group per track/model/language; every module owns its prompt key.
// Confined to the guide service queue, like the legacy whole-guide cache.
@interface CGDGuideModuleCache : NSObject {
    NSString *_path;
    NSMutableDictionary *_entries;
}
- (instancetype)initWithPath:(NSString *)path;
- (NSDictionary *)entryForTrack:(NSString *)trackKey module:(NSString *)module key:(NSString *)key;
- (NSString *)storeEntries:(NSDictionary *)entries forTrack:(NSString *)trackKey;
- (NSString *)clear;
@end
