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

所有对 Qwen API 的请求与错误都会写入磁盘日志，方便排查批改异常。

- **路径**：`getApplicationSupportDirectory()/log/`，按天切分
- **文件名**：`qwen_YYYY-MM-DD.log`；单文件超过 5 MB 时切到 `qwen_YYYY-MM-DD.1.log`、`.2.log` …
- **包含**：每次调用的 `model` / `endpoint` / `status` / `elapsed`、消息文本（不含图片 base64）、响应内容；失败时额外记录 `error type` / `message` / 响应体摘要
- **不含**：图片 base64（图片只记张数）、`Authorization` header

### macOS 找日志

```
~/Library/Containers/cn.yas.yasLocal/Data/Library/Application Support/log/
```

直接 `cat` 或 `grep ERROR` 即可。

### iOS 找日志

iOS 沙盒里默认拿不到。如需导出，可在 Xcode → Devices and Simulators → Download Container → 右键显示包内容，路径为 `AppData/Library/Application Support/log/`。

> 早期版本（`Directory('log')` 相对路径）的旧日志在沙盒根 `Library/Containers/cn.yas.yasLocal/Data/log/`，新版本不再写那里，可手动删除。

## Getting Started（Flutter 脚手架）

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
