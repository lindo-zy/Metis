# Metis 实施记录 · v0.1.0 集成切片

日期：2026-10-17。本文记录从设计基线（main@7a53067）到本集成切片的实际实现、
偏差决策与验证证据。按 06-agent-work-plan 的任务报告模板维护。

## 1. 来源与集成基线

| 项 | 值 |
| --- | --- |
| 集成分支 | codex/metis-v1（worktree /Users/xiao/dev/github/Metis-wt） |
| 文档基线 | main@7a53067 |
| 来源固定 | evidence/source-baseline.json：TypeX dfc9a5b1 / PixPin 973b1b1a / KayokoX 61b7a8d3 |
| 导入方式 | 固定来源工作区整目录复制（保留 PX/DX/Kayoko 前缀，04 §1） |

## 2. 包与目标结构（实现态）

```
Library/MobileSubstrate/DynamicLibraries/
  MetisSpringBoard.dylib  （filter: com.apple.springboard）
    = PixPin 全量 + TypeX SB 侧（DXServer/状态栏手势/全局面板/SMS/浏览器重定向
      + broker/悬浮托管/把手/AI 桌面桥）+ Kayoko Core 全量 + 模块适配器
  MetisUIKit.dylib        （filter: com.apple.UIKit；constructor 对 SB 立即 return）
    = TypeX.xm 键盘 hook/悬浮粘贴/横向手势 + Kayoko Helper 全量
  MetisPasteServices.dylib（filter: druid/pasted）
    = KayokoPasteTipHooks 最小目标（内联门控判定）
Library/Metis/Frameworks/MetisCore.dylib
    = MT* 公共类 + 跨镜像共享 DX 类 + Kayoko Shared + vendored AltList
Library/PreferenceBundles/
  MetisPrefs.bundle            统一设置壳（唯一入口）
  MetisCapturePrefs.bundle     PixPin 详细设置（无独立 loader 注册）
  MetisKeyboardPrefs.bundle    TypeX 详细设置（同上）
  MetisClipboardPrefs.bundle   KayokoX 详细设置（同上）
Library/PreferenceLoader/Preferences/Metis.plist（唯一入口 + 图标）
usr/share/doc/com.lindo.metis/LICENSE-NOTICE
```

## 3. 门控与配置（v1 语义）

- 权威域 `com.lindo.metis`：`enabled`（总开关，默认开）、`captureEnabled`、
  `keyboardEnabled`、`clipboardEnabled`（默认关，ADR-014）。
- 唯一写入者：设置壳（MTConfigService）；变更广播
  `com.lindo.metis/config-changed`，运行端 MTModuleGate 重读。
- 模块桥接点（原读层单点替换，不改业务面）：
  - Capture：`PXPreferences.reload` → `PXConfig.enabled = MTModuleGate`；
  - Keyboard：`DXPrefsManager.readPrefs` 覆盖 `enabledBOOL`（含沙盒快照链路）；
  - Clipboard：`KayokoCoreRuntime.loadPreferences` 覆盖 `self.enabled`；
  - PasteServices：`KayokoPasteTipHooks` 内联判定（模块关闭放行系统行为）。
- 旧域（com.pixpin.screenshot / com.lindo.typex / com.lindo.kayoko.preferences）
  仅承载细节参数；旧 Enabled/enabledBOOL 行已从三个子包根页移除。
- 已知语义：Clipboard 业务观察者按 SB 启动时门控安装（沿 Kayoko 原语义），
  模块开关跨重启生效，设置页显示“等待运行状态”。

## 4. 偏差决策（对设计文档的 v1 修订，按 08 §1 ADR 流程登记）

| 编号 | 决策 | 理由与边界 |
| --- | --- | --- |
| ADR-011a | AltList 采用 vendored 单副本编入 MetisCore（替代外部依赖） | 目标与 ADR-011 一致（消除重名）；外部 AltList.framework 与 TypeX vendored 修改版若并存会在 Preferences.app 重名。vendored 副本（MIT，含 TypeX 修改与 README 记录）单一编译，四个子包共享；control 移除 com.opa334.altlist 依赖 |
| ADR-015a | 详细设置以三个 Metis*Prefs 子包分载，设置壳 dlopen 后压栈 | 02/03 的“单一 bundle + descriptor 统一”为 MT-013 终态；子包方案保本地化表/资源互不冲突，且均无独立 PreferenceLoader 入口（满足“唯一入口”硬约束）。MT-013 完成后合并 |
| ADR-016a | TypeX/ kayak 原域细节键暂为运行细节载体 | 05 的完整键映射迁移（legacy-settings-map 落地）属 MT-013/014；启停权威已收敛到 com.lindo.metis，不存在双权威 |
| ADR-017a | 键盘 appex 沙盒读桥（/Library/TypeX 快照，0777）暂保留 | 属非敏感细节配置的既有通道（01 §2 已登记现状）；MT-004 RootHide 沙盒 POC 后替换为受控通道，不作为新权威源 |

## 5. 功能对照（feature-parity 摘要）

状态枚举：ported（源码迁入、随包构建）/ host-verified / package-verified /
device-verified / deferred-with-reason。本切片整体状态：
**package-verified（iOS16/17 双包构建+包检查通过）；全部功能待真机验证。**

| 模块 | 功能组 | 状态 | 说明 |
| --- | --- | --- | --- |
| Capture | 六模式截图/长截图/编辑器/输出/气泡/外部兼容 | ported | PX 源码整体迁入，enabled 桥接门控 |
| Keyboard | 工具栏/面板/动作/手势/AI/脚本/悬浮 App/把手/SMS/重定向 | ported | 按进程拆分：键盘侧入 UIKitHost，系统能力入 SpringBoard |
| Clipboard | 历史/收藏/标签/面板/悬浮预览/粘贴/来源图标/Snapper 兼容 | ported | Core 入 SB、Helper 入 UIKitHost、粘贴提示入 PasteServices |
| 统一设置 | 唯一入口/总开关/模块开关/状态行/关于/模块页导航 | package-verified | 搜索索引/深链（MT-005 全量）与全部编辑器（MT-013）延期 |
| 迁移/备份 | 三域导入/预览/回滚 | deferred | MT-014；旧域键保留可手动迁移，未实现自动导入 |
| Updater 导入工具 | 旧数据提权导入 | deferred | 04 §4.11：不默认携带旧提权工具，独立评估 |

## 6. 验证证据

- 主机测试：`Tests/Host/run-host-tests.sh`——MTModuleGate 默认值/写入/总开关
  压制/reload 语义，13 项断言通过（隔离随机域，不污染宿主偏好）。
- 构建/包检查：`./build.sh --target ios16 --mode verify` 与 `--target ios17`
  均产出 deb 并通过 `Tests/Package/package-check.sh` 全部 6 组检查
  （元数据/唯一入口/敏感文件/依赖 install_name/架构/版本一致）。
- 类唯一性：`Tests/Package/class-audit.sh` 按 SpringBoard/App/Preferences/
  PasteServices 四个真实共载组审计 ObjC 类重名——PASS。
- 真机验证：未执行（无用户设备连接授权）。按 07 §1 只能报告
  源码/主机/包级结果；DEV-01…DEV-22 矩阵全部待验。

## 7. 回滚方式

卸载 com.lindo.metis deb 恢复原三插件（本包 Conflicts 明确声明互斥，安装
前需先移除旧包）。配置不迁移不覆盖：com.lindo.metis 域独立于三个旧域，
卸载 Metis 不影响旧插件配置。
