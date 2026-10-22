#import <Foundation/Foundation.h>

// Completion always arrives on the main queue. Events contain only validated
// content and safe status text, never a key, headers, or raw response body.
typedef void (^CGDGuideCompletion)(NSDictionary *event);
@interface CGDGuideService : NSObject
+ (instancetype)shared;
- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot force:(BOOL)force completion:(CGDGuideCompletion)completion;
- (NSUUID *)requestSnapshot:(NSDictionary *)snapshot modules:(NSArray *)modules force:(BOOL)force baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion;
- (NSUUID *)regenerateModule:(NSString *)module snapshot:(NSDictionary *)snapshot baseEvent:(NSDictionary *)baseEvent completion:(CGDGuideCompletion)completion;
- (void)cancelSubscription:(NSUUID *)token;
- (void)clearCache:(void (^)(NSString *failure))completion;
- (void)restoreModule:(NSString *)module snapshot:(NSDictionary *)snapshot previousEvent:(NSDictionary *)previous currentEvent:(NSDictionary *)current completion:(CGDGuideCompletion)completion;
@end
