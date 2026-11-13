# Contributing / 参与贡献

Touch GPT is a small native macOS companion. Keep changes readable and background work bounded.
Touch GPT 是原生 macOS 小工具。改动应易读，并控制后台工作量。

1. Open an issue with the problem and expected behavior before a large change. 大改动请先在 Issue 说明问题和预期。
2. Use macOS and Xcode Command Line Tools; Python 3 is needed only for the development tests. 使用 macOS 与 Xcode 命令行工具；Python 3 仅用于开发测试。
3. Run `./scripts/test.sh` and `./scripts/build.sh`. These do not require a Codex login or Touch Bar hardware. 执行这两个命令，无需 Codex 登录或实体触控条。
4. Test visible Touch Bar behavior on compatible hardware when changing layout or private API integration. 修改布局或私有 API 对接时，请在兼容硬件上实测。
5. Include concise validation notes, update both READMEs for user-visible changes, and use demo data in screenshots. 提交简短验证说明，同步更新双语 README，截图使用演示数据。

Use the existing Objective-C/AppKit code and cached drawing paths. Avoid adding a web runtime, continuous screen capture or frequent polling for work that can be triggered by an event.
优先沿用 Objective-C/AppKit 与缓存绘制；能够由事件触发的工作，不引入网页运行时、持续截屏或高频轮询。

Original contributions are submitted under [MIT](LICENSE). Third-party names and artwork remain subject to [their own terms](THIRD_PARTY_NOTICES.md).
原创贡献采用 MIT 许可；第三方名称和图像遵循各自条款。
