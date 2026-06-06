# yas_local

YAS 批改助手 — 本地运行的 Flutter 桌面/iOS App，调用阿里云 Qwen 视觉模型批改扫描的试卷。所有数据存本地 JSON，无后端。

更多架构与流程说明见 [`docs/grading-redesign.md`](../docs/grading-redesign.md)。

## 开发命令

```bash
flutter pub get              # 安装依赖
flutter run -d macos         # macOS 桌面（主要开发目标）
flutter run -d ios           # iOS 模拟器
flutter test                 # 跑所有测试
flutter analyze              # 静态分析
```

## 日志

所有对 Qwen API 的调用记录都通过 Debug sink 落盘，格式为 NDJSON（一行一对象）。**不再需要手动 `cat` 日志**——使用 app 内 `/debug` 屏查看，或在每个 tab 点 Export 导出 JSON 文件（macOS 弹 Finder 高亮，iOS 弹 share sheet）。

磁盘落盘仍可用作离线排查：
- **macOS**: `~/Library/Containers/cn.yas.yasLocal/Data/Library/Application Support/log/yas_YYYY-MM-DD.log`
- **iOS**: sandboxed，导出方式同 Debug 屏 Export

## Getting Started（Flutter 脚手架）

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
