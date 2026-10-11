param([ValidateSet('x64','arm64')][string]$Architecture='x64')
$ErrorActionPreference='Stop'
$exe=Join-Path $PSScriptRoot "bin/publish-$Architecture/Framelet.exe"
if(!(Test-Path $exe)){throw 'Run build.ps1 first.'}
$p=Start-Process $exe -ArgumentList '--self-test' -PassThru -Wait
if($p.ExitCode -ne 0){throw "Synthetic native test failed. Inspect $(Split-Path $exe)/self-test-error.txt"}
Get-Content "$(Split-Path $exe)/self-test.json"
Write-Host 'PASS_SCOPED: no screen, OCR or performance acceptance claimed. Complete RUNTIME-CHECKLIST.md on an authorized Windows test desktop.'
