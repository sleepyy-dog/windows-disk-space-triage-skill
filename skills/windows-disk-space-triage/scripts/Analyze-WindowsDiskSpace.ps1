[CmdletBinding()]
param(
    [string]$Drive = "C:",
    [string[]]$Days = @("3", "7", "30"),
    [int]$Top = 20,
    [int]$GroupDepth = 3,
    [int]$MaxFilesToScan = 500000,
    [switch]$DeepScan,
    [switch]$SaveSnapshot,
    [string]$SnapshotPath,
    [switch]$IncludeSignatureCheck,
    [switch]$Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Continue"

$script:ToolVersion = "0.3.0"

function ConvertTo-DriveRoot {
    param([string]$InputDrive)

    $value = $InputDrive.Trim()
    if ($value -match '^[A-Za-z]$') {
        $value = "$value`:"
    }
    if ($value -match '^[A-Za-z]:$') {
        $value = "$value\"
    }
    if (-not $value.EndsWith('\')) {
        $value = "$value\"
    }

    return [System.IO.Path]::GetFullPath($value)
}

function ConvertTo-Gib {
    param([Int64]$Bytes)
    if ($null -eq $Bytes) { return 0 }
    return [Math]::Round($Bytes / 1GB, 3)
}

function ConvertTo-Mib {
    param([Int64]$Bytes)
    if ($null -eq $Bytes) { return 0 }
    return [Math]::Round($Bytes / 1MB, 2)
}

function Get-GroupPath {
    param(
        [string]$Path,
        [string]$Root,
        [int]$Depth
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full
    }

    $relative = $full.Substring($rootFull.Length).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($relative)) {
        return $rootFull.TrimEnd('\')
    }

    $parts = $relative -split '\\' | Where-Object { $_ -ne "" }
    if ($parts.Count -eq 0) {
        return $rootFull.TrimEnd('\')
    }

    $take = [Math]::Min($Depth, $parts.Count)
    $selected = $parts[0..($take - 1)] -join '\'
    return ($rootFull.TrimEnd('\') + '\' + $selected)
}

function Add-BytesToMap {
    param(
        [hashtable]$Map,
        [string]$Key,
        [Int64]$Bytes
    )

    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = [ordered]@{
            Path = $Key
            Bytes = [Int64]0
            Count = 0
        }
    }
    $Map[$Key].Bytes = [Int64]($Map[$Key].Bytes + $Bytes)
    $Map[$Key].Count = [int]($Map[$Key].Count + 1)
}

function Convert-MapToRows {
    param(
        [hashtable]$Map,
        [int]$Limit
    )

    return @(
        $Map.Values |
            Sort-Object -Property Bytes -Descending |
            Select-Object -First $Limit |
            ForEach-Object {
                [pscustomobject]@{
                    Path = $_.Path
                    SizeGB = ConvertTo-Gib $_.Bytes
                    SizeMB = ConvertTo-Mib $_.Bytes
                    FileCount = $_.Count
                }
            }
    )
}

function Get-PathCategory {
    param([string]$Path)

    $p = $Path.ToLowerInvariant()

    if ($p -match '\\windows\\softwaredistribution\\download') { return "WindowsUpdateCache" }
    if ($p -match '\\windows\\temp') { return "WindowsTemp" }
    if ($p -match '\\users\\[^\\]+\\appdata\\local\\temp') { return "UserTemp" }
    if ($p -match '\\users\\[^\\]+\\downloads') { return "Downloads" }
    if ($p -match '\\users\\[^\\]+\\appdata\\local\\google\\chrome') { return "ChromeData" }
    if ($p -match '\\users\\[^\\]+\\appdata\\local\\microsoft\\edge') { return "EdgeData" }
    if ($p -match '\\cache\\|\\code cache\\|\\gpucache\\|\\cachestorage\\|\\cache$') { return "Cache" }
    if ($p -match '\\node_modules\\|\\.npm\\|\\.pnpm-store\\|\\pip\\cache|\\.gradle\\caches|\\.m2\\repository|\\cargo\\registry|\\nuget\\packages|\\yarn\\cache') { return "DeveloperCache" }
    if ($p -match '\\docker\\|\\wsl\\|\.vhdx$|\.vhd$|\.vmdk$') { return "Virtualization" }
    if ($p -match '\\mathworks\\|\\matlab') { return "MathWorks" }
    if ($p -match '\\microsoft office\\|\\office') { return "Office" }
    if ($p -match '\\program files\\|\\program files \(x86\)\\') { return "InstalledApplication" }
    if ($p -match '\\programdata\\') { return "ProgramData" }
    if ($p -match '\\windows\\') { return "WindowsSystem" }
    if ($p -match '\\users\\[^\\]+\\appdata\\') { return "AppData" }
    return "UserOrData"
}

function Get-Recommendation {
    param(
        [string]$Path,
        [string]$Category,
        [string]$DriveRoot
    )

    $driveLetter = $DriveRoot.Substring(0, 1).ToUpperInvariant()
    $onSystemDrive = $driveLetter -eq "C"

    switch ($Category) {
        "WindowsUpdateCache" {
            return "Use Windows Settings, Disk Cleanup, Storage Sense, or service-aware Windows Update cleanup. Do not manually delete while update services are active."
        }
        "WindowsTemp" { return "Candidate for cleanup after confirming files are old and not locked." }
        "UserTemp" { return "Usually cleanable after closing apps; prefer age-filtered cleanup." }
        "Downloads" {
            if ($onSystemDrive) { return "Review manually; move keepers to another drive such as D: and delete obsolete installers or archives." }
            return "Review manually; delete obsolete downloads or archive keepers."
        }
        "ChromeData" { return "Clear through browser settings or targeted cache cleanup; avoid deleting profile databases blindly." }
        "EdgeData" { return "Clear through browser settings or targeted cache cleanup; avoid deleting profile databases blindly." }
        "Cache" { return "Likely cache; clean through application settings or age-filtered deletion when app is closed." }
        "DeveloperCache" {
            if ($onSystemDrive) { return "Prune package-manager cache or relocate supported caches to D: when practical." }
            return "Prune if dependencies can be redownloaded; avoid deleting active project state blindly."
        }
        "Virtualization" {
            if ($onSystemDrive) { return "Inspect owner first; consider moving Docker/WSL/VM data to D: or compacting with vendor-supported tools." }
            return "Inspect owner first; delete only unused images, volumes, distros, or VM disks."
        }
        "MathWorks" {
            if ($onSystemDrive) { return "Use MathWorks-supported settings or managed install root to move service host/cache to D:; remove stale versions only after confirming active version." }
            return "Remove stale versions only after confirming active version."
        }
        "Office" { return "Use Office update/repair/uninstall mechanisms; avoid manual deletion from managed folders." }
        "InstalledApplication" {
            if ($onSystemDrive) { return "Use official uninstallers or supported relocation settings. Do not manually delete Program Files content." }
            return "If this is a portable app or installer cache, review and delete only if unused."
        }
        "WindowsSystem" { return "Do not manually delete. Use Disk Cleanup, DISM component cleanup, Storage Sense, or documented Windows maintenance." }
        "ProgramData" { return "Review application owner first; use vendor cleanup/uninstallers for managed data." }
        "AppData" {
            if ($onSystemDrive) { return "Review app owner; move or prune only supported caches/downloads, not profile databases." }
            return "Review app owner; delete only known cache or obsolete generated data."
        }
        default {
            if ($onSystemDrive) { return "If user-controlled, consider moving to D: or deleting after review; if app-managed, use the app's cleanup path." }
            return "If user-controlled and no longer needed, delete or archive after review."
        }
    }
}

function Get-SecuritySignal {
    param(
        [System.IO.FileInfo]$File,
        [datetime]$Cutoff,
        [switch]$IncludeSignature
    )

    $signals = New-Object System.Collections.Generic.List[string]
    $full = $File.FullName
    $lower = $full.ToLowerInvariant()
    $name = $File.Name
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext = $File.Extension.ToLowerInvariant()
    $recent = ($File.CreationTime -ge $Cutoff) -or ($File.LastWriteTime -ge $Cutoff)
    $executableExt = @(".exe", ".dll", ".scr", ".bat", ".cmd", ".ps1", ".vbs", ".js", ".jse", ".msi")

    if (-not $recent) {
        return $null
    }

    if ($executableExt -contains $ext) {
        if ($lower -match '\\appdata\\|\\temp\\|\\downloads\\|\\programdata\\|\\public\\') {
            $signals.Add("Recent executable/script in user-writable or temporary location")
        }
    }

    if ($name -match '\.(jpg|jpeg|png|gif|pdf|doc|docx|xls|xlsx|txt)\.(exe|scr|js|vbs|bat|cmd|ps1)$') {
        $signals.Add("Double extension commonly used for disguised executables")
    }

    if ($base -match '^[a-f0-9]{12,}$' -or $base -match '^[A-Za-z0-9]{24,}$') {
        $signals.Add("Random-looking file name")
    }

    if ($lower -match '\\microsoft\\windows\\start menu\\programs\\startup\\') {
        $signals.Add("Startup folder persistence location")
    }

    if (($File.Attributes -band [System.IO.FileAttributes]::Hidden) -and ($executableExt -contains $ext)) {
        $signals.Add("Hidden executable/script")
    }

    if ($signals.Count -eq 0) {
        return $null
    }

    $signatureStatus = $null
    if ($IncludeSignature -and ($executableExt -contains $ext)) {
        try {
            $signatureStatus = (Get-AuthenticodeSignature -LiteralPath $full -ErrorAction SilentlyContinue).Status.ToString()
        }
        catch {
            $signatureStatus = "Unknown"
        }
    }

    return [pscustomobject]@{
        Path = $full
        SizeBytes = $File.Length
        SizeMB = ConvertTo-Mib $File.Length
        Created = $File.CreationTime
        Modified = $File.LastWriteTime
        Signals = @($signals)
        SignatureStatus = $signatureStatus
        Note = "Not a malware verdict. Review with Microsoft Defender or another trusted scanner."
    }
}

function Get-DefenderSummary {
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Available = $false
            Note = "Microsoft Defender PowerShell cmdlets are not available in this session."
        }
    }

    try {
        $status = Get-MpComputerStatus
        return [pscustomobject]@{
            Available = $true
            AMServiceEnabled = $status.AMServiceEnabled
            AntivirusEnabled = $status.AntivirusEnabled
            RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
            AntispywareSignatureLastUpdated = $status.AntispywareSignatureLastUpdated
            AntivirusSignatureLastUpdated = $status.AntivirusSignatureLastUpdated
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Note = "Unable to read Microsoft Defender status: $($_.Exception.Message)"
        }
    }
}

function Get-SnapshotFilePath {
    param(
        [string]$DriveRoot,
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $RequestedPath
    }

    $driveLetter = $DriveRoot.Substring(0, 1).ToUpperInvariant()
    $base = Join-Path $env:LOCALAPPDATA "WindowsDiskSpaceTriage\snapshots"
    return (Join-Path $base "$driveLetter.json")
}

function Read-Snapshots {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json
        if ($data -is [array]) { return @($data) }
        return @($data)
    }
    catch {
        return @()
    }
}

function Save-Snapshot {
    param(
        [string]$Path,
        [object]$Snapshot
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $existing = Read-Snapshots -Path $Path
    $all = @($existing) + @($Snapshot)
    $all | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DriveBaseline {
    param([string]$DriveRoot)

    $driveId = $DriveRoot.Substring(0, 2)
    $logical = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'" -ErrorAction SilentlyContinue
    if ($null -eq $logical) {
        throw "Drive not found or inaccessible: $DriveRoot"
    }

    $used = [Int64]$logical.Size - [Int64]$logical.FreeSpace
    return [pscustomobject]@{
        DeviceID = $logical.DeviceID
        SizeGB = ConvertTo-Gib ([Int64]$logical.Size)
        UsedGB = ConvertTo-Gib $used
        FreeGB = ConvertTo-Gib ([Int64]$logical.FreeSpace)
        FreePercent = if ($logical.Size -gt 0) { [Math]::Round(([double]$logical.FreeSpace / [double]$logical.Size) * 100, 2) } else { 0 }
        FileSystem = $logical.FileSystem
        VolumeName = $logical.VolumeName
    }
}

function Get-EnumerableFiles {
    param([string]$Root)

    try {
        $options = [System.IO.EnumerationOptions]::new()
        $options.RecurseSubdirectories = $true
        $options.IgnoreInaccessible = $true
        $options.AttributesToSkip = [System.IO.FileAttributes]::ReparsePoint
        return [System.IO.Directory]::EnumerateFiles($Root, "*", $options)
    }
    catch {
        return Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName }
    }
}

function Format-SectionRows {
    param(
        [string]$Title,
        [object[]]$Rows
    )

    Write-Host ""
    Write-Host $Title
    if ($Rows.Count -eq 0) {
        Write-Host "  (none)"
        return
    }

    $Rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
}

$driveRoot = ConvertTo-DriveRoot -InputDrive $Drive
if (-not (Test-Path -LiteralPath $driveRoot)) {
    throw "Drive root does not exist: $driveRoot"
}

if ($DeepScan) {
    $MaxFilesToScan = [int]::MaxValue
}

$parsedWindows = New-Object System.Collections.Generic.List[int]
foreach ($dayInput in @($Days)) {
    if ([string]::IsNullOrWhiteSpace($dayInput)) {
        continue
    }

    foreach ($part in ([string]$dayInput -split ",")) {
        $candidate = $part.Trim()
        $parsed = 0
        if ([int]::TryParse($candidate, [ref]$parsed) -and $parsed -gt 0) {
            $parsedWindows.Add($parsed) | Out-Null
        }
    }
}

$dayWindows = @($parsedWindows | Sort-Object -Unique)
if ($dayWindows.Count -eq 0) {
    $dayWindows = @(3, 7, 30)
}

$now = Get-Date
$windowStates = [ordered]@{}
foreach ($dayWindow in $dayWindows) {
    $windowStates[[string]$dayWindow] = [ordered]@{
        Days = [int]$dayWindow
        Cutoff = $now.AddDays(-1 * [int]$dayWindow)
        CreatedMap = @{}
        ModifiedMap = @{}
        CreatedFiles = New-Object System.Collections.Generic.List[object]
        ModifiedFiles = New-Object System.Collections.Generic.List[object]
        SecuritySignals = New-Object System.Collections.Generic.List[object]
    }
}

$baseline = Get-DriveBaseline -DriveRoot $driveRoot
$snapshotFile = Get-SnapshotFilePath -DriveRoot $driveRoot -RequestedPath $SnapshotPath
$previousSnapshots = @(Read-Snapshots -Path $snapshotFile)
$previousSnapshot = $null
if ($previousSnapshots.Length -gt 0) {
    $previousSnapshot = $previousSnapshots[-1]
}

$topLevelMap = @{}
$categoryMap = @{}

$filesScanned = 0
$truncated = $false
$startedAt = Get-Date

foreach ($filePath in (Get-EnumerableFiles -Root $driveRoot)) {
    if ($filesScanned -ge $MaxFilesToScan) {
        $truncated = $true
        break
    }

    try {
        $file = [System.IO.FileInfo]::new([string]$filePath)
        if (-not $file.Exists) { continue }
        $filesScanned++

        $topPath = Get-GroupPath -Path $file.DirectoryName -Root $driveRoot -Depth 1
        Add-BytesToMap -Map $topLevelMap -Key $topPath -Bytes $file.Length

        $category = Get-PathCategory -Path $file.FullName
        Add-BytesToMap -Map $categoryMap -Key $category -Bytes $file.Length

        foreach ($state in $windowStates.Values) {
            if ($file.CreationTime -ge $state.Cutoff) {
                $group = Get-GroupPath -Path $file.DirectoryName -Root $driveRoot -Depth $GroupDepth
                Add-BytesToMap -Map $state.CreatedMap -Key $group -Bytes $file.Length
                $state.CreatedFiles.Add([pscustomobject]@{
                    Path = $file.FullName
                    SizeBytes = $file.Length
                    SizeGB = ConvertTo-Gib $file.Length
                    SizeMB = ConvertTo-Mib $file.Length
                    Created = $file.CreationTime
                    Category = $category
                    Recommendation = Get-Recommendation -Path $file.FullName -Category $category -DriveRoot $driveRoot
                }) | Out-Null
            }

            if ($file.LastWriteTime -ge $state.Cutoff) {
                $group = Get-GroupPath -Path $file.DirectoryName -Root $driveRoot -Depth $GroupDepth
                Add-BytesToMap -Map $state.ModifiedMap -Key $group -Bytes $file.Length
                $state.ModifiedFiles.Add([pscustomobject]@{
                    Path = $file.FullName
                    SizeBytes = $file.Length
                    SizeGB = ConvertTo-Gib $file.Length
                    SizeMB = ConvertTo-Mib $file.Length
                    Modified = $file.LastWriteTime
                    Category = $category
                    Recommendation = Get-Recommendation -Path $file.FullName -Category $category -DriveRoot $driveRoot
                }) | Out-Null
            }

            $signal = Get-SecuritySignal -File $file -Cutoff $state.Cutoff -IncludeSignature:$IncludeSignatureCheck
            if ($null -ne $signal) {
                $state.SecuritySignals.Add($signal) | Out-Null
            }
        }
    }
    catch {
        continue
    }
}

$elapsed = (Get-Date) - $startedAt
$topDirectories = Convert-MapToRows -Map $topLevelMap -Limit $Top
$categoryRows = Convert-MapToRows -Map $categoryMap -Limit $Top
$recentWindows = @(
    foreach ($dayWindow in $dayWindows) {
        $state = $windowStates[[string]$dayWindow]
        [pscustomobject]@{
            Days = $state.Days
            Label = "last $($state.Days) days"
            Cutoff = $state.Cutoff
            RecentCreatedGroups = Convert-MapToRows -Map $state.CreatedMap -Limit $Top
            RecentModifiedGroups = Convert-MapToRows -Map $state.ModifiedMap -Limit $Top
            TopRecentCreatedFiles = @($state.CreatedFiles | Sort-Object -Property SizeBytes -Descending | Select-Object -First $Top)
            TopRecentModifiedFiles = @($state.ModifiedFiles | Sort-Object -Property SizeBytes -Descending | Select-Object -First $Top)
            SecuritySignals = @($state.SecuritySignals | Sort-Object -Property SizeBytes -Descending | Select-Object -First $Top)
        }
    }
)

$snapshotDelta = $null
if ($null -ne $previousSnapshot) {
    $snapshotDelta = [pscustomobject]@{
        PreviousTimestamp = $previousSnapshot.Timestamp
        UsedGBDelta = [Math]::Round($baseline.UsedGB - [double]$previousSnapshot.Baseline.UsedGB, 3)
        FreeGBDelta = [Math]::Round($baseline.FreeGB - [double]$previousSnapshot.Baseline.FreeGB, 3)
        Note = "Snapshot delta is closer to real disk growth than file timestamp aggregation."
    }
}

$snapshot = [pscustomobject]@{
    Timestamp = (Get-Date).ToString("o")
    Drive = $driveRoot
    Baseline = $baseline
    FilesScanned = $filesScanned
    Truncated = $truncated
    TopDirectories = $topDirectories
    CategorySummary = $categoryRows
}

if ($SaveSnapshot) {
    Save-Snapshot -Path $snapshotFile -Snapshot $snapshot
}

$result = [pscustomobject]@{
    ToolVersion = $script:ToolVersion
    GeneratedAt = (Get-Date).ToString("o")
    Drive = $driveRoot
    WindowDays = $dayWindows
    Baseline = $baseline
    Scan = [pscustomobject]@{
        FilesScanned = $filesScanned
        MaxFilesToScan = $MaxFilesToScan
        Truncated = $truncated
        ElapsedSeconds = [Math]::Round($elapsed.TotalSeconds, 2)
        Note = "Recent created/modified size is evidence, not guaranteed net growth."
    }
    Snapshot = [pscustomobject]@{
        Path = $snapshotFile
        PreviousDelta = $snapshotDelta
        SavedThisRun = [bool]$SaveSnapshot
    }
    Defender = Get-DefenderSummary
    TopDirectories = $topDirectories
    CategorySummary = $categoryRows
    RecentWindows = $recentWindows
    SecurityNote = "Security signals are suspicious indicators only. They do not prove malware. Use Microsoft Defender or another trusted scanner for verdicts."
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    return
}

Write-Host "Windows Disk Space Triage"
Write-Host "Drive: $driveRoot"
Write-Host "Time windows: $($dayWindows -join ', ') days"
Write-Host "Free: $($baseline.FreeGB) GB / $($baseline.SizeGB) GB ($($baseline.FreePercent)%)"
Write-Host "Scanned files: $filesScanned in $([Math]::Round($elapsed.TotalSeconds, 2))s"
if ($truncated) {
    Write-Host "Warning: scan reached MaxFilesToScan=$MaxFilesToScan. Results are partial. Use -DeepScan or raise -MaxFilesToScan for a fuller scan."
}

if ($null -ne $snapshotDelta) {
    Write-Host "Snapshot delta since $($snapshotDelta.PreviousTimestamp): Used $($snapshotDelta.UsedGBDelta) GB, Free $($snapshotDelta.FreeGBDelta) GB"
}
elseif (-not $SaveSnapshot) {
    Write-Host "Snapshot: no previous snapshot found. Run with -SaveSnapshot to establish a baseline."
}
elseif ($SaveSnapshot) {
    Write-Host "Snapshot saved: $snapshotFile"
}

Format-SectionRows -Title "Top current directories from scanned files" -Rows $topDirectories
Format-SectionRows -Title "Category summary from scanned files" -Rows $categoryRows

foreach ($window in $recentWindows) {
    Format-SectionRows -Title "Created groups - $($window.Label)" -Rows $window.RecentCreatedGroups
    Format-SectionRows -Title "Modified groups - $($window.Label)" -Rows $window.RecentModifiedGroups
    Format-SectionRows -Title "Largest created files - $($window.Label)" -Rows $window.TopRecentCreatedFiles
    Format-SectionRows -Title "Largest modified files - $($window.Label)" -Rows $window.TopRecentModifiedFiles
    Format-SectionRows -Title "Security review signals - $($window.Label)" -Rows $window.SecuritySignals
}

Write-Host ""
Write-Host "Security note: suspicious signals are not a malware verdict. Use Defender or another trusted scanner for confirmation."
Write-Host "Cleanup note: this script is read-only. Review recommendations before deleting, moving, or uninstalling anything."
