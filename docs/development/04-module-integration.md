# 04 · 三模块迁入与重新集成

## 1. 迁入方法

采用固定来源提交的源码导入，不嵌套 Git 仓库、不依赖开发机旁边恰好存在三个目录，也不把原项目作为运行时依赖。`provenance.json`（待生成）按文件记录来源仓库、commit、原路径、SHA256、许可声明和本地修订原因。

第一轮保留 `PX* / DX* / Kayoko*` 类名前缀以减少移植噪声，新协调接口使用 `MT*`。每个模块先加薄适配器，再替换旧外部调用；禁止先全局字符串替换品牌名造成通知、数据库路径或迁移 key 同时变掉。

只导入源码/头文件/必要资源/许可/有用测试。排除 `.git/.theos/packages/local.env/notify.local.conf/build-notify.local.conf/.netrc/设备脚本个人配置`；原项目的构建上传和通知逻辑不复制。

来源测试里包含被 Git 忽略的文件要显式登记；不得把缺失 fixture 误当业务实现故障。原项目独立功能仍在原仓库维护，本任务只改 Metis 内副本。

## 2. 需要建立的全量对照表

M0 建立 `docs/implementation/feature-parity.md`，最少包含以下行组，并继续依据源码展开到实际选项。状态只能用 `planned / ported / host-verified / package-verified / device-verified / deferred-with-reason`，每行关联任务 ID、来源、目标、测试证据。

| 模块 | 功能组 | 目标归属 | 不得丢失的行为 |
| --- | --- | --- | --- |
| Capture | 全屏/区域/冻结/即时/全屏标记/滚动 | Capture provider | 六模式、取消、busy、锁屏与失败反馈 |
| Capture | 实时区域与冻结切换 | Capture task / selection | 捕获时机、几何快照、拖动隐藏控件、结束恢复 |
| Capture | 长截图 | Capture/LongShot | 自动/智能/采样、暂停继续、尾帧、拼接与内存降级 |
| Capture | 编辑器 | Capture/Editor | 工具、文档、撤销重做、裁剪旋转、重编保留原资源 |
| Capture | 工具栏定制 | Prefs button editor | 顺序、隐藏、图标、名字、URL，自适应每行最多八项 |
| Capture | 输出 | Capture/Output | 保存/复制/分享/预览、幂等、错误重试 |
| Capture | 气泡与悬浮图 | Capture/Overlay | 点击重编、拖动、阴影与触摸策略 |
| Keyboard | 顶部/底部工具栏 | Keyboard host | 独立配置、容量、启停与现有输入行为 |
| Keyboard | 内置文字操作 | Keyboard executor | 选择/复制/删除/光标/查词；组合文本、密码框保护 |
| Keyboard | 六槽手势与子动作 | Gesture coordinator / actions | tap/hold/四向、选择列表/顺序执行原语义 |
| Keyboard | 文本/URL/App/快捷项 | Action providers | 入参替换、应用内浏览、普通/悬浮打开 |
| Keyboard | JavaScript | Script provider | JavaScriptCore 隔离、候选输出、网络与超时取消 |
| Keyboard | 系统动作与控件 | SpringBoard provider | 按能力显隐、敏感动作确认、状态回执 |
| Keyboard | 键盘面板/手势面板 | Keyboard / SpringBoard | 命名、布局、内容、系统控件、类型上下文 |
| Keyboard | Dock/状态栏/横屏/灵动岛 | Gesture coordinator | 区域绑定、未配置放行、晚加载与启动安全 |
| Keyboard | 悬浮 App 与停靠栏 | Floating provider | 打开/最小化/恢复/关闭/缩放/输入，固定六槽 |
| Keyboard | 收起键盘把手 | Keyboard handle | 键盘显隐、拖动、贴边保留入口、面板恢复 |
| Keyboard | AI | AI provider | 多引擎、流式、人设、Markdown、附件、取消 |
| Keyboard | 悬浮粘贴 | Clipboard bridge + host | 内容更新、来源规则、3 秒预览、点按粘贴 |
| Keyboard | 验证码与浏览器重定向 | 独立 providers | 各自默认关，禁用时不处理敏感内容 |
| Keyboard | 图标/分组/批量 | Shared editors | SF 与 App 图标、稳定 ID、分组搜索和批量 |
| Clipboard | 文本/图片/富文本采集 | Clipboard history service | 去重、最大数量、远程来源过滤、保留类型 |
| Clipboard | 历史/收藏/标签 | Clipboard repository | UUID、标签颜色、收藏与历史分开、备注 |
| Clipboard | 搜索/组合筛选/画廊 | Clipboard panel | 分类/来源 App/标签组合、两套画廊 |
| Clipboard | 编辑/分词/二次分词 | Clipboard controllers | 词序、选词、文本与图片预览操作 |
| Clipboard | 来源图标/元数据 | App metadata provider | 现有格式兼容、缺失 fallback、缓存失效 |
| Clipboard | 粘贴/焦点恢复 | UIKit helper + broker | 模式、原输入宿主、锁屏/密码拒绝 |
| Clipboard | 悬浮预览与面板 | Overlay coordinator | 透明区域穿透、倒计时、位置与尺寸 |
| Clipboard | 文本/图片/双击动作 | Shared action refs | `$$$` / `@@@` 替换与 URL 编码语义 |
| Clipboard | 维护与外部导入 | Migration tools | 缓存、数据库检查、CopyLog/CopyVault 独立导入 |

README 的动作数量可能比实际目录旧；不得用文档里的“35 项”等数字生成硬编码上限，运行能力清单才是执行依据。

## 3. PixPin 迁入步骤

1. 按原分层复制到 `Modules/Capture`，先运行移入的纯逻辑测试，记录 baseline；不运行原 build.sh。
2. `MTCaptureModule` 适配 `PXCaptureCoordinator`：显式 prepare/start/activate/deactivate，去掉移入目标里的自启动 constructor。
3. 偏好读取换为 `MTConfigSnapshot` 到 `PXConfig` 的映射，任务仍持不可变 configSnapshot；原 key 仅在 importer 中存在。
4. 六模式映射为 `builtin:capture.*`，直接调 provider；保留 legacy URL/notify 仅在兼容层注册一次。
5. `PXCaptureTask` 的 taskID、状态机、claim/unclaim 输出机制保留；不能为了统一 broker 再维护第二个相互不一致的 activeTask。
6. 将窗口注册到 OverlayCoordinator，完成捕获排除与 finally 清理；busy/取消、旋转失效、退后台/锁屏、长截图内存警告均回归。
7. 把写系统剪贴板切到 ClipboardService，传 origin 与 policy；Capture 不能直接写历史 SQLite。
8. 原设置控制器按页复用/改造，配置字段进入统一 descriptor；移除旧 PreferenceLoader 注册。
9. ShellX/Snapper 外部适配保留为可选 compat provider，缺失不影响六模式；Metis 内部不走这些外部通知。

一个常见陷阱：统一 dispatcher “接受了请求”不代表相册写入完成；必须把 task 输出结果回传并区分 partial capture。

## 4. KayokoX 迁入步骤

1. Core 中面板/历史业务迁入 SpringBoard 目标，Helper 移入 UIKitHost；druid/pasted 提示 hook 单独目标。运行时进程分类沿用并审查，避免受保护系统 UI 和非键盘扩展误装 hooks。
2. 先迁 `HistoryStore/Repository/PasteboardItem/RichTextRepresentation/Tags`，用临时库验证 schema 和引用完整性，不触碰真实历史。
3. 在新私有目录生成目标数据库与资源；旧 `history-v4.sqlite` 只读导入，不复用同一个实时文件。迁移协议见 05。
4. 移除 `KayokoCore.m`/Helper 中独立 constructor 的自动业务启动，改模块注册；保留必要 hook 安装的明示入口并补 stop 路径。
5. 保留 `KayokoFloatingPreviewWindow` 空白触摸穿透；主面板窗口继续独立交互策略，不能全局把两个窗口都改成穿透。
6. 激活方式先按旧 bitmask 导入，每个 bit 映射到相应手势 binding，未知 bit 保留原始值并标需检查；不默认为某种新上滑。
7. 所有内部 pasteboard 写入走 ClipboardService；外部变化观察只注册一份，并应用 record/preview policy。
8. 文本、图片和双击动作迁成统一动作 UUID + context binding；依然保留独立菜单顺序和输入类型限制。
9. `KayokoSnapperIntegration` 改走 `capture.pinImage / capture.editor` 能力接口。**这些能力需在 Capture adapter 显式实现，不等于六种捕获请求已经覆盖。** 未具备能力时显示不可用，不能重新伪造一个 SnapperWindow 类。
10. 面板/悬浮预览/设置资源路径全部走 resolver。SQLite 串行队列与 UI 主队列不交叉同步等待。
11. Updater 中可复用的导入解析移到专用工具，提权 entitlement 和 postinst 行为逐项审查；不能把“安装 Metis”变成自动导入其他 App 私有数据或杀守护进程。

## 5. TypeX 迁入步骤

1. 先按进程切开现有大目标：键盘 hooks/编辑动作入 UIKitHost；系统 broker、全局手势、悬浮托管入 SpringBoard。任何动态 hook 安装归唯一目标。
2. 将 `DXPrefsManager` 换为配置 adapter，去掉 `+load` 自动初始化的权威写入。`preferencesAvailable` 和最后有效快照逻辑仍保留，不再从沙盒 App 回写公开权威快照。
3. 顶部/底部工具栏、按钮列表、六槽手势和布局先保持行为，再接统一编辑器；保留容量与停用配置，不截断用户数组。
4. `DXShortcutsGenerator` 中 PixPin/Kayoko 安装检测改为 registry。`DXPixPinIntegration` 与 clipboardAction 从内部路径移除外部 notify；界面不再要求旧 dylib 存在。
5. 固定目录中的 PixPin 系统动作映射到 Capture provider，旧系统动作仍由 SpringBoard 执行；无输入上下文的手势不能调用必须选区的文字动作。
6. 七类自定义动作迁到 UUID 模型；脚本、人设、图标、分组、面板引用完整保留；旧 selector 仅作为迁移元数据，不长期当主键。
7. Dock/状态栏/工具栏长滑注册到 GestureCoordinator；和 Kayoko 上滑/地球/听写入口先做 hook 冲突表，再安装。
8. `DXFloatingAppRuntime` 作为完整子系统先适配，不拆散 Scene/输入/恢复会话；卡片中心 spinner、停靠栏 spinner 分别度量，不能以修改一个动画宣称修好恢复延迟。
9. 键盘把手保留键盘 show/hide 与贴边恢复；晚启动不能碰未就绪私有 singleton。
10. AI、JavaScript、验证码、浏览器重定向独立 provider，保留开关和安全检查；密钥从公共 config 中剥离，网络测试必须用户明确点击。
11. Settings 子项目内复用纯预览/选择器，禁止把完整 `DXAIEngine` 的自动副作用连带加载；AI 测试由明确 service 调用。

## 6. 公共组件去重顺序

| 顺序 | 组件 | 做法 | 完成条件 |
| --- | --- | --- | --- |
| 1 | 路径、日志、配置类型 | 先建立 Core，旧模块用 adapter | 不再硬编码旧资源根/新权威域 |
| 2 | App 列表与图标 | v1 统一选择外部 AltList 依赖，移除 TypeX vendored 编译副本；图标元数据 provider 做内部包装 | 同宿主无重名类；安装依赖与包检查一致 |
| 3 | 动作和参数 | UUID、inputTypes、context、能力校验 | 所有消费者只存引用 |
| 4 | 手势拥有者 | 合并重复 hook，建立触发仲裁 | 同一手势不双触发，不破坏原行为 |
| 5 | 窗口协调 | 租约包裹旧窗口，不重写内容 UI | 捕获无自身浮层、交互与恢复正确 |
| 6 | 剪贴板写入 | 一个事件源与去重路径 | 截图/验证码/历史粘贴不会错误重复记录 |

外部 AltList 是为了先统一两个既有方案的默认设计，版本/RootHide 可用性需 M0 验证；若决定 vendoring，需完整修改依赖、编译列表、类唯一性和许可记录，不能两套同时存在。

## 7. 旧协议兼容与收尾

兼容承诺：`pixpin://…`、`kayokox://open|close|hide|toggle`、已登记的 PixPin/Kayoko 公共 Darwin 入口。兼容层将其归一为新 action 请求，并始终执行总开关、模块、锁屏和 busy 检查。

Metis 内部不广播旧通知，也不让“旧入口 → 新通知 → 旧入口”双向桥接；所有别名只单向进入一个 dispatcher。需要兼容第三方 Snapper/ShellX 的通知可能同时被真正第三方监听，必须单独列出并测试重复响应，v1 新增兼容默认关闭，导入既有显式兼容选择可保留。

外部调用缺少 requestID 时只能做入口防并发和短窗口节流，不能承诺跨多个旧通知严格 exactly-once；内部 API 要求 requestID 幂等。

最终包不得安装三个旧 PreferenceLoader 入口和原自动 constructor。Source provenance/原版权头仍保留，品牌展示保留在模块说明与关于页面。
