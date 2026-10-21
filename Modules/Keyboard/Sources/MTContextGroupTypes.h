#import <Foundation/Foundation.h>

// 上下文动作组：底栏的「预留区」按当前输入上下文换内容。
//
// 四层结构：布局 → 组 → 有序类型 → 有序动作。
// 同一时刻只激活一组，旧枚举值保留为 ABI 兼容别名。
typedef NS_ENUM(NSInteger, MTContextGroup) {
    MTContextGroupNone = 0,
    // 无信号时的兜底：不显示上下文动作，预留区留给悬浮应用记录/常用应用。
    MTContextGroupDefault,
    // G1 选区：输入框里有非空选区。
    MTContextGroupSelection,
    // G2 剪贴板：8 秒（可配）内发生过复制。
    MTContextGroupClipboard,
    // G3 粘贴后：一次插入达到阈值字数后的 3 秒（可配）短时覆盖层。
    MTContextGroupPaste,
    // v2 输入框有文字；旧名 Input 保留兼容。
    MTContextGroupInput,
    MTContextGroupIdle,
    MTContextGroupDelete,
    MTContextGroupCopy = MTContextGroupClipboard,
    MTContextGroupTyping = MTContextGroupInput,
};

typedef NS_ENUM(NSInteger, MTContextPayloadKind) {
    // 复用工具栏既有动作选择器（copyAction: / pasteAction: / undoAction: 等）。
    MTContextPayloadSelector = 0,
    // 以悬浮窗口打开 URL。
    MTContextPayloadURL,
    // 打开 AI 面板并带入种子文本。
    MTContextPayloadAISeed,
    // Preserve an unavailable action slot without filling from later actions.
    MTContextPayloadUnavailable,
};

@interface MTContextAction : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, copy, readonly) NSString *symbol;
@property(nonatomic, assign, readonly) MTContextPayloadKind payloadKind;
@property(nonatomic, copy, readonly) NSString *payload;
+ (instancetype)actionWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                              symbol:(NSString *)symbol
                         payloadKind:(MTContextPayloadKind)payloadKind
                             payload:(NSString *)payload;
@end

// 一次判定的结果。ttl 是「还要等多久重新判定」，0 表示只随信号变化。
@interface MTContextDecision : NSObject
@property(nonatomic, assign, readonly) MTContextGroup group;
@property(nonatomic, copy, readonly) NSString *reason;
@property(nonatomic, copy, readonly) NSArray<MTContextAction *> *actions;
@property(nonatomic, assign, readonly) NSTimeInterval ttl;
+ (instancetype)decisionWithGroup:(MTContextGroup)group
                           reason:(NSString *)reason
                          actions:(NSArray<MTContextAction *> *)actions
                              ttl:(NSTimeInterval)ttl;
// 底栏用它做廉价变更检测：组、原因、动作标识都相同才算没变。
- (BOOL)isEquivalentToDecision:(MTContextDecision *)other;
@end

FOUNDATION_EXPORT NSString *MTContextGroupName(MTContextGroup group);
FOUNDATION_EXPORT NSString *MTContextGroupKey(MTContextGroup group);
FOUNDATION_EXPORT NSArray<NSNumber *> *MTContextPriority(NSDictionary *preferences);

// 信号快照。所有时间都是「距今多少秒」，由采集端算好，引擎不读时钟以外的状态。
@interface MTContextSnapshot : NSObject
@property(nonatomic, assign) NSTimeInterval deleteAge;
@property(nonatomic, assign) NSUInteger deletedLength;
@property(nonatomic, assign) BOOL canUndo;
@property(nonatomic, assign) BOOL hasImage;
@property(nonatomic, copy) NSString *pasteboardKind;
@property(nonatomic, copy) NSString *pastedText;
@property(nonatomic, copy) NSString *inputText;
// group -> {builtin: [ids], js: [ids], pending: bool}; immutable classifier results.
@property(nonatomic, copy) NSDictionary *classification;
@property(nonatomic, copy) NSString *selectionText;
@property(nonatomic, assign) NSUInteger selectionLength;
@property(nonatomic, assign) NSTimeInterval selectionAge;
@property(nonatomic, copy) NSString *clipboardText;
@property(nonatomic, assign) BOOL clipboardAvailable;
@property(nonatomic, assign) NSTimeInterval clipboardAge;
@property(nonatomic, assign) NSUInteger pastedLength;
@property(nonatomic, assign) NSTimeInterval pasteAge;
@property(nonatomic, assign) BOOL inputAvailable;
@property(nonatomic, assign) NSUInteger inputLength;
@property(nonatomic, assign) BOOL secureInput;
@property(nonatomic, copy) NSString *contentType;
@property(nonatomic, assign) NSInteger keyboardType;
@end

// 判定参数全部来自偏好，缺省值写在 settingsFromPreferences 里，读写两侧同源。
@interface MTContextGroupSettings : NSObject
@property(nonatomic, assign) BOOL enabled;
@property(nonatomic, assign) BOOL selectionEnabled;
@property(nonatomic, assign) BOOL clipboardEnabled;
@property(nonatomic, assign) BOOL pasteEnabled;
@property(nonatomic, assign) BOOL inputEnabled;
@property(nonatomic, assign) BOOL idleEnabled;
@property(nonatomic, copy) NSArray<NSNumber *> *priority;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *configuredActions;
@property(nonatomic, assign) NSTimeInterval clipboardFreshness;
@property(nonatomic, assign) NSTimeInterval pasteFreshness;
@property(nonatomic, assign) NSUInteger pasteMinLength;
+ (instancetype)settingsFromPreferences:(NSDictionary *)preferences;
@end
