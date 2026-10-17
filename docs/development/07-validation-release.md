# 07 · 测试、打包、设备验收与发布

## 1. 证据层级

| 层级 | 证明什么 | 不证明什么 |
| --- | --- | --- |
| 源码审查 | 逻辑、范围、静态路径、接口一致性 | 私有 API 真实可用、沙盒放行 |
| 主机测试 | schema、状态机、算法、模型、stub 链路 | 真实键盘、Scene、SpringBoard 触摸 |
| 构建/包检查 | 编译、资源、架构、依赖、安装脚本结构 | 设备功能正确或稳定 |
| 真机验证 | 指定系统/设备/入口下的本次观察 | 所有 iOS 小版本、所有 App 都适用 |

文档阶段只检查本手册和证据文件，没有执行原项目测试/构建。后续执行结果写到 `docs/implementation/validation/<版本>/`，不用本手册预填“已通过”。

## 2. 主机测试重点

| 测试组 | 必须覆盖 |
| --- | --- |
| 配置 | 新装默认、旧值保留、损坏/未知 schema、generation 并发、原子发布失败、最后有效快照 |
| 设置 | 所有 route/settingID 唯一、搜索直达、隐藏/过滤后稳定 ID 删除、容量、输入范围 |
| 动作 | UUID 引用、缺失动作、能力过滤、上下文、TTL、幂等、超时不重试、cancel 与迟到回调 |
| 手势 | 表面/方向/上下文冲突、短滑/长滑阈值、关闭/锁屏/取消不触发、原行为放行 |
| 窗口 | 嵌套租约、原隐藏窗口、锁屏失效、旋转、异常清理、session 不匹配不恢复 |
| 剪贴板 | write intent/commit、changeCount 关联、OTP 不入库、历史粘贴不回灌、并发外部变化 |
| 数据迁移 | 05 的全部 fixture、每一阶段中断、UUID 映射、WAL、附件、重复导入、归档越界 |
| Capture | 原图像/拼接/尾帧/内存警告/输出 claim 相关测试，保留真实算法执行 |
| Keyboard | 实际 handler/策略、容量、面板引用、输入安全、脚本与流式取消模型 |
| Clipboard | SQLite 真库 fixture、标签/收藏/附件引用、检索/筛选、损坏恢复 |

优先迁移现有有意义测试。TypeX 部分 `run-*.py` 依赖源码片段/字符串检查，搬迁后要审查其覆盖，不能把数千条文本断言当成数千个设备行为测试。PixPin UIKit stub 同样要明确范围。

不为纯文档/低风险机械变更堆砌测试。测试应发现行为错误，而不是逐句复述实现。

## 3. build.sh 的目标契约

**本节命令是待实现接口，当前仓库没有 build.sh。MT-002 实现并测试后才能执行。**

```bash
./build.sh --help
./build.sh --target all --mode verify
./build.sh --target all --mode release --version 0.1.0
```

- `verify`：默认本地测试+构建+包检查；指定输入版本，不改 control，不归档云端、不通知。
- `release`：显式版本、集成分支状态检查、双平台串行构建、检查完成后才发布版本 manifest；任何目标失败整个发布失败。
- `--target ios16|ios17|all`：开发可单目标验证；发布必须 all，版本一致。iOS17 SDK 构建不等于 iOS17 私有 API 已实测。
- `--version` 非空且格式校验；同一版本已发布则拒绝覆盖。verify 产物与 release 路径分开，不能混成最终包。
- 唯一版本来源，暂存中的包 control、Prefs Info.plist、运行版本和 manifest 一致，禁止每个子项目自增版本。
- 构建脚本自己管理 Theos/make，agent 不直接用 make/gmake 另起打包流程。
- 输出 `packages/ios16/com.lindo.metis_<版本>_ios16_iphoneos-arm64e.deb` 和 ios17 对应文件；最终 Architecture 以 RootHide 工具链输出审查，文件名不能代替元数据验证。
- 当前源脚本使用 16.5 / 17.0 SDK；Metis 默认从可配置 Theos SDK 根查找。统一最低部署线拟定 16.0，iOS17 变体若使用更高限定需在 manifest 明示。
- 构建进程级锁覆盖版本、staging、产物发布，不能两个 agent 同时写 `control` 或 `.theos`。
- 失败保留诊断和候选输出并标 invalid，不删已有已发布版本；版本写回不能早于所有检查。
- 缺少必需测试脚本要失败，不沿用 `if exists then silently skip` 作为正式发布逻辑。
- 各目标资源和类实现用显式源清单，禁止顶层通配把 Prefs、stub 或其他入口编进注入目标。

云归档、WebDAV 上传、Bark 通知不在默认 build 中。将来如实现 `scripts/archive.sh` / `scripts/publish.sh`，要有单独入口、目标、授权和结果校验；这些脚本当前也不存在。不能读取或复制旧 local.env / 通知 token 来“自动配好”。

## 4. 包结构目标与检查

以下均为逻辑路径，实际 DEB 根布局必须检查后再判断，不先假设有 `/var/jb` 前缀。

```text
Library/MobileSubstrate/DynamicLibraries/
  MetisSpringBoard.dylib + .plist
  MetisUIKit.dylib + .plist
  MetisPasteServices.dylib + .plist
Library/Metis/Frameworks/MetisCore.dylib
Library/PreferenceBundles/MetisPrefs.bundle/
Library/PreferenceLoader/Preferences/Metis.plist
usr/share/doc/com.lindo.metis/          # 来源与许可
```

package-check 应通过 `dpkg-deb -f/-c/-x`、`file/lipo`、`otool -L`、`plutil` 和唯一性扫描完成；读取/解包检查不是额外打包。

必须核对：

1. Package/Version/Architecture/Depends/Conflicts 与发布 manifest 一致。
2. dylib 依赖实际存在且 install_name/rpath 能解析，framework、sqlite、substrate/roothide 等依赖对应目标。
3. 主库/Prefs arm64/arm64e 切片按目标检查，工具按其实际架构契约检查；无意外模拟器/macOS 二进制。
4. 一个 PreferenceLoader 入口；无旧 TypeXPrefs/PixPinPrefs/KayokoPreferences 注册；资源与本地化完整。
5. 不包含本地配置、密钥、历史数据、测试 fixture 中的个人内容、设备地址或构建缓存。
6. SpringBoard 与 UIKit 目标互斥，druid/pasted 只有极小目标；符号/类清单与 hook ownership 一致。
7. 数据目录所有者/权限、可写路径和只读 public snapshot 规则正确，不能全目录 0777。
8. postinst/prerm/postrm/purge 无默认联网、旧数据删除、无条件提权导入或复制源项目 killall 行为。
9. 每个输出 SHA256、来源 commits、集成 commit、SDK、工具链、schema/协议版本进入 manifest。

Conflicts 至少覆盖三个旧包 ID `com.pixpin.screenshot / com.lindo.typex / com.lindo.kayokox`；TypeX 原 ActionBar/DockX 与 Kayoko 的既有冲突逐项评估合并。不要用 `Provides` 假装仍安装旧 dylib，不要用 `Replaces` 指望自动迁移私有数据。包管理器冲突替换流程和旧卸载脚本要在迁移前验证。

## 5. 真机测试前提

只有用户在当前任务主动明确发起 USB/SSH/设备连接时才连接。用户自行安装验收时，交付本节步骤和日志关键词即可，不主动探测设备、启动 iproxy 或读取设备内容。

记录机型、架构、准确 iOS 版本、RootHide/注入环境、Metis 版本、冷/热启动条件、来源旧数据版本、每一步结果与日志范围。设备日志默认脱敏，避免持续拉取造成额外负载。

目标覆盖 iOS16、iOS17 与实际支持的 arm64/arm64e 组合。不是要求测试不存在的机型/系统组合；缺少某组合要列 coverage gap，不能推断通过。

## 6. 设备验收矩阵

| ID | 场景/步骤 | 预期 |
| --- | --- | --- |
| DEV-01 | 新装后冷启动，所有模块关闭 | 能进设置，无业务浮层/采集，SpringBoard 不因 constructor 崩溃 |
| DEV-02 | 逐个启用，再全部启用，再总关闭 | 状态真实；关闭后 URL/手势/观察者无新业务 |
| DEV-03 | 普通 App、WKWebView、系统搜索、第三方键盘扩展输入 | 工具栏按能力出现；非键盘 appex 与受保护 UI 不误装 |
| DEV-04 | 顶底栏、短滑/长滑、子动作、键盘收起把手 | 原手势含义、容量、贴边入口保持，取消不误触 |
| DEV-05 | 状态栏左中右、Dock、横屏、灵动岛有/无绑定 | 配置动作准确；未配置保留系统行为；一手势一次 |
| DEV-06 | Kayoko 上滑/地球/听写与 TypeX 手势重叠 | 冲突按选择解决，无双重面板或系统操作丢失 |
| DEV-07 | PixPin 六模式、区域实时/冻结、拖动/调整/取消 | 捕获时机正确、按钮避让、输出不含自身 chrome |
| DEV-08 | 全屏与选区长截图，暂停继续、到尾、低内存 | 不缺末段；降级可见；中止清理可恢复 |
| DEV-09 | 编辑、撤销重做、保存/复制失败重试、气泡重编 | 无重复输出；旧相册资源不被意外覆盖 |
| DEV-10 | 剪贴板文本/图/富文本、历史收藏标签、筛选画廊 | 数据与来源正确，边界资源不崩溃 |
| DEV-11 | 悬浮预览出现后点击小球和桌面空白 | 小球可交互，空白透传，不抢 keyWindow |
| DEV-12 | 从输入框唤起历史粘贴，切换输入框/密码框/锁屏 | 仅原有效焦点可贴；失效不贴到新输入框 |
| DEV-13 | 截图复制，captureToHistory 关闭/开启 | 复制正常；历史按开关仅记录一次，不重复预览 |
| DEV-14 | 明确测试 OTP 通知并启用复制 | 验证码按配置复制；默认不入库/预览/日志/AI |
| DEV-15 | 悬浮 App 冷/热打开、最小化/恢复/六槽/缩放/关闭 | 输入触摸有效、会话正确；恢复耗时分阶段记录 |
| DEV-16 | AI 流式取消/附件、脚本超时/网络失败/候选输出 | 无迟到回调误写，凭据不进公共快照或日志 |
| DEV-17 | 全局搜索、动作改名/删除、应用规则、动态字号 | 路由高亮正确、引用影响清晰、可访问性正常 |
| DEV-18 | 导入三项目配置/历史，中途失败与再次导入 | 数据一致、无重复、旧源不改、失败回到前一 manifest |
| DEV-19 | 公共快照缺失/不可读/旧 schema，设置端写入失败 | 状态可理解，无危险默认或空配置覆盖 |
| DEV-20 | pixpin/kayokox/旧通知与新入口，模块关闭/忙/锁屏 | 别名遵守统一门控，内部无回环和双执行 |
| DEV-21 | 旋转、锁屏解锁、来电、前后台切换、键盘显示隐藏 | 窗口/手势/焦点不滞留；旧异步回调无效 |
| DEV-22 | 升级、卸载保留数据、重装、回滚旧版本 | 无静默丢数据；未知 schema 拒绝并有恢复方法 |

## 7. 性能与稳定性记录

先在同设备/OS/负载建立源模块单独运行、Metis 逐模块运行、Metis 全开启三组基线；记录空闲 CPU、SpringBoard/UIKit 内存、键盘首显、截图峰值/耗时、历史规模和查询延迟、长图片数/峰值、窗口数量与观察者数量。

预算要在首个可运行版本测量后固定到 performance.md，不能先拍脑袋写“零开销”。发布门槛至少包括：模块关闭无持续轮询/截屏/历史读取；重复开关不累积 observer/window；相同场景没有可重复的显著内存/延迟退化；发生退化必须分析并给出接受理由或修复。

浮窗恢复分别度量 request/prepare/scene-acquired/live，区分卡片中心和停靠栏 spinner；不要只看动画帧数。主机算法 benchmark 与设备体感分别报告。

## 8. 发布报告

发布候选报告需列出：集成 commit、包路径/SHA256、版本/SDK、功能对照完成率、源码审查结果、主机测试命令/结果、包检查结果、设备矩阵通过项/缺口、已知问题、迁移/回滚指引、许可来源清单。

未完成设备验收时表述为“已构建并完成包检查，真机待验”，不能写“iOS16/17 全面稳定”。没有发布/上传授权时交付本地产物与报告。
