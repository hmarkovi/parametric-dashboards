<#
.SYNOPSIS
    Provisions the NVLAX Parametric Tracking System per
    NVLAX_Parametric_Tracking_System_Design_v1.md.

.DESCRIPTION
    Creates a new SharePoint site, the two required lists (Open Issues,
    Domain Dictionary, Heat Map Overrides) and the Evidence document
    library, applies versioning, disables external sharing, and builds
    the required views.

    Requires: PnP.PowerShell module, and an account with SharePoint
    admin rights (to create the site) and site owner rights afterwards.
    Install module if needed: Install-Module PnP.PowerShell -Scope CurrentUser

.NOTES
    MANUAL STEPS NOT COVERED BY THIS SCRIPT (no tooling access available):
    1. Migrate content from the OneNote source page (no Graph/OneNote API
       access available here):
       onenote:https://intel.sharepoint.com/sites/ybsclientidc/Shared%20Documents/Bin%20Split/Bin%20Split%20Notebook/NVL.one#NVLAX%20Parametric
    2. Confirm/adjust the exact Priority choice values (not specified in
       the design doc; defaulted to High/Medium/Low below).
    (Publishing the link on Parametric-Team.aspx will be done manually.)

    Evidence library root (per-issue folders live here as Issue-<ListItemID>):
    https://intel.sharepoint.com/sites/NVLAXParametricTracking/NVLAXParametricEvidence
#>

param(
    [string]$AdminUrl        = "https://intel-admin.sharepoint.com",
    [string]$SiteUrl         = "https://intel.sharepoint.com/sites/NVLAXParametricTracking",
    [string]$SiteTitle       = "NVLAX Parametric Tracking",
    [string]$SiteAlias       = "NVLAXParametricTracking",
    [string]$OwnersGroup     = "mpe.cdg.idc.pbs@intel.com"
)

# ---------------------------------------------------------------------------
# 1. Create the site (full Team-connected site, backed by a Microsoft 365 Group)
# ---------------------------------------------------------------------------
try {
    Connect-PnPOnline -Url $AdminUrl -Interactive -ErrorAction Stop
} catch {
    Write-Host "FAILED to connect to $AdminUrl - stopping here instead of cascading errors." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

New-PnPSite -Type TeamSite `
    -Title $SiteTitle `
    -Alias $SiteAlias `
    -IsPublic:$false `
    -Description "Single source of truth for NVLAX parametric status, issues, and evidence."

# Disable external sharing on the new site (per SECURITY section)
Set-PnPTenantSite -Url $SiteUrl -Sharing Disabled

Disconnect-PnPOnline

# ---------------------------------------------------------------------------
# 2. Connect to the new site and grant the owners group
# ---------------------------------------------------------------------------
try {
    Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
} catch {
    Write-Host "FAILED to connect to $SiteUrl - stopping here instead of cascading errors." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Team-connected site: membership is driven by the M365 Group, not classic SP groups.
# NOTE: adding a mail-enabled group as an M365 Group owner is not supported by Graph/PnP;
# this adds it as a member. Promote a named individual to Owner manually in Entra ID if needed.
Add-PnPMicrosoft365GroupMember -Identity $SiteAlias -Users $OwnersGroup

# ---------------------------------------------------------------------------
# 3. NVLAX Parametric Open Issues list
# ---------------------------------------------------------------------------
$issuesList = New-PnPList -Title "NVLAX Parametric Open Issues" -Template GenericList -EnableVersioning
Set-PnPField -List $issuesList -Identity "Title" -Values @{ Title = "Issue" }

# Visible fields
Add-PnPField -List $issuesList -DisplayName "Priority" -InternalName "Priority" -Type Choice `
    -Choices "P1","P2","P3" -AddToDefaultView

# Red/Amber/Green color scale on Priority (modern column formatting)
$priorityFormatter = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/sp/v2/column-formatting.schema.json",
  "elmType": "div",
  "txtContent": "@currentField",
  "style": {
    "padding": "3px 8px",
    "border-radius": "4px",
    "color": "#ffffff",
    "text-align": "center",
    "background-color": "=if(@currentField == 'P1', '#D13438', if(@currentField == 'P2', '#FFAA44', if(@currentField == 'P3', '#107C10', '#605E5C')))"
  }
}
'@
Set-PnPField -List $issuesList -Identity "Priority" -Values @{ CustomFormatter = $priorityFormatter }

# Multi-select: an issue can span more than one canonical domain (see DOMAIN NORMALIZATION rule)
Add-PnPField -List $issuesList -DisplayName "Domain" -InternalName "Domain" -Type MultiChoice `
    -Choices "Atom","Ring","Core","GT","GTVPG","SAC","SACD","SADPU","SAIOC","SAME","SAN","SAPS","SAQ","SA","ALL" `
    -AddToDefaultView
# Severity order worst -> best: Blocking > Status Required > Planned > In Progress > Monitoring > Closed
Add-PnPField -List $issuesList -DisplayName "Status" -InternalName "Status" -Type Choice `
    -Choices "Blocking","Status Required","Planned","In Progress","Monitoring","Closed" -AddToDefaultView
Add-PnPField -List $issuesList -DisplayName "Next Step" -InternalName "NextStep" -Type Note -AddToDefaultView
# Text, not Date: source data mixes free text ('TBD','Active'), work-week codes ('WW38'), and dates
Add-PnPField -List $issuesList -DisplayName "Timeline" -InternalName "Timeline" -Type Text -AddToDefaultView
Add-PnPField -List $issuesList -DisplayName "Owner" -InternalName "Owner_x0020_Field" -Type UserMulti -AddToDefaultView
Add-PnPField -List $issuesList -DisplayName "Evidence" -InternalName "Evidence" -Type URL -AddToDefaultView

# Hidden fields (kept off the default view; available in other views)
# Multi-select: an issue can span more than one parameter (e.g. "SICC;Cdyn")
Add-PnPField -List $issuesList -DisplayName "Parameter" -InternalName "Parameter" -Type MultiChoice `
    -Choices "Vmin","SICC","Cdyn","DTS","PreSi","Content"
Add-PnPField -List $issuesList -DisplayName "Affected Domain Scope" -InternalName "AffectedDomainScope" -Type Note
Add-PnPField -List $issuesList -DisplayName "Source Domain" -InternalName "SourceDomain" -Type Text
Add-PnPField -List $issuesList -DisplayName "Comments" -InternalName "Comments" -Type Note
Add-PnPField -List $issuesList -DisplayName "Current Update" -InternalName "CurrentUpdate" -Type Note
Add-PnPField -List $issuesList -DisplayName "Closed Date" -InternalName "ClosedDate" -Type DateTime
Add-PnPField -List $issuesList -DisplayName "Evidence Folder ID" -InternalName "EvidenceFolderId" -Type Text
Add-PnPField -List $issuesList -DisplayName "Automation Reference" -InternalName "AutomationReference" -Type Text
# Fallback for owner names that couldn't be auto-resolved to a directory account during import
Add-PnPField -List $issuesList -DisplayName "Owner Unresolved" -InternalName "OwnerUnresolved" -Type Text

# ---------------------------------------------------------------------------
# 4. Domain Dictionary list (pre-populated from the ALIASES / SPECIAL LOGIC sections)
# ---------------------------------------------------------------------------
$domainList = New-PnPList -Title "Domain Dictionary" -Template GenericList -EnableVersioning
Set-PnPField -List $domainList -Identity "Title" -Values @{ Title = "Canonical Domain" }
Add-PnPField -List $domainList -DisplayName "Aliases" -InternalName "Aliases" -Type Text -AddToDefaultView
Add-PnPField -List $domainList -DisplayName "Is Special Group" -InternalName "IsSpecialGroup" -Type Boolean -AddToDefaultView
Add-PnPField -List $domainList -DisplayName "Group Members" -InternalName "GroupMembers" -Type Note -AddToDefaultView
Add-PnPField -List $domainList -DisplayName "Notes" -InternalName "Notes" -Type Note

$domainRows = @(
    @{ Title = "Atom";  Aliases = "AT" }
    @{ Title = "Ring";  Aliases = "CCF" }
    @{ Title = "Core";  Aliases = "CR" }
    @{ Title = "GT";    Aliases = "" }
    @{ Title = "GTVPG"; Aliases = "" }
    @{ Title = "SAC";   Aliases = "CCLK" }
    @{ Title = "SACD";  Aliases = "Display" }
    @{ Title = "SADPU"; Aliases = "VPU,NPU" }
    @{ Title = "SAIOC"; Aliases = "" }
    @{ Title = "SAME";  Aliases = "Media" }
    @{ Title = "SAN";   Aliases = "NCLK" }
    @{ Title = "SAPS";  Aliases = "IPU" }
    @{ Title = "SAQ";   Aliases = "" }
)
foreach ($row in $domainRows) {
    Add-PnPListItem -List $domainList -Values @{
        Title = $row.Title; Aliases = $row.Aliases; IsSpecialGroup = $false
    }
}
Add-PnPListItem -List $domainList -Values @{
    Title = "SA"; IsSpecialGroup = $true
    GroupMembers = "SAC,SACD,SADPU,SAIOC,SAME,SAN,SAPS,SAQ"
}
Add-PnPListItem -List $domainList -Values @{
    Title = "ALL"; IsSpecialGroup = $true
    GroupMembers = "Atom,Ring,Core,GT,GTVPG,SAC,SACD,SADPU,SAIOC,SAME,SAN,SAPS,SAQ"
}

# ---------------------------------------------------------------------------
# 5. Heat Map Overrides list
# ---------------------------------------------------------------------------
$heatMapList = New-PnPList -Title "Heat Map Overrides" -Template GenericList -EnableVersioning
Set-PnPField -List $heatMapList -Identity "Title" -Values @{ Title = "Override Name" }
Add-PnPField -List $heatMapList -DisplayName "Domain" -InternalName "Domain" -Type Choice `
    -Choices "Atom","Ring","Core","GT","GTVPG","SAC","SACD","SADPU","SAIOC","SAME","SAN","SAPS","SAQ" -AddToDefaultView
Add-PnPField -List $heatMapList -DisplayName "Parameter" -InternalName "Parameter" -Type Choice `
    -Choices "Vmin","SICC","Cdyn","DTS","PreSi","Content" -AddToDefaultView
Add-PnPField -List $heatMapList -DisplayName "Override Status" -InternalName "OverrideStatus" -Type Choice `
    -Choices "Blocking","Status Required","Planned","In Progress","Monitoring","Closed" -AddToDefaultView
Add-PnPField -List $heatMapList -DisplayName "Reason" -InternalName "Reason" -Type Note -AddToDefaultView
Add-PnPField -List $heatMapList -DisplayName "Effective Date" -InternalName "EffectiveDate" -Type DateTime -AddToDefaultView
Add-PnPField -List $heatMapList -DisplayName "Expiry Date" -InternalName "ExpiryDate" -Type DateTime -AddToDefaultView

# ---------------------------------------------------------------------------
# 6. NVLAX Parametric Evidence document library
# ---------------------------------------------------------------------------
$evidenceLibUrl = "NVLAXParametricEvidence"
New-PnPList -Title "NVLAX Parametric Evidence" -Url $evidenceLibUrl -Template DocumentLibrary -EnableVersioning | Out-Null

# Creates the per-issue evidence folder and stamps Evidence + Evidence Folder ID
# back onto the issue item. Reused by the OneNote/Excel migration script; for new
# issues after go-live, a Power Automate flow performs the equivalent on item creation.
function New-NVLAXEvidenceFolder {
    param(
        [Parameter(Mandatory)][int]$IssueId,
        [string]$LibraryUrl = $evidenceLibUrl
    )
    $folderName = "Issue-$IssueId"
    $folder = Add-PnPFolder -Name $folderName -Folder $LibraryUrl
    $folderUrl = "$SiteUrl/$LibraryUrl/$folderName"
    Set-PnPListItem -List $issuesList -Identity $IssueId -Values @{
        Evidence         = "$folderUrl, Evidence Folder"
        EvidenceFolderId = $folder.UniqueId
    }
    return $folderUrl
}

# ---------------------------------------------------------------------------
# 7. Required views on the Open Issues list
# ---------------------------------------------------------------------------
$defaultFields = @("Issue","Priority","Domain","Status","NextStep","Timeline","Owner_x0020_Field","Evidence")

Add-PnPView -List $issuesList -Title "Open Issues" -Fields $defaultFields -Query "<Where><Neq><FieldRef Name='Status'/><Value Type='Choice'>Closed</Value></Neq></Where>"
Add-PnPView -List $issuesList -Title "Blocking Issues" -Fields $defaultFields -Query "<Where><Eq><FieldRef Name='Status'/><Value Type='Choice'>Blocking</Value></Eq></Where>"
Add-PnPView -List $issuesList -Title "Status Required Issues" -Fields $defaultFields -Query "<Where><Eq><FieldRef Name='Status'/><Value Type='Choice'>Status Required</Value></Eq></Where>"
Add-PnPView -List $issuesList -Title "By Domain" -Fields $defaultFields -Query "<GroupBy Collapse='TRUE'><FieldRef Name='Domain'/></GroupBy>"
Add-PnPView -List $issuesList -Title "By Owner" -Fields $defaultFields -Query "<GroupBy Collapse='TRUE'><FieldRef Name='Owner_x0020_Field'/></GroupBy>"
Add-PnPView -List $issuesList -Title "By Parameter" -Fields ($defaultFields + "Parameter") -Query "<GroupBy Collapse='TRUE'><FieldRef Name='Parameter'/></GroupBy>"
Add-PnPView -List $issuesList -Title "Management Review" -Fields $defaultFields -Query "<Where><Eq><FieldRef Name='Priority'/><Value Type='Choice'>P1</Value></Eq></Where><OrderBy><FieldRef Name='Timeline'/></OrderBy>"
Add-PnPView -List $issuesList -Title "Recently Updated" -Fields $defaultFields -Query "<OrderBy><FieldRef Name='Modified' Ascending='FALSE'/></OrderBy>"
Add-PnPView -List $issuesList -Title "Closed Issues" -Fields ($defaultFields + "ClosedDate") -Query "<Where><Eq><FieldRef Name='Status'/><Value Type='Choice'>Closed</Value></Eq></Where>"
Add-PnPView -List $issuesList -Title "Evidence Missing" -Fields $defaultFields -Query "<Where><IsNull><FieldRef Name='Evidence'/></IsNull></Where>"

Write-Host "Provisioning complete. Remaining manual steps:" -ForegroundColor Yellow
Write-Host "1. Migrate content from the NVLAX Parametric OneNote page manually (no Graph/OneNote API access available)." -ForegroundColor Yellow
Write-Host "2. Review/adjust Priority choice values (defaulted to High/Medium/Low)." -ForegroundColor Yellow
Write-Host "3. Add the site link to Parametric-Team.aspx (owner will do this manually)." -ForegroundColor Yellow
Write-Host "Evidence library root: $SiteUrl/$evidenceLibUrl" -ForegroundColor Cyan

Disconnect-PnPOnline
