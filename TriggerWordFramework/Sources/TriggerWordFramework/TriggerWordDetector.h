#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TriggerWordDetector : NSObject

- (void)startListening;
- (void)stopListening;
- (void)reset;

@end

NS_ASSUME_NONNULL_END

