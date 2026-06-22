# 清风航线（Qingfeng Flight Reminder）

一款原生 macOS 菜单栏应用。当“提醒事项”中还有今天未完成的任务时，飞机会拖着横幅飞过屏幕提醒你。

## 功能

- 仅读取系统“提醒事项”中今天到期且尚未完成的任务
- 飞机与螺旋桨动画，支持多显示器
- 鼠标悬停时暂停飞行，移开后继续
- 菜单栏查看、刷新并直接完成提醒
- 可设置检测间隔与勿扰时段
- “测试飞行”使用当天的真实提醒数据
- 数据完全保留在本机，不上传到任何服务器

## 安装

1. 从 [Releases](../../releases/latest) 下载 `Qingfeng-Flight-Reminder-macOS.zip`。
2. 解压后把“清风航线.app”拖入“应用程序”文件夹。
3. 首次打开时允许访问“提醒事项”。

当前发布包采用临时签名、尚未经过 Apple 公证。如果 macOS 提示无法验证开发者，请在 Finder 中按住 Control 点击应用，选择“打开”，再确认一次。

系统要求：macOS 14 或更高版本。Release 为 Universal 2，支持 Apple Silicon 与 Intel Mac。

如需开机启动，可前往“系统设置 → 通用 → 登录项”，把“清风航线”加入“登录时打开”。

## 从源码构建

需要 Xcode 16 或兼容的 Swift 5.10+ 工具链。

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/清风航线.app"
```

构建 Universal 2 版本：

```bash
UNIVERSAL=1 ./scripts/build-app.sh
```

## 隐私

清风航线只通过 Apple EventKit 在本机读取和更新提醒事项。应用没有账号系统、网络服务、分析 SDK 或遥测，不会收集或上传提醒内容。

## 开源许可

[MIT License](LICENSE)
