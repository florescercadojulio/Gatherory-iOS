#import "FirebaseTokenCompatibility.h"
#import <FirebaseMessaging/FirebaseMessaging.h>

@implementation GatheroryFCMTokenCompatibility

+ (void)fetchWithMessaging:(FIRMessaging *)messaging
                completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    // The server sends message.token. Firebase's register() instead requires
    // Installation ID mode and its corresponding server delivery contract.
    // Keep suppression limited to this compatibility call, not the app or SDK.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [messaging tokenWithCompletion:completion];
#pragma clang diagnostic pop
}

@end
