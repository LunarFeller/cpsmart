# 参与贡献

## 开发准备

需要 macOS 13 或更高版本，以及 Apple Command Line Tools。

```bash
swift build
bash Scripts/run_tests.sh
```

安装完整 Xcode 时，测试脚本会运行 SwiftPM 的标准 XCTest 目标；只有 Command Line Tools 的环境缺少 XCTest 模块，脚本才使用兼容运行器执行同一批核心用例。

请从最新的上游 `main` 创建功能分支，不要把任务交接、聊天记录、个人计划或临时截图提交到仓库。README、架构说明、测试方案、构建与发布文档可以随代码一起维护。

## 从 fork 提交 Pull Request

1. 在 GitHub 上 fork `dongdaoguang/cpsmart`。
2. 将官方仓库设为 `upstream`，自己的 fork 设为 `origin`。
3. 从 `upstream/main` 创建分支并提交改动。
4. 推送到自己的 fork，然后向 `dongdaoguang/cpsmart:main` 发起 Pull Request。

```bash
git remote rename origin upstream
git remote add origin https://github.com/<你的账号>/cpsmart.git
git fetch upstream
git switch -c feature/<功能名> upstream/main

# 修改、测试并提交后
git push -u origin feature/<功能名>
gh pr create --repo dongdaoguang/cpsmart --base main --head <你的账号>:feature/<功能名>
```

提交 PR 前请确认：

- `swift build` 和 `bash Scripts/run_tests.sh` 通过。
- PR 中只有产品代码、测试和正式文档，没有过程文档。
- README、更新日志和版本号与行为一致。
- 不提交 `build/`、`dist/`、`.build/` 或本地证书和公证凭据。
