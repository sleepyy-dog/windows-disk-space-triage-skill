# Windows 硬盘空间诊断 Skill

[English README](README.md)

这是一个精简的 Codex skill，用于在清理前诊断 Windows 硬盘空间压力，尤其适用于 `C:\` 空间快速减少、AppData 或 Program Files 异常变大、更新缓存和开发工具缓存占用过高等场景。

它主要包含三部分：

- skill 定位与安全边界
- 硬盘空间分析流程
- 按风险分类的优化建议
- 一个只读 PowerShell 脚本，用于按硬盘分析空间压力

## 安装

从这个仓库安装 skill：

PowerShell：

```powershell
python "$HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" --repo sleepyy-dog/windows-disk-space-triage-skill --path skills/windows-disk-space-triage
```

macOS/Linux：

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py --repo sleepyy-dog/windows-disk-space-triage-skill --path skills/windows-disk-space-triage
```

安装后重启 Codex，让新的 skill 被发现。

## 脚本

内置脚本按单个硬盘分析空间占用，不会删除文件：

```powershell
cd skills\windows-disk-space-triage
.\scripts\Analyze-WindowsDiskSpace.ps1 -Drive C: -Top 20
```

常用参数：

- `-Drive C:` 或 `-Drive D:`：选择硬盘。
- `-Days "3,7,30"`：输出哪些时间窗口。默认输出最近 3 天、7 天、30 天。
- `-Json`：输出 JSON，便于后续自动分析。
- `-SaveSnapshot`：保存本次快照，方便以后对比真实增长。
- `-IncludeSignatureCheck`：对最近出现的可疑可执行文件/脚本附加签名状态。

脚本会输出当前占用，并按每个时间窗口分别列出创建/修改的目录聚合、最近大文件、安全可疑信号，以及 C/D 盘不同场景下的迁移或删除建议。安全可疑信号不等于病毒结论，最终仍需要 Microsoft Defender 或其他可信杀毒工具确认。

## Skill 路径

```text
skills/windows-disk-space-triage/SKILL.md
```

## 设计原则

- 默认先做只读诊断，不直接删除文件。
- 默认关注 `C:\`，并同时输出最近 3 天、7 天、30 天变化，除非用户指定其他范围。
- 区分“体积大”“最近修改过”和“可安全释放”。
- 对 `C:\Windows`、`Program Files`、Office、Edge、MathWorks、驱动和系统更新目录保持保守。
- 删除、卸载、移动、压缩、清空回收站、关闭更新或修改环境变量前，必须先让用户确认。

## 许可证

MIT
