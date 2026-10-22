#import <Foundation/Foundation.h>

// Durable user-selected copies. Never evicted as part of cache maintenance.
@interface CGDGuideLibrary : NSObject {
    NSString *_path;
    NSMutableDictionary *_items;
    BOOL _loadFailed;
}
- (instancetype)initWithPath:(NSString *)path;
- (NSArray *)items;
- (NSString *)saveSnapshot:(NSDictionary *)snapshot event:(NSDictionary *)event;
- (NSString *)removeItem:(NSString *)identifier;
- (NSString *)loadError;
@end
