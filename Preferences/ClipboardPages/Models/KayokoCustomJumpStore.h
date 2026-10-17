//
//  KayokoCustomJumpStore.h
//  Kayoko
//

#import <Foundation/Foundation.h>

@class KayokoCustomJump;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kKayokoCustomJumpStoreErrorDomain;

@interface KayokoCustomJumpStore : NSObject

@property(nonatomic, copy, readonly) NSString *jumpsPath;

+ (NSString *)defaultJumpsPath;
+ (NSString *)defaultImageActionsPath;
- (instancetype)initWithJumpsPath:(NSString *)jumpsPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable NSMutableArray<KayokoCustomJump *> *)loadJumpsWithError:(NSError **)error;
- (BOOL)saveJumps:(NSArray<KayokoCustomJump *> *)jumps error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
