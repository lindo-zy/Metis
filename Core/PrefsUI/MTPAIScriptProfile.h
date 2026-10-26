#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 两处脚本位的运行契约不同，共用同一套「生成 → 预检 → 采纳」流程时，
// 差异全部收敛在这个 profile 里：入口签名、沙盒能力、体积上限、提示词与示例。
// 新增第三处脚本位时只加一个 +profile，不要再复制 chat/debug 页面。
typedef NS_ENUM(NSInteger, MTPAIScriptRuntime) {
    // 自定义动作：设置进程内由 MTJavaScriptEngine 执行，可联网、可打开 App。
    MTPAIScriptRuntimeAction = 0,
    // 底栏 JS 规则：键盘进程内由 MTContextClassifier 执行，纯沙盒判定。
    MTPAIScriptRuntimeContext,
};

@interface MTPAIScriptProfile : NSObject

@property(nonatomic, assign, readonly) MTPAIScriptRuntime runtime;
// 展示用入口签名，例如 "async function main(str)" / "function match(text)"。
@property(nonatomic, copy, readonly) NSString *entrySignature;
// 入口函数名，预检用它做全局绑定探测与回复截取。
@property(nonatomic, copy, readonly) NSString *entrySymbol;
// 一行契约摘要，给 AI 生成页与编辑器状态条用。
@property(nonatomic, copy, readonly) NSString *contractSummary;
// AI 入口副标题，说明这一路只会生成什么。
@property(nonatomic, copy, readonly) NSString *generateSubtitle;
// 0 表示不按字节限制，改用字符上限。
@property(nonatomic, assign, readonly) NSUInteger maxBytes;
@property(nonatomic, assign, readonly) NSUInteger maxCharacters;
// 新建规则时的默认脚本。
@property(nonatomic, copy, readonly) NSString *sampleTemplate;

+ (instancetype)actionProfile;
+ (instancetype)contextProfile;

- (NSString *)systemPrompt;
// 语法、入口声明、体积三项静态检查；从不执行脚本。
- (nullable NSString *)precheckErrorForScript:(NSString *)script;
// 去除 Markdown 围栏、剥离解释文字，尽量拿到可直接编译的脚本。
- (NSString *)scriptFromReply:(NSString *)reply;
// "1.4 KB / 8 KB" 或 "1234 / 131072 字符"，供编辑器与预览卡显示。
- (NSString *)byteUsageTextForScript:(NSString *)script;
// 供 UI 判断是否已超限。
- (BOOL)isScriptOversized:(NSString *)script;

@end

NS_ASSUME_NONNULL_END
