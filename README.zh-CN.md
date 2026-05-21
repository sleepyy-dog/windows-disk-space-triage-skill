# Windows 硬盘空间诊断 Skill

[English README](README.md)

这是一个精简的 Codex skill，用于在清理前诊断 Windows 硬盘空间压力，尤其适用于 `C:\` 空间快速减少、AppData 或 Program Files 异常变大、更新缓存和开发工具缓存占用过高等场景。

它主要包含三部分：

- skill 定位与安全边界
- 硬盘空间分析流程
- 按风险分类的优化建议

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

## Skill 路径

```text
skills/windows-disk-space-triage/SKILL.md
```

## 设计原则

- 默认先做只读诊断，不直接删除文件。
- 默认关注 `C:\` 和最近 7 天变化，除非用户指定其他范围。
- 区分“体积大”“最近修改过”和“可安全释放”。
- 对 `C:\Windows`、`Program Files`、Office、Edge、MathWorks、驱动和系统更新目录保持保守。
- 删除、卸载、移动、压缩、清空回收站、关闭更新或修改环境变量前，必须先让用户确认。

## 许可证

MIT
