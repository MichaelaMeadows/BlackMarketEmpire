param(
    [string]$GodotCommand = "godot"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$testScripts = Get-ChildItem -Path $PSScriptRoot -File -Filter "*test.gd" |
    Where-Object { $_.Name -notlike "*helper*" } |
    Sort-Object Name

if ($testScripts.Count -eq 0) {
    Write-Host "No Godot test scripts found in $PSScriptRoot."
    exit 0
}

Push-Location $repoRoot
try {
    foreach ($script in $testScripts) {
        $relativePath = "tools/$($script.Name)"
        Write-Host ""
        Write-Host "==> Running $relativePath"
        & $GodotCommand --headless --script $relativePath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Test failed: $relativePath"
            exit $LASTEXITCODE
        }
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "All tests passed."
