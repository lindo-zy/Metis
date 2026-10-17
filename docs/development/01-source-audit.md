# 01 · 现状与源码证据

## 1. 调查范围

2026-10-17 对本地四个仓库进行了只读源码调查。没有构建、安装、USB/SSH、联网查询或原仓库修改。下面的“事实”是文件/接口事实，不表示对应私有 API 已在设备运行。

| 仓库 | 本地分支 | HEAD | control 版本 | 工作区 |
| --- | --- | --- | --- | --- |
| Metis | main | 无首个提交 | 无 | 初始空仓库 |
| TypeX | dev | `dfc9a5b19924482272ba3a0e7f1282a9aad9a765` | 4.8.7 | 调查时干净 |
| PixPin | main | `973b1b1afe6d1e452d63cf90333f7337ddc4a003` | 2.2.9 | 调查时干净 |
| KayokoX | main | `61b7a8d35274540068ddda3233df78d9d47f0046` | 5.0.56 | `build.sh` 已修改；`.zcodeignore` 未跟踪 |

来源根目录分别为 `/Users/xiao/dev/github/TypeX`、`/Users/xiao/dev/github/PixPin`、`/Users/xiao/dev/github/KayokoX`。这些绝对路径只用于本机查阅；后续导入配置必须允许覆盖，不依赖开发者机器目录。

KayokoX 未提交 `build.sh` diff 是三处 Bark 通知文字变化。本手册不将其视为业务集成输入，也不覆盖它。源码哈希记录的是调查时工作区实际文件，HEAD 则标识 Git 基线，两者不可混为一谈。

机器可读证据见 [source-baseline.json](evidence/source-baseline.json)。版本以当前 control 为准：例如 PixPin README 内“当前版本 1.5.10”已经落后于 control 的 2.2.9，不能按 README 版本导入。

## 2. TypeX

| 观察点 | 已读来源 | 集成含义 |
| --- | --- | --- |
| 注入 | `TypeX.plist`：UIKit + SpringBoard；`TypeX.xm` | 不应把同等广度应用到 PixPin |
| 编译 | 根 Makefile 通配顶层 `.m/.mm/.x/.xm`，另编译 `typexprefs` | 移入后改显式目标清单，避免把设置类/测试编入注入库 |
| 偏好 | `common.h`、`DXPrefsManager.m/.h` | 域 `com.lindo.typex`，主开关 `enabledBOOL`；有版本化 shared snapshot 与 `preferencesAvailable` |
| 沙盒桥 | `DXPrefsManager.m`、`typexprefs/Makefile` | `/Library/TypeX/shared.plist`、目录 0777 是现状，不能直接推广到 Metis 敏感数据 |
| 系统执行 | `DXSystemOpenBroker.h/.m`、`DXDarwinOpenChannel.h/.m` | 已有请求 TTL、错误枚举、超时不重试语义，优先适配 |
| 旧联动 | `DXPixPinIntegration.h`、`DXShortcutsGenerator.m` | 检查 `PixPin.dylib` 与 kayoko 前缀 dylib；合并后必须替换为模块 capability |
| 设置 | `typexprefs/Resources/Root.plist` 与 `DXP*Controller` | 顶底工具栏、面板、动作、手势、AI、短信、浏览器重定向等分散 |
| 图标 | `typexprefs/AltList`、`DXPSFSymbolCatalog` | 自带 AltList 源码，和 KayokoX 外部 AltList 要去重 |
| 新功能 | `DXKbdCollapseHandle`、`DXFloatingAppRuntime`、`DXBrowserRedirectHooks` | 比历史笔记更新，不能按旧版本删减 |

核心功能覆盖：双工具栏、六槽手势、子动作、文本/URL/应用/快捷项/脚本/系统动作、键盘和桌面面板、状态栏/Dock、悬浮 App 与六槽停靠栏、键盘收起把手、AI、多项应用策略、短信验证码、浏览器重定向、剪贴板悬浮粘贴、备份恢复。

TypeX 的 `tests/` 和 `docs/` 被 `.gitignore` 忽略，当前本机却存在大量 `tests/run-*.py`。不能只按 Git commit 导入代码后认为测试本来就没有；要显式挑选并登记测试来源。

## 3. PixPin

| 观察点 | 已读来源 | 集成含义 |
| --- | --- | --- |
| 注入 | `PixPin.plist` | 仅 SpringBoard |
| 分层 | `Sources/Common/Capture/Overlay/Editor/Output/SpringBoard` | 可保留既有分层迁入 Modules/Capture |
| 设置 | `PXConstants.m`、`PXPreferences.m`、Prefs Root.plist | 域 `com.pixpin.screenshot`，主开关 `Enabled` |
| 请求 | `PXExternalRequest.h/.m`、`PXSpringBoardEntry.xm` | 白名单 URL/Darwin 入口；部分旧 Snapper/ShellX 协议与可选类对接 |
| 会话 | `PXCaptureTask.h`、`PXCaptureCoordinator.h` | 唯一 taskID、状态转换、输出 claim、配置快照、忙时拒绝 |
| 实时区域 | `PXCaptureTask.h`、`PXSelectionView.m` | 当前源码已含实时区域/冻结态字段，不能把历史未完成笔记当当前事实 |
| 排除层 | `PXCaptureLayerExclusion.m` | 捕获位恢复只恢复自己持有的位；新增共享窗口管理不得破坏 |
| 输出 | `PXClipboardWriter`、`PXOutputPipeline` | 保存/复制幂等与失败重试要保留 |
| 测试 | `Tests/run-host-tests.sh`、`Tests/Unit` | 现成纯逻辑与图像链路测试可迁入；stub 不是真机 UIKit |

保留六类截图模式、区域冻结切换、自动/智能/采样长截图、编辑器与撤销、按钮排序和自定义 URL、结果气泡、悬浮图、保存/复制/分享、外部入口、内存警告降级。

## 4. KayokoX

| 观察点 | 已读来源 | 集成含义 |
| --- | --- | --- |
| 进程拆分 | Core/Helper 的 Makefile 与 filter | Core：SpringBoard + `druid/pasted`；Helper：UIKit，内部再分类 |
| 进程分类 | `KayokoHelperProcessContext.m` | keyboard-service appex 与普通 App 分开，过滤受保护应用/非键盘扩展 |
| 主业务 | `KayokoCore.m`、`KayokoCoreRuntime.m` | 面板、观察者、剪贴板采集、粘贴、悬浮预览等要拆出可停用服务 |
| 存储 | `KayokoHistoryStore.m` | SQLite `history-v4.sqlite`，图片目录、`rich-text` 关联文件；不是一个 plist |
| 路径 | `KayokoHistoryStore.m` | 逻辑根 `/var/mobile/Library/com.lindo.kayoko/` 经 `jbroot` 解析 |
| 配置 | `KayokoPreferenceKeys.h`、`KayokoNotificationKeys.h` | 域是 `com.lindo.kayoko.preferences`，不是包名 `com.lindo.kayokox` |
| UI 配置 | Root/AdvancedOptions.plist 与 Controllers | 浮窗、预览、标签、动作、画廊、应用过滤、数据维护 |
| 旧悬浮 | `KayokoSnapperIntegration.m` | 依赖运行时 `SnapperWindow` 类；内部应改为 Capture 能力接口 |
| 安装辅助 | Updater/Makefile、postinst | 导入器带 entitlement，安装脚本重启 druid/pasted；不能原样执行安装维护 |
| AltList | Preferences/Makefile、Frameworks | 使用外部框架 stub，control 有 com.opa334.altlist 依赖 |

保留文本/图片/富文本历史、收藏、搜索组合筛选、标签、分词和二次分词、预览编辑、来源 App 图标、文本/图片/双击动作、隐私遮罩、自动粘贴/焦点恢复、悬浮预览、画廊和数据导入维护。

## 5. 构建与许可的当前事实

- 三个仓库当前入口都是根 `build.sh`，不是旧笔记里的 `build-roothide-ios.sh`。
- TypeX、PixPin 当前脚本依次构建 iOS 16 / iOS 17；KayokoX 接受 `ios16|ios17|all`。
- 三者编译主体均涉及 arm64/arm64e。KayokoX updater 单独配置 arm64，不能以主库架构推断工具架构。
- KayokoX 当前构建还包含 iCloud 归档、WebDAV、Bark，部分发布失败只警告。Metis 需要自己定义清晰退出码，不继承副作用。
- TypeX 根 LICENSE 文本为 AGPL v3；KayokoX COPYING/README 为 GPL v3，THIRD_PARTY_NOTICES 含 AltList MIT；PixPin 本次未发现根许可证文件。这里只登记文件事实，不作许可兼容结论。
- M0 必须生成来源与第三方清单、保留原始声明，确定可分发范围；未知许可不能由 agent 猜成“自有无约束”。发布前解决，文档与技术骨架可以先行。

## 6. 证据的边界

源码出现类名，不证明每个 iOS 小版本都有该类；文件哈希不证明设备稳定；源项目旧构建结果也不证明新 Metis 二进制。所有“已验证”必须指向本次实现实际产生的证据。
