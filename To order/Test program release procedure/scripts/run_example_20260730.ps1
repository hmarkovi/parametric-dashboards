$script = Join-Path $PSScriptRoot "build_tp_release_report.ps1"

& $script `
  -WeeklyRunsDir "R:\Products\NVL\NVL-H\Weekly Runs" `
  -CurrentCsv "R:\Products\NVL\NVL-H\Weekly Runs\Vmin_20260730.csv" `
  -CorrelationLots @("P630498CR","P630506CR") `
  -WtlLots @("P631001WTY","P6301270D","P6301280D","P6301290D","P6301810RD","Y6311230RD") `
  -MaxBaselineFiles 2
