# NVLAX PARAMETRIC TRACKING SYSTEM
## System Design Specification
Version: 1.0
Owner: MPE.CDG.IDC.PBS
Classification: Intel Internal Only

# PURPOSE
Provide a single source of truth for NVLAX parametric status, open issues, evidence management, heat-map reporting, management reviews, historical tracking, and future automation.

# SITE STRUCTURE
Hosted on the existing site: https://intel.sharepoint.com/sites/ybsclientidc
(no new site collection; no changes to existing site content, settings, or permissions -
only net-new additions below)
- NVLAX Parametric Open Issues (Microsoft List)
- NVLAX Parametric Evidence (Document Library)
- NVLAX Domain Dictionary (Microsoft List)
- NVLAX Heat Map Overrides (Microsoft List)
- NVLAX Parametric Tracking (new dedicated page, landing/dashboard for this system)

# SECURITY
Inherits the existing ybsclientidc site's permissions and sharing settings as-is.
No new owners group, no membership changes, no sharing-setting changes are made.
Access is whatever a user already has on the existing site.

# DOMAINS
Atom, Ring, Core, GT, GTVPG, SAC, SACD, SADPU, SAIOC, SAME, SAN, SAPS, SAQ

# ALIASES
Atom=AT
Ring=CCF
Core=CR,IA
SAC=CCLK
SACD=Display
SADPU=VPU,NPU
SAME=Media
SAN=NCLK
SAPS=IPU

# SPECIAL LOGIC
SA => SAC,SACD,SADPU,SAIOC,SAME,SAN,SAPS,SAQ
ALL => all canonical domains
Preserve original source domain text.

Domain field is multi-select (Domain can span more than one canonical domain per issue).
Domain normalization on import (derived from Affected Domain Scope, since Source Domain
is free text, e.g. "SA-Atom", "Core / IA"). Each scope token is resolved to a canonical
domain via direct match or the ALIASES table above:
- All tokens resolve, and the resolved set == all 13 canonical domains => Domain = ALL
- All tokens resolve, and the resolved set == exact SA group (8 domains) => Domain = SA
- All tokens resolve, otherwise => Domain = the resolved canonical domain(s), listed directly (multi-select)
- Any token does NOT resolve to a canonical domain or alias => approximate: fall back to SA/ALL
  (whichever best fits the recognizable tokens) and flag the unresolved token(s) for manual review

# PRIORITY VALUES
P1 (red, most urgent), P2 (amber), P3 (green).

# STATUS VALUES
Severity order, worst to best (drives heat map "worst status wins"):
Blocking > Status Required > Planned > In Progress > Monitoring > Closed

# ISSUE FIELDS
Visible:
Priority, Domain, Issue, Status, Next Step, Timeline, Owner, Evidence

Hidden:
Parameter, Affected Domain Scope, Source Domain, Comments,
Current Update, Closed Date, Evidence Folder ID,
Automation Reference, Owner Unresolved, Created, Modified

Field type notes:
- Parameter: multi-select (an issue can span more than one parameter, e.g. "SICC;Cdyn").
- Timeline: plain text (data mixes free text, work-week codes, and dates - not a clean date field).
- Owner: People field (multi-value); import script auto-resolves free-text names against the
  tenant directory. Unresolved names are preserved in the hidden Owner Unresolved text field for
  manual correction.

# PARAMETERS
Vmin, SICC, Cdyn, DTS, PreSi, Content

# EVIDENCE LIBRARY
Supports PNG, JPG, DOCX, PPTX, XLSX, PDF, TXT.
One folder per issue.
Evidence links point to library, never OneNote.

# EVIDENCE LINKING
Library root: https://intel.sharepoint.com/sites/ybsclientidc/NVLAXParametricEvidence
Folder naming: Issue-<ListItemID> (e.g. Issue-42), created at the same time as the issue.
Folder path pattern: <Library root>/Issue-<ListItemID>
On issue creation:
- Create the matching folder under the library root.
- Populate the issue's Evidence field with a direct hyperlink to the folder.
- Populate the hidden Evidence Folder ID field with the folder's unique ID (GUID), for automation reference.
Ongoing new issues: Power Automate flow (trigger on item creation) creates the folder and writes back Evidence + Evidence Folder ID.
Existing/migrated issues: created in bulk by the migration script at import time.

# HEAT MAP
Rows = Canonical domains.
Columns = Vmin,SICC,Cdyn,DTS,PreSi,Content.
Worst status wins.
Manual overrides stored separately.

# VERSION CONTROL
Enable version history on:
- Issue List
- Evidence Library
- NVLAX Domain Dictionary
- NVLAX Heat Map Overrides

Recoverable:
- List items
- Comments
- Status changes
- DOCX/PPTX/XLSX/PDF/Image revisions
- Alias definitions

# REQUIRED VIEWS
Open Issues
Blocking Issues
Status Required Issues
By Domain
By Owner
By Parameter
Management Review
Recently Updated
Closed Issues
Evidence Missing

# MIGRATION SOURCE
Single source page: NVLAX Parametric OneNote page.
Landing page: NVLAX Parametric Tracking page on the existing ybsclientidc site, embedding
a view of the Open Issues list (replaces the earlier plan to link from Parametric-Team.aspx).

# FUTURE EXTENSIONS
Issue Aging
Escalation Tracking
Validation Tracking
Notifications
Dashboard Integration
Power Automate
Graph API Integration
