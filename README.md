# 在 Cursor 中运行 InfraView

本项目是一个 macOS SwiftUI 应用，可以通过以下几种方式在 Cursor 中运行：

## 方法 1: 使用任务（Tasks）运行（推荐）

1. **按 `Cmd+Shift+P`** 打开命令面板
2. 输入 `Tasks: Run Task`
3. 选择以下任务之一：
   - **Build InfraView** - 仅构建项目
   - **Build and Run InfraView** - 构建并运行应用

## 方法 2: 使用调试配置运行

1. 点击左侧的 **运行和调试** 图标（或按 `Cmd+Shift+D`）
2. 在顶部下拉菜单中选择 **"Run InfraView"**
3. 点击绿色的运行按钮（或按 `F5`）

这将自动构建项目并启动应用。

## 方法 3: 使用终端脚本运行

在终端中运行：

```bash
./run.sh
```

这个脚本会自动构建项目并启动应用。

## 方法 4: 使用 Xcode（最标准的方式）

虽然可以在 Cursor 中运行，但对于 macOS 应用，**使用 Xcode 仍然是最推荐的方式**：

1. 双击 `InfraView.xcodeproj` 在 Xcode 中打开项目
2. 选择目标设备（Mac）
3. 按 `Cmd+R` 运行

## 注意事项

- 确保已安装 **Xcode Command Line Tools**：
  ```bash
  xcode-select --install
  ```

- 如果遇到权限问题，可能需要先构建一次：
  ```bash
  xcodebuild -project InfraView.xcodeproj -scheme InfraView build
  ```

- 构建产物位于 `./build/Build/Products/Debug/` 目录

## 快捷键

- `Cmd+Shift+B` - 运行默认构建任务
- `F5` - 开始调试
- `Cmd+Shift+P` - 打开命令面板

