# Windows Disk Space Triage Skill

[中文说明](README.zh-CN.md)

A concise Codex skill for diagnosing Windows disk-space pressure before cleanup.

It focuses on:

- skill scope and safety posture
- disk-space analysis workflow
- optimization recommendations by risk category
- a read-only PowerShell script for drive-level analysis

## Install

Install the skill from this repository path:

PowerShell:

```powershell
python "$HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" --repo sleepyy-dog/windows-disk-space-triage-skill --path skills/windows-disk-space-triage
```

macOS/Linux:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py --repo sleepyy-dog/windows-disk-space-triage-skill --path skills/windows-disk-space-triage
```

Restart Codex after installation so the new skill is discovered.

## Script

The bundled script analyzes one Windows drive at a time and does not delete files:

```powershell
cd skills\windows-disk-space-triage
.\scripts\Analyze-WindowsDiskSpace.ps1 -Drive C: -Top 20
```

Useful options:

- `-Drive C:` or `-Drive D:`: choose the drive.
- `-Days "3,7,30"`: time windows to report. Defaults to 3, 7, and 30 days.
- `-Json`: output machine-readable JSON.
- `-SaveSnapshot`: save a baseline for future growth comparisons.
- `-IncludeSignatureCheck`: add Authenticode status for suspicious recent executable/script files.

The script reports current usage, created/modified groups for each time window, large files per window, security review signals, and C/D-drive-specific recommendations. Security signals are not malware verdicts; use Microsoft Defender or another trusted scanner for confirmation.

## Skill Path

```text
skills/windows-disk-space-triage/SKILL.md
```

## License

MIT
