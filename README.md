# AlgerMusicPlayer-Themes

**[AlgerMusicPlayer-WinUI3](https://github.com/TencenTiM/AlgerMusicPlayer-WinUI3)** 的官方在线主题与壁纸仓库。

客户端打开「系统设置 → 个性主题 → 主题工坊 / 主题市场」即可自动连接本仓库，点击 **「刷新主题仓库」** 获取最新上架主题，支持图片/视频壁纸自动下载安装。

## 仓库目录结构

- `index.json`：客户端默认拉取的在线主题清单
- `themes/`：各主题独立归档文件（`*.algertheme.json`）
- `wallpapers/`：主题关联的高清图片壁纸与动态视频壁纸
- `previews/`：可选的主题自定义预览截图
- `inbox/`：待上架收件箱（放入导出主题文件后一键发布）

## 如何上架 / 更新主题

1. 在 AlgerMusicPlayer 客户端中调试好主题后，点击 **导出主题 (.algertheme.json)**；
2. 将导出的 `.algertheme.json` 文件放入本仓库的 `inbox/` 目录（如果是**动态视频壁纸**主题，可把同名 `.mp4`/`.webm` 一起放入 `inbox/`）；
3. 双击根目录下的 `一键发布inbox主题.bat`（或执行 `.\publish-theme.ps1`）；
4. 脚本会自动提取壁纸、更新 `themes/` 与 `index.json`（同 ID 自动覆盖更新，新主题自动置顶），并自动提交推送到 GitHub `main` 分支。

### 脚本可选参数

```powershell
# 指定分类或作者，或仅本地生成暂不推送
.\publish-theme.ps1 -Category "光学壁纸" -Author "TencenTiM" -NoPush
```

## 客户端默认订阅地址

```text
https://raw.githubusercontent.com/TencenTiM/AlgerMusicPlayer-Themes/main/index.json
```
