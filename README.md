# Windows Disk Space Triage Skill

A concise Codex skill for diagnosing Windows disk-space pressure before cleanup.

It focuses on:

- skill scope and safety posture
- disk-space analysis workflow
- optimization recommendations by risk category

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

## Skill Path

```text
skills/windows-disk-space-triage/SKILL.md
```

## License

MIT
