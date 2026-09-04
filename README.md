<div align="center">
  <img src="KeyDiary/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="键盘日记图标">
  <h1>键盘日记</h1>
  <p>在 Mac 上记录、观察与回放你的每一次按键。</p>
</div>

键盘日记是一款原生 macOS 菜单栏应用。它通过一张可视化键盘呈现实时输入，按日期与 App 汇总按键次数，并可以回放历史记录、导出键盘动画视频，或让整张键盘变成一块像素视频屏幕。

> [!NOTE]
> **AI 生成声明：** 本项目完全由人工智能生成，包括产品设计、代码实现、资源整理、测试与文档编写。

## 功能亮点

- **实时键盘**：同步高亮当前按下的普通键、修饰键和部分系统功能键。
- **按键统计**：按今天、最近若干天、全部时间或自定义日期筛选，并支持按前台 App 过滤；键盘可在 QWERTY 与 A–Z 排列间切换。
- **历史回放**：在时间轴上选择区间，以不同速度重放按键轨迹，并可同步播放按键音效。
- **视频导出**：将回放或像素影院画面导出为 MP4/MOV，支持 H.264、HEVC、带透明通道的 ProRes 4444，以及 720p、1080p、4K 和多种帧率。
- **像素影院**：把视频采样到 14 × 6 的键帽矩阵，支持彩色/黑白、适合/填充/拉伸、反相、循环播放和原片同步预览。
- **悬浮键盘**：以无边框窗口展示实时键盘，适合录屏、直播或演示。
- **键盘音效**：内置多种机械轴体采样和三种钢琴演奏模式，可调节音色与音量。
- **数据管理**：分页查看、筛选和删除记录；支持 JSON、CSV、Excel 的合并/替换导入与导出。
- **菜单栏常驻**：可快速查看今日按键数、打开主界面或悬浮键盘、切换音效，并可设置登录时启动。
- **个性化外观**：支持跟随系统、浅色、深色外观以及自定义主题色。

## 系统要求

- macOS 15.0 或更高版本
- Xcode 27 或更高版本（工程当前使用 Xcode 27 项目格式）
- Swift Package Manager 可访问 GitHub，以便首次构建时获取 `ZIPFoundation`

## 从源码运行

```bash
git clone https://github.com/MrSouthWall/KeyDiary.git
cd KeyDiary
open KeyDiary.xcodeproj
```

在 Xcode 中选择 `KeyDiary` scheme 和 `My Mac`，必要时在 **Signing & Capabilities** 中选择你自己的开发团队，然后运行项目。

应用第一次启动时不会自动弹出主窗口，而是驻留在菜单栏。点击菜单栏中的键盘图标进入设置，并按提示前往：

> 系统设置 → 隐私与安全性 → 输入监控

授权“键盘日记”后重新启用记录即可。

仓库也提供了开发脚本。若 `/Applications/Xcode-beta.app` 存在，脚本会优先使用它：

```bash
./script/build_and_run.sh             # 构建并运行
./script/build_and_run.sh --debug     # 使用 LLDB 启动
./script/build_and_run.sh --logs      # 查看应用进程日志
./script/build_and_run.sh --telemetry # 查看键盘日记子系统日志
./script/build_and_run.sh --verify    # 构建、运行并检查进程
```

## 运行测试

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project KeyDiary.xcodeproj \
  -scheme KeyDiary \
  -destination 'platform=macOS' \
  -derivedDataPath .build
```

如果你的默认 Xcode 已能打开该工程，可以省略 `DEVELOPER_DIR`。

## 隐私与数据

键盘日记使用只读的系统事件监听，不会拦截或修改原始键盘事件。每条记录包含：

- 时间戳
- 键码与按键标签
- 当时位于前台的 App 名称及 Bundle ID

数据默认仅保存在本机 SQLite 数据库中：

```text
~/Library/Application Support/KeyDiary/key-diary.sqlite
```

应用代码不会主动把按键记录上传到网络。需要注意的是，连续的按键标签仍可能暴露密码、聊天内容或其他敏感信息。请只在你信任的设备上使用，妥善保管导出的 JSON、CSV、Excel 和视频文件，并在不需要时暂停记录或清除数据。

## 数据导入与导出

设置中的“数据”区域支持以下格式：

| 格式 | 导入 | 导出 | 适用场景 |
| --- | :---: | :---: | --- |
| JSON | ✓ | ✓ | 完整备份与恢复 |
| CSV | ✓ | ✓ | 按键与鼠标点击的文本处理和数据分析 |
| Excel (`.xlsx`) | ✓ | ✓ | 按键与鼠标点击的表格查看和整理 |

导入时可选择：

- **合并导入**：保留现有记录，并按记录 ID 跳过重复项。
- **替换导入**：先创建 JSON 备份，再用导入文件替换本机记录；导入失败时不会提交数据库变更。

## 技术栈

- Swift、SwiftUI、Observation
- AppKit、ApplicationServices / Core Graphics Event Tap
- SQLite3
- AVFoundation、Core Image、Core Video
- ServiceManagement
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)（Excel 文件读写）

## 项目结构

```text
KeyDiary/
├── KeyDiary/                  # 应用源码与资源
│   ├── Models/                # 按键、布局、像素帧与编辑器模型
│   ├── Services/              # 键盘监听、音效、数据传输与视频导出
│   ├── Stores/                # 应用状态与 SQLite 持久化
│   ├── Support/               # 主题、窗口、登录项和文件面板支持
│   └── Views/                 # 主界面、设置、时间轴与悬浮窗口
├── KeyDiaryTests/             # 数据库、Store、布局与像素帧测试
├── script/build_and_run.sh    # 本地构建、运行与调试脚本
├── LICENSE                    # MIT 开源许可证
└── THIRD_PARTY_NOTICES.md     # 第三方资源声明
```

## 开源许可

键盘日记基于 [MIT License](LICENSE) 开源。你可以自由使用、复制、修改、合并、发布和分发本项目，但须保留原始版权与许可声明。

## 第三方资源

机械键盘音效来自 [tplai/kbsim](https://github.com/tplai/kbsim)，详细许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。依赖版本锁定在 Swift Package Manager 的 `Package.resolved` 中。
