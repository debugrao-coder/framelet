# 瞬帧 / Framelet

本地优先的 macOS / Windows 原生截图工具：区域截图、长截图、GIF 录制和文字提取。

**0.1 开发预览，不是稳定版。** macOS Apple Silicon 已完成部分本机验证；Windows 与 Intel Mac 仅构建检查，不代表实机可用性验收。

[预览下载](https://github.com/debugrao-coder/framelet/releases) · [MIT License](LICENSE)

## 功能与边界

| 能力 | macOS | Windows |
| --- | --- | --- |
| 区域截图 | ScreenCaptureKit；合成测试文档单窗口采集已在较早构建验证 | WGC/D3D11，受控 GDI 回退；实机待验证 |
| 长截图 | 手动滚动、自动采样/手动追加、暂停/撤回；合成拼接逐像素验证 | 手动追加/撤回，共享 Rust 配准；实机待验证 |
| GIF / 录屏 | H.264 MP4、GIF 导出、暂停与裁剪；合成编码测试通过，真实录屏待验证 | 流式 GIF；无 MP4、无暂停；实机待验证 |
| 文字提取 | Apple Vision，本地中英文 OCR | Windows 系统 OCR，需要 MSIX 包身份和识别语言包 |
| 编辑 | 矩形、箭头、画笔、实色遮盖、撤销/重做、缩放、PNG、剪贴板 | 矩形、箭头、文字、实色遮盖、撤销、PNG、剪贴板；实机待验证 |
| 快捷键 | 可配置、停用、恢复默认、冲突提示、保存及重启回读已验证 | 同类设置已实现并通过合成测试；系统注册及 UI 待实机验证 |

长截图需避开固定页眉/页脚；不能可靠匹配时拒绝追加。尚未实现通用固定栏去除、自动滚动或横向拼接。OCR 存在漏字、标点与空格误差，请复核重要文字。

## 隐私与权限

- 不需要账号，不内置云上传、遥测或音频录制。
- OCR 使用系统提供的本地识别能力，**无需配置 AI 模型或 API Key**。尚未接入生成式 AI 翻译或总结。
- macOS 截图需用户自行授予屏幕录制权限。普通区域截图会先获取各显示器画面供框选，再处理所选区域；不要在含敏感内容的桌面上运行测试。
- 当前 Mac 包采用临时开发签名，**未公证**。更新构建后权限可能需要重新确认；本次下载包的屏幕采集权限与真实采集尚未重新验证。不要为安装而全局关闭系统安全保护。
- `prototype/` 仅为合成样本交互预览，不访问真实屏幕，不是真实 OCR 或录屏实现。

## 快捷键

Mac 菜单 **瞬帧 → 设置…** 或 **⌘,**；Windows 工具条 **快捷键**。

| 功能 | 默认组合（双端） |
| --- | --- |
| 截图 | Control / Ctrl + Shift + 2 |
| 长截图 | Control / Ctrl + Shift + 3 |
| 录制 | Control / Ctrl + Shift + 4 |
| 提取文字 | Control / Ctrl + Shift + 5 |

点击“应用”才保存；取消不保存草稿。配置仅保存在本机用户目录。重复组合或注册冲突会提示；设置窗口内不会触发采集。Mac 字母采用物理键位映射，非 QWERTY 布局尚未验证。

## 从源码构建

### macOS

需要 macOS 14+、Xcode Command Line Tools、Rust 和 Swift。当前构建主机为 Apple Silicon；视觉采用 AppKit/SwiftUI 系统组件与语义颜色，材质效果取决于系统版本。

```sh
rustup target add aarch64-apple-darwin
bash scripts/build-mac.sh arm64
# 输出 build/arm64/Framelet.app，并运行合成自测及签名检查
```

Intel 交叉构建：

```sh
rustup target add x86_64-apple-darwin
bash scripts/build-mac.sh x86_64
```

未运行 Intel 产物；没有自动安装 Rosetta。构建脚本仅作临时签名，不申请证书或公证。

### Windows

需要 Windows 10 2004+ / Windows 11、.NET 8 SDK、Rust MSVC 与 Visual Studio C++ Build Tools；MSIX 打包还需 Windows SDK。

```powershell
rustup target add x86_64-pc-windows-msvc
./windows/build.ps1 -Architecture x64
# 需要 OCR 包身份时：
./windows/build.ps1 -Architecture x64 -Package
```

MSIX 未默认签名；脚本不会创建或信任证书，也不会自动安装。Windows 尚无真机验证，因此本次发布不提供“已验收”的 Windows 安装包。详见 [Windows 构建说明](windows/README.md) 与 [运行验收清单](windows/RUNTIME-CHECKLIST.md)。

### 合成测试与设计预览

```sh
cargo test --manifest-path core/Cargo.toml
cargo clippy --manifest-path core/Cargo.toml -- -D warnings
dotnet run --project windows/tests/GifMuxTests.csproj -c Release
cd prototype
npm ci
npm run build
npm run test:sites
npm run dev -- --host 127.0.0.1 --port 4317
```

Windows 无平台测试为 242 个断言；额外传入本机 Rust 动态库可执行 5 个 ABI 断言。Mac 自测覆盖拼接、保存保护、OCR 内容修订、历史、缩放与快捷键事务。编码测试使用合成帧；不代表真实采集、Windows UI 或性能验收。

## 发布状态

`v0.1.0-preview.1` 提供 MIT 源码与 Apple Silicon Mac 开发预览 ZIP。ZIP 内应用与发布前本机测试版本一致，但未经公证；不保证在其他机器上直接打开。

待完成：双端真实长截图/GIF 回归、Windows 安装与 OCR、Intel Mac 运行、混合 DPI/多屏、长时间资源与性能测试、正式签名/公证及升级回滚。**双端稳定发布：HOLD。**

本机原始测试截图、日志和工具链路径不上传公共仓库；目录内文档提及的本机 `artifacts/` 或 `*-validation` 文件不随源码分发。它们不能作为本仓 CI 通过或远端实机验收的证据。

## 项目结构与许可证

- `macos/`：AppKit / SwiftUI / ScreenCaptureKit / Vision
- `windows/`：WPF / WGC / WinRT OCR
- `core/`：Rust RGBA 垂直重叠检测与 C ABI
- `prototype/`：独立 React 设计预览
- `design/`：设计参考及原创生成图标；普通构建直接使用已生成资源

项目采用 [MIT](LICENSE)。依赖保留各自许可证；第三方商标及平台名称不表示官方背书。
