# Security and privacy / 安全与隐私

Touch GPT follows one explicitly selected local Codex chat. It reads task state and excerpts through the local desktop socket and sends an approval decision only after the corresponding button is pressed. It does not provide a hosted service or analytics endpoint. Quota retrieval starts the Codex application's bundled CLI briefly; that process uses the existing Codex account and may contact OpenAI.

The app stores the selected chat ID in macOS user defaults. It does not save chat history or Touch Bar frames. The foreground-controls probe samples the Touch Bar for roughly 180 ms when needed after an app switch, then releases the stream. Diagnostic logs contain connection/layout state, not complete chat messages. macOS and Codex may keep their own diagnostics.

If reporting an issue, remove chat IDs, account details, credentials, private commands and conversation text. Use a repository's private vulnerability reporting feature if enabled. Do not post secrets in public issues.

Touch GPT 只关注用户选择的一个本机 Codex 对话；点击 Allow 或 Reject 后才提交对应审批。程序没有自建云服务和统计上报。额度查询会短暂启动 Codex 自带 CLI，该进程使用已有账户并可能连接 OpenAI。

程序只在系统偏好中保存所选对话 ID，不保存聊天记录或触控条画面。切换应用后，必要时短暂采样约 180 毫秒来判断触控条是否空闲；完成后立即释放。报告问题前请移除对话 ID、账户信息、凭据、私人命令及聊天内容。
