# Metis

Metis 是一个 iOS RootHide 插件：**一个安装包、一个系统设置入口、三个可独立开关的模块**——截图与标注、键盘与操作、剪贴板。

- 系统设置 → Metis 是唯一入口；总开关与三个模块开关独立控制（默认仅总开关开）。
- 截图与标注：全屏/区域/冻结/即时/标记/滚动长截图、编辑器、输出与气泡。
- 键盘与操作：顶/底工具栏、键盘面板、六槽手势、自定义动作、AI、脚本、悬浮
  应用与停靠栏、状态栏/Dock 手势、短信验证码、浏览器重定向。
- 剪贴板：文本/图片/富文本历史、收藏、标签、搜索、画廊、悬浮预览、粘贴与
  焦点恢复。

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

按进程最小注入：

| 目标 | 注入范围 | 内容 |
| --- | --- | --- |
| MetisSpringBoard.dylib | SpringBoard | 截图引擎 + 系统能力（open broker/全局手势/悬浮托管）+ 剪贴板核心 |
| MetisUIKit.dylib | UIKit 宿主（SB 内立即返回） | 键盘工具栏/面板 hook + 剪贴板键盘宿主辅助 |
| MetisPasteServices.dylib | druid / pasted | 粘贴提示最小 hook（可关） |
| MetisCore.dylib | 以上全部链接 | MT* 公共类 + 跨镜像共享层 + vendored AltList |
| MetisPrefs.bundle | 系统设置 | 统一设置壳（唯一入口） |

配置权威域 `com.lindo.metis`（Settings 唯一写入者）。

## 许可

本项目代码以 **GPL-3.0** 发布（全文见 [LICENSE](LICENSE)）：使用、修改或再分发
本项目代码的作品必须以同等许可开源。第三方组件（AltList，MIT，vendored）说明
见 [LICENSE-NOTICE](LICENSE-NOTICE)。
