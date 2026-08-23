# cpsmart

cpsmart 是一个轻量的原生 macOS 菜单栏剪贴板历史工具。它在本机记录复制过的文本、图片和文件，按 `⇧⌘V` 会在当前屏幕底部弹出铺满当前显示器宽度的横向历史记录。

## 功能

- 自动记录文本、图片和文件复制历史
- `⇧⌘V` 全局快捷键呼出底部浮窗
- 固定深色的简约界面，内容卡片占满浮窗主体区域
- 移动鼠标、单击卡片或按 `←` / `→` 都可选择，所有卡片保持等大
- 选择后立即写入系统剪贴板；按回车会返回原应用并自动执行 `⌘V`
- `Esc` 关闭，退格键删除所选记录
- 相同内容自动去重，最新记录排在最前
- 支持清空和暂停记录
- 历史最多 200 条、数据最多约 25 MB；单张图片最大 8 MB
- 自动忽略密码管理器标记为隐藏、临时或自动生成的剪贴板内容
- 历史只保存在本机 `~/Library/Application Support/cpsmart/history.json`
- 可选“登录时启动”

## 安装

1. 打开 `dist/cpsmart-1.4.0-universal.dmg`。
2. 把 `cpsmart.app` 拖到 `Applications`。
3. 从“应用程序”启动 cpsmart，菜单栏会出现剪贴板图标。

当前构建使用 ad-hoc 本地签名，适合在本机安装。若要公开分发，需要 Apple Developer ID 证书并完成 notarization（公证）。

第一次使用“回车直接粘贴”时，macOS 会请求“辅助功能”权限。请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 cpsmart；该权限只用于向你原来所在的应用发送一次 `⌘V`。

## 开发与构建

要求 macOS 13 或更高版本，以及 Apple Command Line Tools。无需完整 Xcode。

```bash
bash Scripts/run_tests.sh
bash Scripts/build_dmg.sh
```

构建脚本会分别编译 Intel 和 Apple Silicon 版本、合并为 Universal 2 应用，并在 `dist/` 生成 DMG。

## 隐私说明

剪贴板历史可能包含隐私信息。cpsmart 不联网、不上传历史，并会跳过带标准敏感标记的内容；但不是所有应用都会正确设置这些标记。处理敏感数据时，可从菜单栏选择“暂停记录”，并定期清空历史。
