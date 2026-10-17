# Metis

Metis 将 PixPin（截图与标注）、TypeX（键盘与操作）和 KayokoX（剪贴板）整合为
一个 iOS RootHide 插件：**一个安装包、一个系统设置入口、三个可独立开关的模块。**

- 系统设置 → Metis 是唯一入口；总开关与三个模块开关独立控制（默认仅总开关开）。
- 截图与标注 · PixPin：全屏/区域/冻结/即时/标记/滚动长截图、编辑器、输出与气泡。
- 键盘与操作 · TypeX：顶/底工具栏、键盘面板、六槽手势、自定义动作、AI、脚本、
  悬浮应用与停靠栏、状态栏/Dock 手势、短信验证码、浏览器重定向。
- 剪贴板 · KayokoX：文本/图片/富文本历史、收藏、标签、搜索、画廊、悬浮预览、
  粘贴与焦点恢复。

## 构建与发布

```bash
./build.sh --help
./build.sh --target all --mode verify                 # 主机测试 + 双平台构建 + 包检查
./build.sh --target all --mode release --version 0.1.0 # 发布构建（manifest + 版本写回）
```

要求：Theos（roothide fork，`THEOS` 环境变量或默认路径）与 iPhoneOS16.5/17.0 SDK。
产物：`packages/ios16|ios17/com.lindo.metis_<版本>_<平台>_iphoneos-arm64e.deb`。

推 tag（`v*`）后 GitHub Actions 自动双平台构建并发布 Release（见
`.github/workflows/release.yml`）。

## 架构

按进程最小注入（详见 [docs/development/03-architecture.md](docs/development/03-architecture.md)）：

| 目标 | 注入范围 | 内容 |
| --- | --- | --- |
| MetisSpringBoard.dylib | SpringBoard | PixPin 全量 + TypeX 系统能力 + Kayoko Core |
| MetisUIKit.dylib | UIKit 宿主（SB 内立即返回） | TypeX 键盘 hook + Kayoko Helper |
| MetisPasteServices.dylib | druid / pasted | 粘贴提示最小 hook（可关） |
| MetisCore.dylib | 以上全部链接 | MT* 公共类 + 跨镜像共享层 + vendored AltList |
| MetisPrefs.bundle | 系统设置 | 统一设置壳（唯一入口） |

配置权威域 `com.lindo.metis`（Settings 唯一写入者）；与旧三包互斥（Conflicts），
旧配置域保留、不迁移不覆盖。当前实现状态与偏差决策见
[docs/implementation/implementation-report.md](docs/implementation/implementation-report.md)。

## 许可

TypeX（AGPL-3.0）、KayokoX（GPL-3.0）、AltList（MIT，vendored）；来源与许可清单
见 [LICENSE-NOTICE](LICENSE-NOTICE)。
