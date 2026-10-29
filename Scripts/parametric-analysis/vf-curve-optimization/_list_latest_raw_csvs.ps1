$files = Get-ChildItem "$env:TEMP\trace-vmin-P6*_6248_CLASSHOT-*.csv" | Sort-Object LastWriteTime
$rows = foreach ($f in $files) {
    $line2 = (Get-Content -LiteralPath $f.FullName -TotalCount 2)[1]
    $domain = ($line2 -split ',')[0]
    $job = ($f.Name -replace '^trace-vmin-','' -replace '-[0-9a-f]{8}\.csv$','')
    [pscustomobject]@{ Job=$job; Domain=$domain; File=$f.FullName; Time=$f.LastWriteTime; SizeKB=[math]::Round($f.Length/1KB,1) }
}
$latestPerJobDomain = $rows | Group-Object Job,Domain | ForEach-Object {
    $_.Group | Sort-Object Time -Descending | Select-Object -First 1
}
$latestPerJobDomain | Sort-Object Job,Domain | Format-Table Job,Domain,SizeKB -AutoSize
Write-Host "Total latest (job,domain) files: $($latestPerJobDomain.Count)"
$latestPerJobDomain | Select-Object -ExpandProperty File | Out-File -LiteralPath (Join-Path $env:TEMP 'vf_curve_raw_file_list.txt') -Encoding utf8
