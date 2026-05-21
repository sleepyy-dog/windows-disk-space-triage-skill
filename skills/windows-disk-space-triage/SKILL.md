---
name: windows-disk-space-triage
description: Use when a Windows user reports low disk space, a shrinking C drive, unexpected storage pressure, large AppData or Program Files folders, update/cache growth, or asks what can be cleaned safely. This skill guides read-only diagnosis first, then safe optimization recommendations before any cleanup.
---

# Windows Disk Space Triage

## 1. Skill Scope

Use this skill to diagnose Windows disk-space pressure, especially on `C:\`.

The goal is to answer three questions:

- What is using space now?
- What appears to have grown recently?
- What actions are safe, useful, or risky?

Default posture:

- Start read-only.
- Default to `C:\` and the last 7 days unless the user specifies otherwise.
- Do not delete, uninstall, move, compress, empty Recycle Bin, disable updates, or change environment variables without explicit user confirmation.
- Treat "large", "recently modified", and "reclaimable" as different claims.
- Be cautious with `C:\Windows`, `C:\Program Files`, `C:\Program Files (x86)`, and vendor-managed application folders.
- Explain uncertainty when directory sizes may be distorted by hard links, junctions, sparse files, virtual disks, or access-denied paths.

This skill is for storage triage, not RAM/memory debugging unless the issue is page files, hibernation files, dumps, or other disk-backed pressure.

## 2. Disk Analysis Workflow

1. Establish baseline.

   Capture current drive capacity, free space, scan window, current user, and whether admin rights are available.

   ```powershell
   Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" |
     Select-Object DeviceID,Size,FreeSpace
   Get-PSDrive -Name C
   ```

2. Rank coarse usage first.

   Start with first-level folders under the target drive, then deepen only into suspicious or high-value areas. Prefer already-installed disk usage tools if present; otherwise use PowerShell and tolerate access-denied errors.

   Typical first targets:

   - `C:\Users\<user>\AppData`
   - `C:\ProgramData`
   - `C:\Windows`
   - `C:\Program Files`
   - `C:\Program Files (x86)`
   - `C:\$Recycle.Bin`

3. Identify recent change signals.

   Aggregate files created or modified in the selected window by parent directory. Use this to find suspects, not as proof of net growth.

   Useful distinction:

   - `CreationTime`: often better for newly downloaded/generated files.
   - `LastWriteTime`: useful for active caches, logs, databases, and updates, but can overstate growth.

4. Check known Windows pressure categories.

   Cover these angles before recommending cleanup:

   - User temp and caches: `%TEMP%`, `%LOCALAPPDATA%\Temp`, browser cache, thumbnail cache.
   - Browser data: Chrome/Edge `Cache`, `Code Cache`, `GPUCache`, `Service Worker\CacheStorage`.
   - Developer caches: npm, pnpm, yarn, pip, uv, conda, NuGet, Maven, Gradle, Rust/Cargo, Docker, WSL.
   - Windows update and maintenance: `SoftwareDistribution\Download`, Delivery Optimization, Windows temp, CBS/DISM logs, `Windows.old`, `$WINDOWS.~BT`.
   - Application update systems: Office, Edge, Microsoft Store apps, MathWorks Service Host/MATLAB, JetBrains, VS Code.
   - Large special files: `hiberfil.sys`, `pagefile.sys`, crash dumps, VM images, ISO/installers, WSL/Docker virtual disks.
   - Recycle Bin and shadow copies. Use `vssadmin list shadowstorage` when available; note if admin rights are required.

5. Classify findings.

   Report each finding with:

   - Path
   - Estimated size
   - Recent evidence, if any
   - Confidence: high, medium, or low
   - Safe action
   - Risk or verification needed

6. Present the result before cleanup.

   Output a ranked diagnosis first. Only after the user approves should you run destructive commands or change configuration. Prefer dry-run or `-WhatIf` modes where available, then verify free-space change afterward.

## 3. Optimization Recommendations

Use category-specific guidance instead of one generic "clean disk" answer.

High-confidence actions:

- Empty Recycle Bin after the user confirms no needed files are there.
- Remove user temp files that are old and not locked.
- Clear browser caches through browser settings or safe cache directories.
- Clean Windows Update cache through Windows Settings, Disk Cleanup, Storage Sense, or documented service-aware procedures.
- Remove old installers, archives, crash dumps, and downloaded packages after user review.

Medium-confidence actions:

- Prune package-manager caches such as npm, pnpm, pip, uv, conda, NuGet, Maven, Gradle, or Cargo when projects can redownload dependencies.
- Prune Docker images/containers/volumes only after listing what would be removed.
- Compact or relocate WSL/Docker virtual disks only after identifying the distro or data owner.
- Remove old application versions only through official uninstallers or vendor-supported managers.
- Move large user-controlled downloads, datasets, VM images, and build artifacts to another drive.

Risky or manual-review actions:

- Do not manually delete arbitrary files from `C:\Windows`, `WinSxS`, `Installer`, `System32`, `Program Files`, or active application data directories.
- Do not delete Office, Edge, Store, MathWorks, or driver update folders unless the vendor workflow or prior investigation confirms they are stale.
- Do not delete database-like files, virtual disks, project dependency folders, or application profiles merely because they are large.

Prevention recommendations:

- Enable or tune Windows Storage Sense for routine temp and Recycle Bin cleanup.
- Keep periodic disk snapshots so future incidents can compare real growth instead of relying only on modified timestamps.
- Relocate large, user-controlled caches or tool installs to another drive when the tool supports it.
- Uninstall unused application versions instead of deleting managed folders.
- For recurring vendor updaters, identify whether auto-update can be disabled, redirected, or constrained through supported settings.
- Keep a short allowlist of known safe cleanup paths and a denylist of system/vendor-managed paths for this machine.
