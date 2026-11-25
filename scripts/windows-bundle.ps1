# scripts/windows-bundle.ps1 OUT_DIR
#
# Builds the release binary and copies it to OUT_DIR with every Swift runtime DLL that it loads,
# so that it runs on a computer with no Swift toolchain.
param([Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = "Stop"

swift build -c release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$bin = swift build -c release --show-bin-path
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item (Join-Path $bin "plan-complete.exe") $Out

function Get-Imports([string]$File) {
    llvm-readobj --coff-imports $File |
        Select-String '^\s*Name:\s*(\S+\.dll)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
}

$system = [Environment]::GetFolderPath("Windows")
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $Out "plan-complete.exe"))
$seen = @{}
while ($queue.Count -gt 0) {
    foreach ($name in Get-Imports $queue.Dequeue()) {
        if ($seen[$name.ToLower()] -or $name -match "^(api|ext)-ms-") { continue }
        $seen[$name.ToLower()] = $true
        $found = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found -or $found.Source.StartsWith($system, "OrdinalIgnoreCase")) { continue }
        Copy-Item $found.Source $Out
        $queue.Enqueue($found.Source)
    }
}

Get-ChildItem $Out | Format-Table Name, Length

$env:PATH = "$system\System32;$system"
& (Join-Path $Out "plan-complete.exe") --version
if ($LASTEXITCODE -ne 0) { throw "the bundle does not run without the toolchain on PATH" }
