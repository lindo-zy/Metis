#import <Foundation/Foundation.h>

// SpringBoard 进程：安装快速面板宿主（Darwin 观察者；窗口与面板按需创建）。
// 面板由系统动作（「快速面板」）唤出，不依赖键盘显隐。
FOUNDATION_EXPORT void MTStartQuickPanelHost(void);

// SpringBoard 进程：桌面出现时收回已展开的快速面板。
FOUNDATION_EXPORT void MTQuickPanelDesktopDidAppear(void);

// SpringBoard 进程：悬浮会话转为 Live 时喂入最近悬浮列表（面板数据源）。
FOUNDATION_EXPORT void MTQuickPanelNoteFloated(NSString *bundleIdentifier);

// SpringBoard 主线程：按需打开快速面板（系统动作入口）。
FOUNDATION_EXPORT BOOL MTPresentQuickPanel(void);
