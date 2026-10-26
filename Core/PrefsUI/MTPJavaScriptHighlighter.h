#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 语法着色只依赖位置与类型，不依赖 UIKit，主机测试可直接编译验证。
// 输出按 location 升序、互不重叠；未着色区间不出现在结果里。
typedef NS_ENUM(NSInteger, MTPJSTokenType) {
    MTPJSTokenTypeKeyword = 1,
    MTPJSTokenTypeString,
    MTPJSTokenTypeRegex,
    MTPJSTokenTypeNumber,
    MTPJSTokenTypeComment,
};

FOUNDATION_EXPORT NSString * const MTPJSTokenTypeKey;
FOUNDATION_EXPORT NSString * const MTPJSTokenLocationKey;
FOUNDATION_EXPORT NSString * const MTPJSTokenLengthKey;

@interface MTPJavaScriptHighlighter : NSObject

// 每项为 {type: NSNumber(MTPJSTokenType), location: NSNumber, length: NSNumber}。
+ (NSArray<NSDictionary<NSString *, id> *> *)tokensForSource:(NSString *)source;

@end

NS_ASSUME_NONNULL_END
