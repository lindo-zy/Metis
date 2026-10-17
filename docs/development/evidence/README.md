# 源码调查证据归档

生成日期：2026-10-17；生成方式：读取本地仓库 Git 状态、control、选定文件哈希、设置 plist 和常量声明。没有运行构建、执行源脚本或读取个人凭据。

| 文件 | 内容 | 边界 |
| --- | --- | --- |
| [source-baseline.json](source-baseline.json) | 三仓库分支/HEAD/工作区、control 版本、关键文件 SHA256 与跟踪状态 | 哈希来自调查时工作区，Kayoko build.sh 与 HEAD 不同 |
| [legacy-settings-specifiers.json](legacy-settings-specifiers.json) | 69 个带 key/detail/action 的 plist specifier 原始记录 | 包含导航/操作；不等于 69 个设置，不覆盖动态控制器 |
| [legacy-key-declarations.json](legacy-key-declarations.json) | 182 条选定源码内的键/域/路径相关声明，带来源行号 | 是迁移检索种子，不是完整配置 schema |
| [document-review.md](document-review.md) | 本次文档链接、格式、任务与来源复核结果 | 仅文档交付检查，不是插件测试报告 |

三个 JSON 都是证据副本，不能直接当可执行配置导入。specifier 的 default/value 与运行 reader 不一致时，应沿源码核对并记录差异，不能盲信任一侧。

本手册以源码事实为基础，历史项目经验只用于提醒启动、设备授权和测试边界；所有当前版本/入口/存储结论均在本次重新查阅。后续来源发生变化，保留本快照，新增带日期快照和设计差异，不覆盖历史。
