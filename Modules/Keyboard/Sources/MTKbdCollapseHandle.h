#import <Foundation/Foundation.h>

// 承载键盘的进程（包括 SpringBoard）：写入 Darwin 状态字并广播门铃，
// 键盘弹出时隐藏把手和面板，收起后恢复先前位置和缩边状态。
FOUNDATION_EXPORT void MTStartKbdVisibilityReporter(void);

// SpringBoard 进程：安装收起把手宿主（Darwin 观察者；窗口与把手按需创建）。
FOUNDATION_EXPORT void MTStartKbdCollapseHandle(void);

// SpringBoard 进程：桌面出现时收回面板并恢复边缘常驻入口。
FOUNDATION_EXPORT void MTKbdCollapseHandleDesktopDidAppear(void);

// SpringBoard 进程：悬浮会话转为 Live 时喂入最近悬浮列表（面板数据源）。
FOUNDATION_EXPORT void MTKbdCollapseHandleNoteFloated(NSString *bundleIdentifier);
