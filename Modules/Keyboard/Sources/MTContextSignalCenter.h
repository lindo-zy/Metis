#import <UIKit/UIKit.h>
#import "MTContextGroupTypes.h"

FOUNDATION_EXPORT NSNotificationName const MTContextGroupDidChangeNotification;

// 进程内信号采集与动作组状态机（主线程单例）。
//
// 只在「悬浮底栏 + 动作组」都开启时工作：未开启时所有 hook 入口一次字典读取即返回，
// 不注册定时器、不读选区。渲染端（底栏）订阅 MTContextGroupDidChangeNotification。
@interface MTContextSignalCenter : NSObject

+ (instancetype)sharedCenter;

@property(nonatomic, readonly) MTContextDecision *currentDecision;
// 当前是否处于工作态（悬浮底栏开启且动作组未被关闭）。
@property(nonatomic, readonly) BOOL active;

#pragma mark - hook 入口（任意线程，内部转主线程）
- (void)noteResponderActivated:(UIResponder *)responder;
- (void)noteResponderResigned:(UIResponder *)responder;
- (void)noteSelectionLengthChanged:(NSUInteger)length responder:(UIResponder *)responder;
- (void)noteCopyFromResponder:(UIResponder *)responder;
- (void)notePasteToResponder:(UIResponder *)responder insertedLength:(NSUInteger)insertedLength;
- (void)noteExternalClipboardChange;

#pragma mark - 执行侧
- (void)evaluateNow;
- (NSString *)diagnosticSummary;

@end

// 读取输入框当前字符数。只走公开属性，取不到返回 0。
FOUNDATION_EXPORT NSUInteger MTContextTextLengthForResponder(UIResponder *responder);
