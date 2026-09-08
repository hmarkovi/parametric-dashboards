# NVLAX PARAMETRIC TRACKING SYSTEM
## System Design Specification
Version: 1.0
Owner: MPE.CDG.IDC.PBS
Classification: Intel Internal Only

# PURPOSE
Provide a single source of truth for NVLAX parametric status, open issues, evidence management, heat-map reporting, management reviews, historical tracking, and future automation.

# SITE STRUCTURE
- NVLAX Parametric Open Issues (Microsoft List)
- NVLAX Parametric Evidence (Document Library)
- Domain Dictionary (Microsoft List)
- Heat Map Overrides (Microsoft List)

# SECURITY
Owners Group: mpe.cdg.idc.pbs@intel.com
Members: Explicitly added users plus issue owners.
External sharing disabled.

# DOMAINS
Atom, Ring, Core, GT, GTVPG, SAC, SACD, SADPU, SAIOC, SAME, SAN, SAPS, SAQ

# ALIASES
Atom=AT
Ring=CCF
Core=CR
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

# ISSUE FIELDS
Visible:
Priority, Domain, Issue, Status, Next Step, Timeline, Owner, Evidence

Hidden:
Parameter, Affected Domain Scope, Source Domain, Comments,
Current Update, Closed Date, Evidence Folder ID,
Automation Reference, Created, Modified

# PARAMETERS
Vmin, SICC, Cdyn, DTS, PreSi, Content

# EVIDENCE LIBRARY
Supports PNG, JPG, DOCX, PPTX, XLSX, PDF, TXT.
One folder per issue.
Evidence links point to library, never OneNote.

# HEAT MAP
Rows = Canonical domains.
Columns = Vmin,SICC,Cdyn,DTS,PreSi,Content.
Worst status wins.
Manual overrides stored separately.

# VERSION CONTROL
Enable version history on:
- Issue List
- Evidence Library
- Domain Dictionary
- Heat Map Overrides

Recoverable:
- List items
- Comments
- Status changes
- DOCX/PPTX/XLSX/PDF/Image revisions
- Alias definitions

# REQUIRED VIEWS
Open Issues
Blocking Issues
At Risk Issues
By Domain
By Owner
By Parameter
Management Review
Recently Updated
Closed Issues
Evidence Missing

# MIGRATION SOURCE
Single source page: NVLAX Parametric OneNote page.

# FUTURE EXTENSIONS
Issue Aging
Escalation Tracking
Validation Tracking
Notifications
Dashboard Integration
Power Automate
Graph API Integration
