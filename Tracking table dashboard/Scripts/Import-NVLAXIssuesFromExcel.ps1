<#
.SYNOPSIS
    One-time migration: imports the NVLAX Parametric Tracker Excel export into the
    "NVLAX Parametric Open Issues" list on the provisioned site, and creates a
    matching Evidence folder for each imported issue.

.DESCRIPTION
    Run this AFTER New-NVLAXParametricSite.ps1 has provisioned the site/lists.

    Reads directly from the local .xlsx (no Graph/OneNote API access needed) by
    unzipping it and parsing the OOXML sheet/sharedStrings parts.

    Only the "Issues" sheet is imported. "Heat Map" is a live rollup (not stored
    data), "Heat Map Overrides" is currently empty, and "NVLAX Domain Dictionary" is
    already seeded by the provisioning script from the design doc's ALIASES section.

.NOTES
    Domain normalization: the raw "Domain" column (e.g. "SA-Atom", "Core / IA") is
    free text and is preserved as-is in the hidden Source Domain field. The visible
    Domain field (multi-select) is derived from the Affected Domain Scope column,
    resolving each token via direct match or the ALIASES table (e.g. IA -> Core):
      - all tokens resolve, set == all 13 canonical domains -> ALL
      - all tokens resolve, set == exact SA group (8 domains) -> SA
      - all tokens resolve, otherwise -> the resolved domains listed directly
      - any token unrecognized -> approximate to SA/ALL and flag for manual review

    Owner resolution: names are free text, sometimes multiple ("Lama A.; Lital M."),
    with no emails in the source data. Each name is searched against the tenant
    directory via the People Picker REST search; matches are added to the People
    field, non-matches (including "Unassigned"/team names like "HVE Owners") are
    recorded as-is in the hidden Owner Unresolved field for manual follow-up.
#>

param(
    [string]$SiteUrl        = "https://intel.sharepoint.com/sites/ybsclientidc",
    [string]$EvidenceLibUrl = "NVLAXParametricEvidence",
    [string]$ExcelPath      = "C:\Users\hmarkovi\Downloads\NVLAX_Parametric_Tracker_First_Draft_v2.xlsx"
)

$CanonicalDomains = @("Atom","Ring","Core","GT","GTVPG","SAC","SACD","SADPU","SAIOC","SAME","SAN","SAPS","SAQ")
$SaGroup          = @("SAC","SACD","SADPU","SAIOC","SAME","SAN","SAPS","SAQ")
# Alias -> canonical domain, per the design doc's ALIASES section
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

$extractPath = Join-Path $env:TEMP ("nvlax_import_" + [guid]::NewGuid().ToString("N"))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ExcelPath, $extractPath)
$shared = Get-SharedStrings "$extractPath\xl\sharedStrings.xml"
$rows = Get-SheetRows "$extractPath\xl\worksheets\sheet1.xml" $shared
Remove-Item $extractPath -Recurse -Force

# ---------------------------------------------------------------------------
# Domain normalization (reverse SPECIAL LOGIC): resolves each scope token to a
# canonical domain (direct match or alias); only approximates to SA/ALL when a
# token can't be recognized at all. Returns an array for the multi-select field.
# ---------------------------------------------------------------------------
function Resolve-DomainToken([string]$Token) {
    $t = $Token.Trim()
    if ($CanonicalDomains -contains $t) { return $t }
    if ($DomainAliases.ContainsKey($t)) { return $DomainAliases[$t] }
    return $null
}

function Get-NormalizedDomain([string]$AffectedScope) {
    $tokens = @($AffectedScope -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    if (-not $tokens) { return @("ALL") }

    $resolved = @()
    $unresolved = @()
    foreach ($token in $tokens) {
        $r = Resolve-DomainToken $token
        if ($r) { $resolved += $r } else { $unresolved += $token }
    }
    $resolved = $resolved | Sort-Object -Unique

    if ($unresolved.Count -gt 0) {
        # Approximation fallback only when a token isn't a recognizable domain/alias
        Write-Host "  Domain scope has unrecognized token(s): $($unresolved -join ', ') - approximating." -ForegroundColor DarkYellow
        if (($resolved | Where-Object { $SaGroup -contains $_ }).Count -gt 0) { return @("SA") }
        return @("ALL")
    }

    if (-not (Compare-Object $resolved ($CanonicalDomains | Sort-Object -Unique))) { return @("ALL") }
    if ($resolved.Count -eq 1) { return @($resolved[0]) }
    if (-not (Compare-Object $resolved ($SaGroup | Sort-Object -Unique))) { return @("SA") }
    return $resolved
}

# ---------------------------------------------------------------------------
# Owner resolution against the tenant directory (People Picker REST search)
# ---------------------------------------------------------------------------
function Resolve-NVLAXOwners([string]$OwnerRaw) {
    $resolvedIds = @()
    $unresolved  = @()
    $names = @($OwnerRaw -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "Unassigned" })
    foreach ($name in $names) {
        try {
            $body = @{ queryParams = @{
                AllowEmailAddresses      = $true
                AllowMultipleEntities    = $false
                AllUrlZones              = $false
                MaximumEntitySuggestions = 1
                PrincipalSource          = 15
                PrincipalType            = 1
                QueryString              = $name
            }} | ConvertTo-Json
            $result = Invoke-PnPSPRestMethod -Method Post `
                -Url "/_api/SP.UI.ApplicationPages.ClientPeoplePickerWebServiceInterface.ClientPeoplePickerSearchUser" `
                -Content $body -ContentType "application/json;odata=verbose"
            $matches = $result.d.ClientPeoplePickerSearchUser | ConvertFrom-Json
            if ($matches -and $matches.Count -gt 0) {
                $user = Ensure-PnPUser -LoginName $matches[0].Key
                $resolvedIds += $user.Id
            } else {
                $unresolved += $name
            }
        } catch {
            $unresolved += $name
        }
    }
    if ($OwnerRaw -match "Unassigned") { $unresolved += "Unassigned" }
    [PSCustomObject]@{ ResolvedIds = $resolvedIds; Unresolved = ($unresolved -join "; ") }
}

# ---------------------------------------------------------------------------
# Evidence folder creation (mirrors New-NVLAXEvidenceFolder in the provisioning script)
# ---------------------------------------------------------------------------
function New-NVLAXEvidenceFolder([int]$IssueId, $IssuesList) {
    $folderName = "Issue-$IssueId"
    $folder = Add-PnPFolder -Name $folderName -Folder $EvidenceLibUrl
    $folderUrl = "$SiteUrl/$EvidenceLibUrl/$folderName"
    Set-PnPListItem -List $IssuesList -Identity $IssueId -Values @{
        Evidence         = "$folderUrl, Evidence Folder"
        EvidenceFolderId = $folder.UniqueId
    }
    return $folderUrl
}

# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------
Connect-PnPOnline -Url $SiteUrl -Interactive
$issuesList = Get-PnPList -Identity "NVLAX Parametric Open Issues"

$summary = @()
for ($i = 1; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    if (-not $r["C"]) { continue }  # skip blank rows

    $domain    = Get-NormalizedDomain $r["J"]
    $params    = @($r["I"] -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ownerInfo = Resolve-NVLAXOwners $r["G"]

    $values = @{
        Title                = $r["C"]
        Priority             = $r["A"]
        Domain               = $domain
        Status               = $r["D"]
        NextStep             = $r["E"]
        Timeline             = $r["F"]
        Parameter            = $params
        AffectedDomainScope  = $r["J"]
        SourceDomain         = $r["B"]
        Comments             = $r["K"]
        OwnerUnresolved      = $ownerInfo.Unresolved
    }
    if ($ownerInfo.ResolvedIds.Count -gt 0) {
        $values["Owner_x0020_Field"] = $ownerInfo.ResolvedIds
    }

    $item = Add-PnPListItem -List $issuesList -Values $values
    $folderUrl = New-NVLAXEvidenceFolder -IssueId $item.Id -IssuesList $issuesList

    $summary += [PSCustomObject]@{
        Id               = $item.Id
        Issue            = $r["C"]
        Domain           = $domain
        OwnerUnresolved  = $ownerInfo.Unresolved
        EvidenceFolder   = $folderUrl
    }
}

Disconnect-PnPOnline

Write-Host "Import complete. $($summary.Count) issues created. Review these before considering migration done:" -ForegroundColor Yellow
$summary | Where-Object { $_.OwnerUnresolved } | Format-Table Id, Issue, OwnerUnresolved -AutoSize
