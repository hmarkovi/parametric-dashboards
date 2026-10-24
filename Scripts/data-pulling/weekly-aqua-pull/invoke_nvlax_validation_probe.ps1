[CmdletBinding()]
param(
    [string]$WrapperScriptPath = "C:\Users\hmarkovi\Downloads\NVLH_Parametric-main\NVLH_Parametric-main\Scripts\data-pulling\weekly-aqua-pull\run_nvlax62a0h25_daily_full_analysis.ps1",
    [string]$OutputDirectory = "C:\Temp\nvlax_validation_probe_output",
    [string]$TranscriptPath = "C:\Temp\nvlax_validation_probe_transcript.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Start-Transcript -Path $TranscriptPath -Force | Out-Null
try {
    Write-Host "Probe start: $(Get-Date -Format o)"
    Write-Host "WrapperScriptPath=$WrapperScriptPath"
    Write-Host "OutputDirectory=$OutputDirectory"

    if (-not (Test-Path -LiteralPath $WrapperScriptPath)) {
        throw "Wrapper script not found: $WrapperScriptPath"
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    & $WrapperScriptPath `
        -OutputDirectory $OutputDirectory `
        -ProgramPattern 'NVLAX62A0H25*' `
        -LastNDaysTestStart 0 `
        -LastNDaysTestEnd 7 `
        -AquaPullTimeoutSeconds 1800 `
        -AquaPullPollSeconds 10 `
        -KeepCleanCsvArtifact

    Write-Host "Probe completed successfully"
    exit 0
}
catch {
    Write-Host "Probe failed: $($_.Exception.Message)"
    Write-Host "Exception type: $($_.Exception.GetType().FullName)"
    Write-Host "Script stack:" 
    Write-Host $_.ScriptStackTrace
    Write-Host "Invocation info:" 
    Write-Host ($_.InvocationInfo | Format-List * | Out-String)
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
