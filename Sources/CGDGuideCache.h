#import <Foundation/Foundation.h>

// All methods are confined to the guide service's serial queue.
@interface CGDGuideCache : NSObject {
    NSString *_path;
    NSMutableDictionary *_entries;
}
- (instancetype)initWithPath:(NSString *)path;
- (NSDictionary *)entryForKey:(NSString *)key;
- (NSString *)storeGuide:(NSDictionary *)guide key:(NSString *)key date:(NSDate *)date;
- (NSString *)clear;
@end
