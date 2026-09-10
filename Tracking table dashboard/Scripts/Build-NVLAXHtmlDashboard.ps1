<#
.SYNOPSIS
    Generates a single self-contained HTML dashboard (heat map + issues table)
    from the NVLAX Parametric Tracker Excel export. No external dependencies -
    works fully offline, so it's safe to host on an internal file share or
    upload to a SharePoint library and open locally.

.DESCRIPTION
    Re-run this any time the source Excel changes to regenerate the dashboard.
    No SharePoint/PnP connection is required - this is fully local/offline.
#>

param(
    [string]$ExcelPath = "C:\Users\hmarkovi\Downloads\NVLAX_Parametric_Tracker_First_Draft_v2.xlsx",
    [string]$OutputPath = "C:\Projects\NVL\.docs\Scripts\utility\..\..\Dashboard\NVLAX-Parametric-Dashboard.html"
)

$CanonicalDomains = @("Atom","Ring","Core","GT","GTVPG","SAC","SACD","SADPU","SAIOC","SAME","SAN","SAPS","SAQ")
$Parameters       = @("Vmin","SICC","Cdyn","DTS","PreSi","Content")
# Worst -> best severity order (index 0 = worst)
$StatusOrder      = @("Blocking","Status Required","Planned","In Progress","Monitoring","Closed")
$StatusColors     = @{
    "Blocking"        = "#D13438"
    "Status Required" = "#FF8C00"
    "Planned"         = "#FFC83D"
    "In Progress"     = "#0078D4"
    "Monitoring"      = "#8764B8"
    "Closed"          = "#107C10"
}
$PriorityColors   = @{ "P1" = "#D13438"; "P2" = "#FFAA44"; "P3" = "#107C10" }
$DomainAliases = @{
    "AT" = "Atom"; "CCF" = "Ring"; "CR" = "Core"; "IA" = "Core"
    "CCLK" = "SAC"; "Display" = "SACD"; "VPU" = "SADPU"; "NPU" = "SADPU"
    "Media" = "SAME"; "NCLK" = "SAN"; "IPU" = "SAPS"
}

# ---------------------------------------------------------------------------
# Minimal OOXML reader (no external modules required)
# ---------------------------------------------------------------------------
function Get-SharedStrings([string]$Path) {
    [xml]$xml = Get-Content $Path -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("a", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
    $xml.SelectNodes("//a:si", $ns) | ForEach-Object { $_.InnerText }
}

function Get-SheetRows([string]$Path, [string[]]$SharedStrings) {
    [xml]$xml = Get-Content $Path -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("a", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
    $rows = @()
    foreach ($row in $xml.SelectNodes("//a:row", $ns)) {
        $rowData = @{}
        foreach ($c in $row.SelectNodes("a:c", $ns)) {
            $colLetters = ($c.GetAttribute("r") -replace '[0-9]', '')
            $t = $c.GetAttribute("t")
            $vNode = $c.SelectSingleNode("a:v", $ns)
            $val = $null
            if ($t -eq "s" -and $vNode) { $val = $SharedStrings[[int]$vNode.InnerText] }
            elseif ($t -eq "inlineStr") { $val = $c.SelectSingleNode("a:is", $ns).InnerText }
            elseif ($vNode) { $val = $vNode.InnerText }
            $rowData[$colLetters] = $val
        }
        $rows += ,$rowData
    }
    $rows
}

function Resolve-DomainToken([string]$Token) {
    $t = $Token.Trim()
    if ($CanonicalDomains -contains $t) { return $t }
    if ($DomainAliases.ContainsKey($t)) { return $DomainAliases[$t] }
    return $null
}

$extractPath = Join-Path $env:TEMP ("nvlax_dash_" + [guid]::NewGuid().ToString("N"))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ExcelPath, $extractPath)
$shared = Get-SharedStrings "$extractPath\xl\sharedStrings.xml"
$rows = Get-SheetRows "$extractPath\xl\worksheets\sheet1.xml" $shared
Remove-Item $extractPath -Recurse -Force

# ---------------------------------------------------------------------------
# Build issue records + heat map cell severities
# ---------------------------------------------------------------------------
$issues = @()
# heatMap[domain][parameter] = worst status string
$heatMap = @{}
foreach ($d in $CanonicalDomains) {
    $heatMap[$d] = @{}
    foreach ($p in $Parameters) { $heatMap[$d][$p] = $null }
}

function Get-WorseStatus($a, $b) {
    if (-not $a) { return $b }
    if (-not $b) { return $a }
    $ia = $StatusOrder.IndexOf($a); $ib = $StatusOrder.IndexOf($b)
    if ($ia -le $ib) { return $a } else { return $b }
}

for ($i = 1; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    if (-not $r["C"]) { continue }

    $status = $r["D"]
    $scopeTokens = @($r["J"] -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    $resolvedDomains = @($scopeTokens | ForEach-Object { Resolve-DomainToken $_ } | Where-Object { $_ } | Sort-Object -Unique)
    $paramTokens = @($r["I"] -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim() })

    foreach ($d in $resolvedDomains) {
        foreach ($p in $paramTokens) {
            if ($CanonicalDomains -contains $d -and $Parameters -contains $p) {
                $heatMap[$d][$p] = Get-WorseStatus $heatMap[$d][$p] $status
            }
        }
    }

    $issues += [PSCustomObject]@{
        priority   = [string]$r["A"]
        domain     = [string]$r["B"]
        issue      = [string]$r["C"]
        status     = [string]$status
        nextStep   = [string]$r["E"]
        timeline   = [string]$r["F"]
        owner      = [string]$r["G"]
        parameter  = ($paramTokens -join ", ")
        scope      = ($resolvedDomains -join ", ")
        evidence   = [string]$r["L"]
    }
}

# ---------------------------------------------------------------------------
# Render HTML
# ---------------------------------------------------------------------------
$issuesJson = $issues | ConvertTo-Json -Depth 3 -Compress
$heatMapRows = ""
foreach ($d in $CanonicalDomains) {
    $cells = ""
    foreach ($p in $Parameters) {
        $st = $heatMap[$d][$p]
        if ($st) {
            $color = $StatusColors[$st]
            $cells += "<td style='background:$color' title='$st'>$st</td>"
        } else {
            $cells += "<td class='na'>-</td>"
        }
    }
    $heatMapRows += "<tr><th>$d</th>$cells</tr>`n"
}
$paramHeaders = ($Parameters | ForEach-Object { "<th>$_</th>" }) -join ""
$legendHtml = ($StatusOrder | ForEach-Object { "<span><span class='dot' style='background:$($StatusColors[$_])'></span>$_</span>" }) -join "`n"
$statusColorsJs = ($StatusColors.Keys | ForEach-Object { "'$_': '$($StatusColors[$_])'" }) -join ", "
$priorityColorsJs = ($PriorityColors.Keys | ForEach-Object { "'$_': '$($PriorityColors[$_])'" }) -join ", "
$generatedOn = Get-Date -Format "yyyy-MM-dd HH:mm"

# Single-quoted here-string: no PowerShell interpolation, so JS template literals
# (${...}, backticks) pass through untouched. Placeholders swapped in afterward.
$html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>NVLAX Parametric Tracking Dashboard</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; background: #f3f2f1; color: #201f1e; }
  h1 { margin-bottom: 0; }
  .subtitle { color: #605e5c; margin-top: 4px; }
  table { border-collapse: collapse; margin: 16px 0; width: 100%; background: #fff; }
  th, td { border: 1px solid #d1d1d1; padding: 6px 10px; text-align: left; font-size: 13px; }
  #heatmap th { background: #f3f2f1; }
  #heatmap td { text-align: center; color: #fff; font-weight: 600; }
  #heatmap td.na { background: #e1dfdd; color: #a19f9d; font-weight: 400; }
  .badge { padding: 2px 8px; border-radius: 4px; color: #fff; font-weight: 600; display: inline-block; }
  .controls { margin: 12px 0; display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
  .controls input, .controls select { padding: 6px; border: 1px solid #d1d1d1; border-radius: 4px; }
  #issues th { cursor: pointer; background: #f3f2f1; user-select: none; }
  #issues th:hover { background: #e1dfdd; }
  .legend span { margin-right: 12px; font-size: 12px; }
  .legend .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 4px; }
</style>
</head>
<body>
  <h1>NVLAX Parametric Tracking Dashboard</h1>
  <div class="subtitle">Generated __GENERATED_ON__ from the tracker Excel export - Intel Internal Only</div>

  <h2>Heat Map (worst status wins)</h2>
  <div class="legend">
__LEGEND__
  </div>
  <table id="heatmap">
    <tr><th>Domain</th>__PARAM_HEADERS__</tr>
    __HEATMAP_ROWS__
  </table>

  <h2>Open Issues</h2>
  <div class="controls">
    <input id="searchBox" type="text" placeholder="Search issues..." oninput="renderTable()">
    <select id="domainFilter" onchange="renderTable()"><option value="">All Domains</option></select>
    <select id="statusFilter" onchange="renderTable()"><option value="">All Statuses</option></select>
    <select id="priorityFilter" onchange="renderTable()"><option value="">All Priorities</option></select>
  </div>
  <table id="issues">
    <thead>
      <tr>
        <th onclick="sortBy('priority')">Priority</th>
        <th onclick="sortBy('domain')">Domain</th>
        <th onclick="sortBy('issue')">Issue</th>
        <th onclick="sortBy('status')">Status</th>
        <th onclick="sortBy('nextStep')">Next Step</th>
        <th onclick="sortBy('timeline')">Timeline</th>
        <th onclick="sortBy('owner')">Owner</th>
        <th onclick="sortBy('parameter')">Parameter</th>
        <th>Evidence</th>
      </tr>
    </thead>
    <tbody id="issuesBody"></tbody>
  </table>

<script>
const issues = __ISSUES_JSON__;
const statusColors = { __STATUS_COLORS__ };
const priorityColors = { __PRIORITY_COLORS__ };
let sortKey = null, sortAsc = true;

function populateFilters() {
  const domains = [...new Set(issues.map(i => i.domain))].sort();
  const statuses = [...new Set(issues.map(i => i.status))].sort();
  const priorities = [...new Set(issues.map(i => i.priority))].sort();
  const fill = (id, values) => {
    const sel = document.getElementById(id);
    values.forEach(v => { const o = document.createElement('option'); o.value = v; o.textContent = v; sel.appendChild(o); });
  };
  fill('domainFilter', domains);
  fill('statusFilter', statuses);
  fill('priorityFilter', priorities);
}

function sortBy(key) {
  if (sortKey === key) { sortAsc = !sortAsc; } else { sortKey = key; sortAsc = true; }
  renderTable();
}

function renderTable() {
  const q = document.getElementById('searchBox').value.toLowerCase();
  const df = document.getElementById('domainFilter').value;
  const sf = document.getElementById('statusFilter').value;
  const pf = document.getElementById('priorityFilter').value;

  let rows = issues.filter(i => {
    if (df && i.domain !== df) return false;
    if (sf && i.status !== sf) return false;
    if (pf && i.priority !== pf) return false;
    if (q && !Object.values(i).join(' ').toLowerCase().includes(q)) return false;
    return true;
  });

  if (sortKey) {
    rows = rows.slice().sort((a, b) => {
      const r = String(a[sortKey]).localeCompare(String(b[sortKey]));
      return sortAsc ? r : -r;
    });
  }

  const body = document.getElementById('issuesBody');
  body.innerHTML = rows.map(i => `
    <tr>
      <td><span class="badge" style="background:${priorityColors[i.priority] || '#605e5c'}">${i.priority}</span></td>
      <td>${i.domain}</td>
      <td>${i.issue}</td>
      <td><span class="badge" style="background:${statusColors[i.status] || '#605e5c'}">${i.status}</span></td>
      <td>${i.nextStep}</td>
      <td>${i.timeline}</td>
      <td>${i.owner}</td>
      <td>${i.parameter}</td>
      <td>${i.evidence ? `<a href="${i.evidence}" target="_blank">View source</a>` : ''}</td>
    </tr>`).join('');
}

populateFilters();
renderTable();
</script>
</body>
</html>
'@

$html = $html.Replace('__GENERATED_ON__', $generatedOn).
               Replace('__LEGEND__', $legendHtml).
               Replace('__PARAM_HEADERS__', $paramHeaders).
               Replace('__HEATMAP_ROWS__', $heatMapRows).
               Replace('__ISSUES_JSON__', $issuesJson).
               Replace('__STATUS_COLORS__', $statusColorsJs).
               Replace('__PRIORITY_COLORS__', $priorityColorsJs)

$outDir = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Set-Content -Path $OutputPath -Value $html -Encoding UTF8
Write-Host "Dashboard written to: $OutputPath" -ForegroundColor Green
