# TimbreCanvas

TimbreCanvas 是一款本地优先的原生 macOS 语音创作工具。它用 SwiftUI 提供手绘纸感界面，通过常驻推理进程调用外置的 IndexTTS 2 MLX 运行时；应用仓库不包含模型权重、用户音色或生成音频。

## 功能

- IndexTTS 2 文本转语音、8 维情绪、语速与高级采样参数
- 官方示例音色与本地音色克隆
- 已提取音色重命名、搜索和删除
- 保存“音色 + 情绪 + 语速 + 完整生成参数”预设
- 选择导入音频和导出目录
- 常驻推理进程，模型只需加载一次
- 模型中立的引擎接口，可继续接入其他本地 TTS 模型

## 系统要求

- Apple Silicon Mac
- macOS 14 或更高版本
- 16 GB 统一内存起步，推荐 24 GB 或更多
- 首次安装建议预留至少 20 GB 空间
- Xcode Command Line Tools（用于从源码构建 App）

## 一条命令配置 App 和模型

克隆仓库后运行：

```bash
./script/setup.sh
```

脚本会在下载前展示外部模型许可证，随后完成：

1. 校验本机架构、内存和磁盘空间；
2. 下载并校验固定版本的 `uv`；
3. 从固定提交安装第三方 MLX 端口；
4. 从官方 Hugging Face 仓库下载 IndexTTS 2 及外部声码器/编码器；
5. 在本机转换为 8-bit MLX 权重并验证 SHA-256；
6. 下载官方示例声音并预计算音色；
7. 构建 App，默认安装到 `$HOME/Applications/TimbreCanvas.app`。

把大型模型放在外置磁盘：

```bash
./script/setup.sh --install-root "/Volumes/ExternalAI/TimbreCanvas"
```

复用已经验证的 MLX-IndexTTS 项目：

```bash
./script/setup.sh --reuse-runtime "/path/to/mlx-indextts"
```

完整参数见：

```bash
./script/setup.sh --help
```

## 使用说明

中文版完整手册见 [docs/使用说明.md](docs/使用说明.md)。

## 隐私与许可证

TimbreCanvas 不提供遥测、云端上传或账号系统。音频、音色、预设和生成结果保留在用户选择的本地目录。详见 [PRIVACY.md](PRIVACY.md)。

本仓库中的 App 与运行时适配代码采用 MIT License。外部模型不属于本仓库，也不受本仓库 MIT License 覆盖；其中部分模型包含非商业或其他使用限制。安装前请阅读 [THIRD_PARTY_MODELS.md](THIRD_PARTY_MODELS.md)。

## 开发

```bash
swift test --package-path App
PYTHONPATH=RuntimeHost python3 -m pytest RuntimeHost/tests Installer/tests
./script/package_app.sh --debug
```

安全政策与当前已知上游风险见 [SECURITY.md](SECURITY.md)。

作者：[ZacharyJiao](https://github.com/ZacharyJiao)
