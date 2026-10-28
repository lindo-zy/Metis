#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 剪切板设置包内「就地新建动作」的落盘桥：新建动作的定义经 legacy 域写入
// （MTPrefsManager），由 legacy 桥镜像进共享资源库，对键盘等其余入口可见。
// 自定义跳转管理页与捕获规则的「添加动作」共用这两个函数。

// 追加一条自定义动作定义；非空分组名同时注册进分组表。重复 selector 会被
// 去重替换。写入成功返回 YES。
BOOL MTClipboardPersistCustomActionDefinition(NSDictionary *definition);

// 桥接层从 legacy selector 确定性推导 store UUID：写入完成后用它把新动作
// 解析成共享库 UUID（引用以 UUID 存储）。找不到返回 nil。
NSString * _Nullable MTClipboardStoredActionIDForSelector(NSString *selector);

NS_ASSUME_NONNULL_END
