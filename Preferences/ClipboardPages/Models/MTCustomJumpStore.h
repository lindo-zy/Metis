//
//  MTCustomJumpStore.h
//  Mt
//

#import <Foundation/Foundation.h>

@class MTCustomJump;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMTCustomJumpStoreErrorDomain;

@interface MTCustomJumpStore : NSObject

@property(nonatomic, copy, readonly) NSString *jumpsPath;

+ (NSString *)defaultJumpsPath;
+ (NSString *)defaultImageActionsPath;
- (instancetype)initWithJumpsPath:(NSString *)jumpsPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSMutableArray<MTCustomJump *> *)loadJumpsWithError:(NSError **)error;
- (BOOL)saveJumps:(NSArray<MTCustomJump *> *)jumps error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
