//
//  MTWordSelectionTokenizer.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTWordSelectionTokenizer : NSObject

+ (NSArray<NSDictionary<NSString *, id> *> *)tokensForText:(NSString *)text;
+ (NSArray<NSDictionary<NSString *, id> *> *)characterTokensForText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
