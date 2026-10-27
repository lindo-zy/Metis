//
//  MTCaptureRuleEngine.h
//  Mt
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 复制后按序求值 match(text, meta)，首个命中规则决定悬浮入口及动作。
// 规则数据存共享资源文档顶层键 clipboardRules（读写见 MTClipboardActionReferences）。
@interface MTCaptureRule : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
// 关闭的规则完全不参与求值；缺省为启用。
@property (nonatomic, assign, readonly) BOOL enabled;
// 首条命中规则开启此开关时，复制后自动执行；否则等待单击悬浮入口。
@property (nonatomic, assign, readonly) BOOL autoRun;
@property (nonatomic, assign, readonly) BOOL floatingEnabled;
@property (nonatomic, copy, readonly) NSString *symbolName;
// #RRGGBB，缺省或非法值使用蓝色 #007AFF。
@property (nonatomic, copy, readonly) NSString *symbolColor;
@property (nonatomic, assign, readonly) BOOL tooltipEnabled;
@property (nonatomic, copy, readonly) NSString *tooltipText;
@property (nonatomic, copy, readonly) NSString *source;
// 指向共享资源动作库的 UUID，至多一个；旧配置保留首个有效引用。
@property (nonatomic, copy, readonly) NSArray<NSString *> *actions;

// 防御性解析：非法条目（缺 id/source 超限/结构不对）直接丢弃，不抛错。
+ (NSArray<MTCaptureRule *> *)rulesFromDictionaries:(nullable NSArray *)dictionaries;
- (NSDictionary *)dictionaryRepresentation;

@end

typedef void (^MTCaptureRuleReply)(MTCaptureRule * _Nullable hit);

@interface MTCaptureRuleEngine : NSObject

+ (instancetype)sharedEngine;

// 后台串行求值，completion 回主线程。hit 为 nil 表示未命中（含全部失败/禁用）。
- (void)evaluateRules:(NSArray<MTCaptureRule *> *)rules
                 text:(nullable NSString *)text
                 kind:(NSString *)kind   // @"text" | @"image"
             autoOnly:(BOOL)autoOnly
           completion:(MTCaptureRuleReply)completion;

// 调试与运行使用同一沙盒；不累积失败计数，也不执行动作。结果含有界 console 日志。
- (void)testSource:(NSString *)source text:(nullable NSString *)text kind:(NSString *)kind
        completion:(void (^)(NSDictionary *result))completion;

// 同步单条求值（宿主测试/调试用），返回 @{@"matched": @BOOL, @"error": NSString, @"ms": @double}。
- (NSDictionary *)evaluateSource:(NSString *)source
                            text:(nullable NSString *)text
                            kind:(NSString *)kind;

@end

NS_ASSUME_NONNULL_END
