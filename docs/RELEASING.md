# Release guide / 发布指南

This folder is a complete source project. Preparing it locally does not create a GitHub repository or publish a Release.
这是完整源码项目；本地打包不会创建 GitHub 仓库或公开发布 Release。

## Prepare / 准备

- Review [third-party names and artwork](../THIRD_PARTY_NOTICES.md) before a public release.
  公开发布前核对第三方名称与图像说明。
- The app uses original tap artwork. Review the remaining GPT name before publishing. [OpenAI brand guidelines](https://openai.com/brand/)
  应用已使用原创的轻触图标；公开发布前请核对当前 GPT 名称的使用条件。
- Update `CFBundleShortVersionString` and `CFBundleVersion` in `resources/Info.plist`, then update both READMEs and [CHANGELOG.md](../CHANGELOG.md).
  在 Info.plist 更新版本号与构建号，同步更新双语 README 和更新记录。
- Keep screenshots free of personal chats, paths and account data. Captions must distinguish real captures from icon previews and identify demo content.
  截图不包含私人对话、路径或账户信息；说明真实截图、图标预览与演示内容的区别。

## Build locally / 本地构建

From the project root / 在项目根目录执行：

```sh
./scripts/test.sh
./scripts/package.sh
cd dist
shasum -a 256 -c SHA256SUMS.txt
```

The packaging command rebuilds the app, checks its local signature, and creates:
打包命令会重新构建、校验本地签名，并生成：

| File / 文件 | Use / 用途 |
| --- | --- |
| `TouchGPT-1.2.2-macos-arm64.zip` | `Touch GPT.app` for users / 用户安装包 |
| `TouchGPT-1.2.2-source.zip` | Full source, tests, docs and screenshots / 完整源码、测试、文档与截图 |
| `SHA256SUMS.txt` | SHA-256 checksums for both archives / 两个压缩包的校验值 |

The source archive contains `TouchGPT-1.2.2/`. It excludes Git history, build outputs, local environment files and Finder metadata. It can be built without a `.git` directory.
源码包内为 `TouchGPT-1.2.2/`，不含 Git 历史、构建产物、本地环境文件和 Finder 元数据；解压后无需 `.git` 即可构建。

## Upload to GitHub / 上传 GitHub

Create an empty repository in your own GitHub account, then use the repository's exact remote URL. Upload the project contents, including `.github`, `.gitignore` and `.gitattributes`; do not upload `build/` or `dist/` as source files.
在自己的 GitHub 账户创建空仓库，并使用该仓库提供的准确远程地址。上传项目内容时保留隐藏的 `.github`、`.gitignore` 与 `.gitattributes`；`build/` 和 `dist/` 不作为源码上传。

GitHub Desktop can publish the local project. If using Git, initialize a `main` branch, review the files before committing, add the copied remote URL, and push `main`. No account name or remote URL is embedded in this package.
可用 GitHub Desktop 发布本地项目；使用 Git 时，初始化 `main` 分支、检查待提交文件、提交后添加复制的远程地址，再推送 `main`。本包没有预置账户名或远程地址。

The included workflow runs build tests on GitHub's macOS ARM64 runner and saves downloadable artifacts. It does not publish Releases. GitHub-hosted runners cannot validate physical Touch Bar behavior; keep the local hardware check in the release notes. [Runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
随附工作流在 GitHub 的 macOS ARM64 runner 执行测试与打包，仅保存可下载产物，不自动发布 Release。云端 runner 无法验证实体触控条，请在发布说明记录本机硬件验证。

In GitHub's **Releases → Draft a new release**, select the tested commit, create a matching tag such as `v1.2.2`, copy the version notes, and attach the three files from `dist/`. Review the draft before publishing. GitHub also supplies its own source archives for tags. [GitHub release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
在 GitHub 的 **Releases → Draft a new release** 中选择验证过的提交，创建对应版本标签（如 `v1.2.2`），填写版本说明并附上 `dist/` 的三个文件。检查草稿后再发布。GitHub 也会为标签自动提供源码压缩包。

## Signing / 签名

The current build uses an ad hoc signature. A successful `codesign --verify` checks bundle integrity; it does not mean Apple has notarized or approved the app. For a notarized distribution, use your own Apple Developer ID and Apple's signing/notarization process, then package that signed artifact and regenerate its checksums. Keep signing credentials outside the repository. [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
当前构建使用 ad hoc 签名。`codesign --verify` 成功表示包完整性通过，不表示获得 Apple 公证或审核。需要公证版时，使用自己的 Developer ID 完成 Apple 签名与公证流程，再打包该产物并重新生成校验值；签名凭据不放入仓库。
