param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string]$GodotCommand = "godot"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$logDir = Join-Path $PSScriptRoot ".godot_logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Push-Location $repoRoot
try {
    $normalizedScriptPath = $ScriptPath.Replace("\", "/")
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $logPath = Join-Path $logDir "$scriptName.log"
    Write-Host "==> Running $normalizedScriptPath"
    & $GodotCommand --headless --log-file $logPath --script $normalizedScriptPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Test failed: $normalizedScriptPath"
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
