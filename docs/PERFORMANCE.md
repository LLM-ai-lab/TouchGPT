# Performance / 性能说明

[简体中文 README](../README.md) · [English README](../README.en.md)

## Local measurements / 本机实测

Measured on **2026-11-13**, using the production **v1.2.0 / build 6** process connected to a local Codex chat. This was not the screenshot fixture.

测量日期为 **2026-11-13**，对象为连接本机 Codex 对话的正式 **v1.2.0 / build 6** 进程，非截图演示程序。

| Environment / 环境 | Value / 数据 |
| --- | --- |
| Hardware / 硬件 | 2020 M1 MacBook Pro, `MacBookPro17,1`, arm64 |
| OS / 系统 | macOS 26.7.3 |
| Build / 构建 | arm64, Clang `-O2`, ad hoc signed / 本地临时签名 |
| Executable size / 可执行文件大小 | 169,808 bytes; executable only, excluding resources / 仅可执行文件，不含资源 |

| Approx. time after launch / 启动后约 | Physical footprint (`vmmap`) | CPU sample (`ps`) |
| --- | --- | --- |
| 6 s | 17.4M | 0.0% |
| 10 s | 17.3M | 0.0% |
| 14 s | 17.3M | 0.0% |

The reported peak physical footprint was **17.5M**. Values retain `vmmap`'s displayed `M` unit. These are three brief samples after startup, not a sustained idle benchmark or a guarantee of zero CPU usage. The followed-chat state was not isolated into separate idle and working benchmarks.

工具报告的峰值物理内存为 **17.5M**。表格保留 `vmmap` 显示的 `M` 单位。这是启动后的三次短时采样，不是持续空闲基准，也不代表 CPU 始终为零；此次未将所关注对话的空闲与执行状态拆成独立基准测试。

## What is measured / 测量范围

These figures describe the **Touch GPT process itself**. They do not include the Codex desktop app, AI inference, or the temporary Codex command-line process used to read account quota. Quota queries can involve Codex's normal network activity.

上述数据统计 **Touch GPT 进程本身**，不包含 Codex 桌面应用、模型推理，以及读取账户额度时短暂启动的 Codex 命令行子进程。额度查询可能涉及 Codex 的正常联网。

`vmmap`'s physical footprint and `ps`'s resident memory are different measurements. This document reports physical footprint. CPU percentages are samples from the stated scenario, not a guarantee that all future workloads will have the same cost.

`vmmap` 的 Physical footprint 与 `ps` 的常驻内存 RSS 口径不同。本文采用前者；CPU 数据是指定场景下的采样，不代表所有运行情况的固定占用。

## Why it stays small / 轻量化实现

| Mechanism / 机制 | Behavior / 工作方式 |
| --- | --- |
| Native UI / 原生界面 | Objective-C + system AppKit; no bundled web engine or AI model / 使用系统 AppKit，不内置网页引擎或模型 |
| Task updates / 任务更新 | Local socket events rather than repeated history scans / 通过本机 socket 接收事件，不循环扫描历史 |
| Icons / 图标 | Cached vector glyph and status images / 缓存矢量图形与状态图片 |
| Thinking / 思考动画 | Cached progress frames with one timer for the visible view / 缓存进度条帧，可见视图使用一个计时器 |
| Idle / 空闲 | Animation timer is invalidated when the task ends or an approval appears / 任务结束或出现审批时撤销动画计时器 |
| Foreground change / 前台切换 | A brief ≈180 ms Touch Bar sample, released immediately afterward / 约 180 毫秒短时采样，结束后释放 |
| Quota / 额度 | Refresh every 300 s, plus launch, wake, and explicit refresh; child process exits after the query / 每 300 秒及启动、唤醒、手动刷新时查询，查询子进程随后退出 |
| Disconnected / 连接断开 | Reconnect delay backs off from 2 s to at most 30 s / 重连间隔从 2 秒逐步增加，最高 30 秒 |

The Touch Bar sample is used to determine whether another application has controls. Production code does not save those frames. The separate documentation capture tool intentionally saves demo screenshots when a maintainer runs it.

触控条采样仅用于判断其他应用是否占用控件区域，正式应用不会保存这些画面。单独的文档截图工具由维护者手动运行，才会保存演示截图。

## Reproduce / 复现

On a Mac with a physical Touch Bar, build the app and start one instance:
在带实体 Touch Bar 的 Mac 上构建并启动一个实例：

```sh
./scripts/build.sh
open "build/Touch GPT.app"
```

Find the process and inspect its physical footprint and CPU usage:
找到进程并读取物理内存与 CPU 采样：

```sh
pgrep -x TouchGPT
# Replace 12345 with the PID above / 将 12345 替换为上一步的 PID
vmmap -summary 12345
ps -p 12345 -o pid=,%cpu=,etime=,command=
```

Record the app version, hardware, macOS version, followed-chat state, whether thinking animation is visible, and whether a quota refresh is in progress. For an idle sample, wait for startup and the initial quota query to finish. Measure several intervals if comparing changes; a single `0.0%` sample is rounded display output, not proof of zero CPU work.

记录应用版本、硬件、macOS 版本、所关注对话的状态、思考动画是否可见，以及额度刷新是否正在执行。测量空闲状态前，应等待启动和首次额度查询完成。比较版本时应跨多个时段采样；单次显示 `0.0%` 是取整后的采样结果，不等于完全没有 CPU 工作。

For a complete system comparison, measure Codex and the temporary quota process separately. GitHub-hosted runners can validate compilation and logic tests, but cannot measure physical Touch Bar behavior.

如需比较完整工作环境，请另行测量 Codex 和临时额度查询进程。GitHub 云端 runner 可以验证编译与逻辑测试，无法测量实体 Touch Bar 的运行表现。
