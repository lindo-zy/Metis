# 05 · 配置、数据迁移与恢复

本章定义目标格式与事务，不声称当前已有 importer。迁移只发生在 Metis 副本，默认不删除或回写旧项目数据。

## 1. 数据分类与唯一所有者

| 数据 | 权威所有者 | 共享范围 | 普通配置备份 |
| --- | --- | --- | --- |
| 用户配置、动作、绑定、规则 | Settings 配置服务 | 按进程裁剪后的快照 | 包含 |
| AI/API 凭据 | Private credential store | 仅获准的服务 | 默认排除 |
| 剪贴板数据库、图片、富文本、收藏、标签 | Clipboard repository | SpringBoard 服务；Settings 走维护接口 | 排除，单独数据备份 |
| 把手/浮窗位置、MRU、最后选区 | 模块 state store | 对应模块 | 可选且明确标记 |
| 截图临时图、长图切片、会话句柄 | Capture task store | 会话内授权访问 | 排除 |
| 来源、迁移报告、未知字段 | Migration journal | 设置/诊断，脱敏摘要 | 可包含无敏感摘要 |

历史数据目录目标为 RootHide 解析后的 `/var/mobile/Library/Metis/Clipboard/`；private config/credentials 与它分目录。不能把所有资源放 `/Library/Metis` 世界可读目录。

## 2. 新配置注册目录

每个 SettingDescriptor 必须登记 `settingID, path, type, default, range/enum, ownerModule, availability, applyPolicy, sensitivity, legacyMappings`。页面从注册目录生成/引用，迁移也从同一 schema 校验。

新装默认：global.enabled=true，三个模块 enabled=false；模块启用后普通参数按来源有效默认映射。剪贴板采集类型必须在启用流程由用户选择；跨模块自动记录、验证码、浏览器重定向和新全局手势默认关闭。

导入默认规则：**有有效旧值就保留旧值；缺失才采用迁移默认；数据不可读时终止该来源，不当成空配置。** 旧 enabled 进入候选配置，事务成功和用户选“导入后启用”之前不开放运行。

## 3. 关键键映射

以下是必须优先实现的映射，不是全部 key 清单；原始 specifier 与源码常量见 evidence。动态控制器内生成的设置必须由 M0 补全 schema，不能只迁首页 plist。

| 来源域 | 原 key/结构 | Metis 目标 | 转换规则 |
| --- | --- | --- | --- |
| com.lindo.typex | enabledBOOL | modules.keyboard.enabled | 保留 bool；受迁移激活门控 |
| com.pixpin.screenshot | Enabled | modules.capture.enabled | 独立字段，不与另一个 Enabled 合并 |
| com.lindo.kayoko.preferences | Enabled | modules.clipboard.enabled | 独立字段；包 ID 不能作为域 |
| com.lindo.typex | hapticBOOL | keyboard.feedback.haptic | bool |
| com.lindo.typex | smscodecopyBOOL | keyboard.otp.copyEnabled | 缺失 false，历史记录仍默认 false |
| com.lindo.typex | browserredirectBOOL | keyboard.browserRedirect.enabled | 缺失 false |
| com.lindo.typex | pasteimagechipBOOL / pasteimagechipapps | keyboard.pasteChip.enabled / applicationRules | 总开关 + 显式应用范围，空集合不表示所有应用 |
| com.pixpin.screenshot | AreaRememberLastRect | capture.selection.rememberRect | bool；关闭与清除缓存区分 |
| com.pixpin.screenshot | AreaLastSelectionRect / MarkupHandleOrigin | Capture state store | 有效几何才导入，旋转/尺寸变更后重新校验 |
| com.pixpin.screenshot | SelectionSnapEdgeDistance | capture.selection.snapDistance | 数值 0–60 pt，旧缺失 12 |
| com.pixpin.screenshot | DefaultResultAction | capture.output.defaultAction | 用源码 enum 显式映射，未知枚举待检查 |
| com.pixpin.screenshot | SaveAlsoCopy / ShowResultBubble | capture.output.saveAlsoCopy / showBubble | bool；不因此开启 captureToHistory |
| com.pixpin.screenshot | FloatingSnapShadow / ScreenshotHaptic | capture.pin.shadow / feedback.haptic | bool |
| com.pixpin.screenshot | EditorDefaultLineWidth | capture.editor.lineWidth | 校验 0.5–16 pt；缺失 4 |
| com.pixpin.screenshot | Editor*Order/Hidden/Names/Icons | capture.editor.buttons | 转为稳定 buttonID 记录；顺序与隐藏分别保留 |
| com.pixpin.screenshot | SelectionButton* / SelectionCustomButtons | capture.selection.buttons + actions | 旧逐行 CSV 由原解析规则读取，不能简单逗号 split |
| com.pixpin.screenshot | LongShot* | capture.longShot.* | 按 PXLongShotOptions 的当前枚举/范围逐项迁移 |
| com.lindo.kayoko.preferences | MaximumHistoryAmount / SaveText / SaveImages | clipboard.capture.* | 数量范围从当前 schema 得出，旧缺失最大量 200 |
| com.lindo.kayoko.preferences | PrivacyMode | clipboard.privacy.maskPreview | 只是显示遮罩，不宣称加密 |
| com.lindo.kayoko.preferences | FloatingPreview* | clipboard.preview.* | size 25–100、duration 3–10 等按源码检查 |
| com.lindo.kayoko.preferences | FloatingPanelScale / Color / HeightInPoints | clipboard.panel.* | 带单位与合法范围 |
| com.lindo.kayoko.preferences | ActivationMethod | bindings + migration.rawActivationMask | 位掩码逐 bit 转换；未知 bit 不丢失 |
| com.lindo.kayoko.preferences | AutomaticallyPaste / AutomaticPasteMode | clipboard.paste.* | 经典/模拟/自动保持枚举含义 |
| com.lindo.kayoko.preferences | ApplicationBlacklist | applicationRules[clipboard.record] | module scope deny，不能禁用整个 Metis |
| com.lindo.kayoko.preferences | IgnoreRemoteReplication | clipboard.capture.ignoreRemote | 保留用户旧值 |
| com.lindo.kayoko.preferences | InitialViewMode / ItemDetailsMode / PreviewLineCount | clipboard.panel.* | 显式 enum 映射，不按中文标题推断 |
| com.lindo.kayoko.preferences | *GalleryModeEnabled | clipboard.gallery.* | 保留历史/收藏两个维度，旧统一值仅作 fallback |
| com.lindo.kayoko.preferences | OverlayWindowLevel* | clipboard.advanced.legacyWindowPolicy | 保留原值作兼容，正常运行受 OverlayCoordinator 约束 |

颜色字符串、图标字符串、数值单位、URL 占位符都要保留语义。无法通过 schema 的字段隔离并出报告，不静默 clamp 到看似合理的新值；用户选择“采用建议修正”后才提交。

## 4. 动作、面板和绑定迁移

1. 建立旧模块/旧标识 → 新 UUID 映射表，先迁动作再迁引用。UUID 映射写入 journal，重复执行复用，不每次生成新副本。
2. TypeX 内置 selector 经白名单映射为 builtin ID；自定义 selector 只是旧标识，与动作种类/参数共同决定转换。
3. TypeX 分组、动作排序、折叠状态、面板、子动作和工具栏绑定分别保留。删除组不会删除动作，空动作和无效引用列入报告。
4. Kayoko 文本、图片、双击动作保留三个使用场景，不因为同名同 URL 就强行合并；可以后续显式合并，必须先展示引用影响。
5. `$$$` 与 `@@@` 转为有明确定义的模板 token。编码发生在哪一步按原执行语义建 fixture；避免重复 percent-encoding、破坏换行或把图片空文本误当剪贴板全文。
6. PixPin 自定义按钮保留 buttonID、名称、图标、URL、顺序/隐藏；动作存 UUID，按钮存引用。
7. 内容相同不等于同一动作；导入去重优先使用来源稳定标识，不按名字覆盖用户已经在 Metis 创建的动作。
8. 绑定到已关闭模块合法，运行返回 disabled；绑定到缺失/损坏动作保留 missing 标记，不能执行任意 fallback。

## 5. 旧数据发现与安装顺序

迁移必须支持两条路线：

- **推荐：先导出再替换。** 用户仍安装原插件时导出/生成只读快照，然后安装 Metis；Metis 从明确的备份导入。
- **残留数据导入。** 原插件已经移除但数据保留，Metis 检测逻辑旧域与数据库并展示来源；不能依赖旧 dylib 还存在来发现数据。

最终包与旧三个包冲突，安装包管理器可能先卸载旧包。M0 必须审查旧包 prerm/postrm 是否清数据；存在 purge 风险时先完成导出工具与替换指引，禁止用“旧数据通常还在”作为迁移保证。安装脚本不得自动联网、自动导入历史或清理旧目录。

可支持 `metis-migrate --dry-run --source …` 的离线工具，但这是待实现 CLI；不得在工具存在前写成已可执行。

## 6. 迁移事务与中断恢复

迁移状态：`detected → planned → backedUp → copying → validated → committed → activated`；任一步失败进入 failed，保留 journal。journal 不含正文/凭据，记录来源 ID、schema、目标 UUID 映射、校验数量/摘要和错误。

迁移标识用 `source domain + source format + source fingerprint + importer version`。相同来源指纹已经 committed 则无操作；来源有变化生成增量计划并展示，不自动覆盖现有配置。

事务步骤：

1. `dry-run` 校验权限、格式、磁盘空间、引用和待覆盖项；生成可读变更清单与风险说明。
2. 暂停目标模块采集/业务，等待数据库与截图输出空闲；获取维护锁。不能停掉整个系统粘贴服务充当数据库锁。
3. 生成 Metis 当前配置/数据一致备份，校验可读性后继续；首次没有目标数据也记录空基线。
4. 建立独立 staging 根，复制配置、动作、历史库、图片、富文本、标签；所有新路径经过 resolver。
5. 对 SQLite 使用受支持的一致快照/backup API。**不能只复制主 sqlite 文件忽略 WAL/SHM，也不能对仍在写的旧库直接 file copy。** 原插件仍在写且无法取得一致快照时终止并要求离线导出；失败不得破坏旧库。
6. 在副本上升级 schema、映射附件、保留收藏/标签/备注/来源/时间戳/富文本等字段。检查库完整性、行数、外键/逻辑引用、图片/富文本存在性与大小；损坏记录隔离并报告。
7. 将 staging 与 candidate config 验证完毕，目标目录通过同文件系统原子切换/manifest 指针切换提交；配置与数据跨存储无法一个 OS 事务完成，采用两阶段 journal，未完成的 manifest 不激活。
8. 提交成功后记 committed；仅用户选“启用”且所有依赖满足才 activated。清理 staging 不删除备份或旧来源。
9. 崩溃重启读取 journal：提交前清理/重试 staging；已切换但未激活先校验再完成提交；校验失败回到上一份 manifest。不得重复追加历史。

配置恢复和历史恢复可分别执行，但整个选择范围内必须一致；不能出现列表显示新标签但历史还指向旧 ID。

## 7. 备份文件格式

建议归档 `.metisbackup`（容器可用 ZIP），包含：

```text
manifest.json              # formatVersion、appVersion、schema、scope、hashes
config/config.json         # 无凭据的用户配置与动作绑定
resources/                 # 用户图标等必要资源
data/clipboard.sqlite      # 仅用户显式选择“含剪贴板数据”时
data/images/               # 对应附件
data/rich-text/
```

普通备份默认不含剪贴板历史、收藏正文、截图、凭据；“完整数据备份”需明确说明包括哪些私密内容。v1 如未实现加密，不展示“加密备份”选项，也不宣称压缩包安全保密。API key 由用户导入后重新填写。

导入必须限制归档总字节/文件数/解压比/单文件大小，校验类型/哈希，拒绝绝对路径、`..`、符号链接与重复归档路径；先解到隔离 staging，禁止解压直接覆盖目标。数字上限在实现中根据备份规模集中配置并测试，不无限制解压。

### 合并和覆盖

- 默认“合并”：新 UUID 合入，来源相同 UUID 发生差异则显示两侧摘要并选择保留/复制，不按名称覆盖。
- “覆盖所选模块”：先备份，再替换该模块配置和关联绑定，公共动作只有无人引用才删除；不影响其他模块业务数据。
- 完整数据恢复需维护锁、磁盘空间和一致校验；坏包拒绝提交，不通过重新启动掩盖错误。
- schema 比当前更新则拒绝并提示升级；旧 schema 逐版本升级到当前，未知字段保存在隔离 payload 并报告，不执行它。

## 8. 回滚与卸载

新版本升级前对配置/schema 做快照。数据库迁移采用扩展优先和版本化 schema，旧版本不能读新 schema 时拒绝启动并给出恢复路径，不在原库强行降级。

回滚到旧插件：停用 Metis → 在用户明确安装操作下移除冲突包 → 安装对应旧包 → 继续使用一直保留的旧数据或用户的旧版备份。Metis 运行后新增的历史不会自动同步回旧库，不能承诺零损失双向回滚；需要导出工具时单独实现和验收。

卸载 Metis 默认保留用户数据；清除数据是设置中的独立操作，需准确范围和确认。包管理器 purge 策略必须在发布说明中明示，不暗中删除剪贴板或旧项目目录。

## 9. 必要测试 fixture

- 三域都存在 `Enabled`/`enabledBOOL`，不会互相覆盖。
- 缺失、不可读、损坏、空但有效、未知新 schema 五种输入有不同结果。
- TypeX 深层动作/面板/子动作、同名动作、缺失引用、停用按钮与符号图标完整往返。
- Kayoko v4 SQLite + WAL、历史/收藏/标签/富文本/备注/图片、缺失附件、超量历史、旧 JSON 来源。
- PixPin 自定义 URL 中逗号/换行/中文/percent 编码、隐藏按钮、未知枚举与几何数据。
- 中断发生在每个 journal 阶段，重复导入不重复记录；恢复失败保留旧 manifest。
- 导出不含凭据；普通配置导出不含历史正文；恶意归档无法越过 staging 根。
