#import <Foundation/Foundation.h>

@class FIRMessaging;

NS_ASSUME_NONNULL_BEGIN

/// Token-based delivery compatibility for the pinned Firebase SDK.
/// register(completion:) requires an end-to-end Firebase Installation ID migration.
@interface GatheroryFCMTokenCompatibility : NSObject
+ (void)fetchWithMessaging:(FIRMessaging *)messaging
                completion:(void (^)(NSString *_Nullable token, NSError *_Nullable error))completion
    NS_SWIFT_NAME(fetch(messaging:completion:));
@end

NS_ASSUME_NONNULL_END
