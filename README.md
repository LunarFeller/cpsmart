# ClipShelf

ClipShelf 是一个轻量的原生 macOS 菜单栏剪贴板历史工具。它在本机记录复制过的文本、图片和文件，按 `⇧⌘V` 可随时搜索并重新选择一条记录。

## 功能

- 自动记录文本、图片和文件复制历史
- `⇧⌘V` 全局快捷键呼出，方向键选择，回车复制回剪贴板
- 搜索、删除、清空和暂停记录
- 相同内容自动去重，最近使用的记录置顶
- 历史最多 200 条、数据最多约 25 MB；单张图片最大 8 MB
- 自动忽略密码管理器标记为隐藏、临时或自动生成的剪贴板内容
- 历史只保存在本机 `~/Library/Application Support/ClipShelf/history.json`
- 可选“登录时启动”

## 安装

1. 打开 `dist/ClipShelf-1.0.0-universal.dmg`。
2. 把 `ClipShelf.app` 拖到 `Applications`。
3. 从“应用程序”启动 ClipShelf，菜单栏会出现剪贴板图标。

当前构建使用 ad-hoc 本地签名，适合在本机安装。若要公开分发，需要 Apple Developer ID 证书并完成 notarization（公证）。

## 开发与构建

要求 macOS 13 或更高版本，以及 Apple Command Line Tools。无需完整 Xcode。

```bash
bash Scripts/run_tests.sh
bash Scripts/build_dmg.sh
```

构建脚本会分别编译 Intel 和 Apple Silicon 版本、合并为 Universal 2 应用，并在 `dist/` 生成 DMG。

## 隐私说明

剪贴板历史可能包含隐私信息。ClipShelf 不联网、不上传历史，并会跳过带标准敏感标记的内容；但不是所有应用都会正确设置这些标记。处理敏感数据时，可从菜单栏选择“暂停记录”，并定期清空历史。
