# Weekly Automation Build Session — Chat Log

**Session ID:** 01ead9ee-e890-417a-810b-d3155d7c5267
**Date:** 2026-06-02

---

### Assistant

I’m checking the existing script locally to find the lot filter, output format, and ILAS enrichment path, then I’ll run the narrow validation against the single lot without touching the weekly schedule settings.This first pass is just to verify whether the script already supports a one-lot override and CSV output, or whether a minimal probe edit is needed before execution.

---

### Assistant

The script already advertises both `LotsOverride` and ILAS enrichment in repo notes; I’m reading the execution path now to confirm the final artifact is the clean CSV and to see the exact command line I should use for a one-lot run.

---

### Assistant

The script path is clear: `-LotsOverride` switches from `-lotsfromfs` to a fixed lot, ILAS stays enabled by default, and the final artifact is the enriched CSV. I’m running that exact validation now with only the lot override added.

---

### Assistant

The run exposed a local parser break in the script itself, centered near the health-log path; I’m reading just the affected block to repair that syntax defect and rerun the same one-lot validation.

---

### Assistant

I’m making the smallest possible fix: close the broken string literal in the `finally` block, then I’ll rerun the same one-lot command before touching anything else.

---

### Assistant

The parser defect is patched. I’m rerunning the exact validation invocation now to see whether the script completes and produces the enriched CSV for lot `Y6220110`.

---

## User — Message 1

Try Again

---

### Assistant

The same parser error persisted, which means there’s likely another unmatched quote earlier that only surfaces at the health-log line; I’m now scanning the script with line numbers and quote counts to locate the true unclosed string and fix it directly.

---

### Assistant

I found no smart-quote characters, so I’m now checking for an unclosed here-string or escape continuation that can make a normal quote look unterminated at line 663.

---

### Assistant

I’m now checking the full `Parse-IlasVminDts` and `Enrich-WeeklyReportWithIlasData` region because the parser’s secondary errors start exactly there, which usually means the real unterminated string is inside that function body.

---

### Assistant

Parser still flags the same location even in a regenerated temporary copy, so I’m inspecting parser tokens near EOF to identify where it starts treating content as a dangling string.

---

### Assistant

I’ve isolated the break to the logging block near the end, so I’m replacing that block with a simpler equivalent construction to remove any hidden token corruption while preserving behavior. Then I’ll re-validate syntax and re-run the one-lot job.

---

### Assistant

Syntax now validates cleanly. I’m executing the requested one-lot run (`Y6220110`) with unchanged weekly schedule parameters and ILAS enrichment still enabled, then I’ll verify the generated final CSV and enrichment columns.

---

### Assistant

The Aqua process is still actively running, so the job hasn’t finished yet. I’m checking the network output folder for in-progress `_raw`/`Vmin` CSVs tied to this run stamp to confirm it is writing results.

---

### Assistant

Progress update: the run has advanced and now produced today’s raw file (`_raw_20260602_135633.csv`), so it is no longer stuck at startup. I’m monitoring until the final enriched `Vmin_...csv` appears and then I’ll validate ILAS columns in it.

---

## User — Message 2

what is the issue that is taking so long? which step are you stuck at?

---

### Assistant

I’m pulling the latest run snapshot and process state so I can tell you exactly where it stalled and why it took long.

---

### Assistant

The delay is at the ILAS enrichment pull step, not the main weekly pull.

Current stuck point:
1. Main report completed successfully.
2. Filtering/classhot + visual-unit limiting completed.
3. It then started the second AQUA call for ILAS:
   - Report: `sbelyy\ILAS\ILAS_VMIN_DTS`
   - Lot arg: `-lots Y6220110`
4. It is waiting at: `Waiting for AQUA to prepare report results...` for that ILAS query.

So the bottleneck is AQUA server-side preparation for the ILAS report (second pull), not your weekly schedule parameters or CSV export step. The final CSV write only happens after this ILAS step returns.

---

## User — Message 3

lets change direction. change the script to include in this automation only the first steps related to the Aqua querry data pulling related to "hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12" and the data cleaning and file creation of this data. omit all script that is related to the ILAS querry.

---

### Assistant

I’ll surgically strip ILAS-specific flow from the script and keep only the main AQUA pull (`hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12`), cleaning/filtering, and CSV output creation, then validate syntax.

---

### Assistant

I confirmed all ILAS-related pieces are localized, so next I’m removing the ILAS parameters/functions and the second AQUA pass, leaving only main pull, clean, and CSV creation flow.

---

### Assistant

ILAS references are now removed; I’m doing a parser check to ensure the trimmed script is still fully runnable.

---

### Assistant

Updated the script to run only the main AQUA flow and omit all ILAS logic.

What I changed in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1):
1. Removed ILAS parameters from `param(...)`:
   - `IlasReportPath`
   - `EnableIlasEnrichment`
2. Removed ILAS-only functions:
   - `Parse-IlasVminDts`
   - `Enrich-WeeklyReportWithIlasData`
3. Removed the entire second AQUA call block for ILAS (`sbelyy\ILAS\ILAS_VMIN_DTS`).
4. Removed ILAS enrichment branching and ILAS logging lines.
5. Kept only:
   - Main AQUA pull from `hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12`
   - Existing cleaning/filtering (`*MV` exclusion, `Classhot`, visual-unit cap, DS-column drop)
   - Clean CSV + final CSV output file creation
   - Retention + health/log writing

Validation:
1. PowerShell parser check returns `PARSER_OK`.

If you want, I can run the trimmed script now for lot `Y6220110` to confirm runtime and output file names end-to-end.

---

## User — Message 4

validate for the specifiic lot mentioned

---

### Assistant

I’ll run the trimmed script for lot `Y6220110`, then verify the generated CSV files and row counts so you have a concrete validation result.

---

### Assistant

I’m now checking the live run state and produced files directly (not the buffered historical transcript) so we can confirm whether this lot validation actually completed and what outputs were created.

---

### Assistant

The validation run is active and currently blocked upstream in AQUA report preparation; I’m polling once more for completion and then I’ll report the concrete pass/fail with output file paths.

---

### Assistant

The current full-size run is still waiting on AQUA preparation, so I’m switching to a faster validation pass on the same lot using reduced sampling (`AquaMaxRows`) to confirm end-to-end script behavior and output creation.

---

## User — Message 5

[Terminal d74310bf-befb-40e8-947a-0457ef183146 notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize | Out-String

   Id ProcessName StartTime          
   -- ----------- ---------          
32416 AquaCmdLine 6/2/2026 1:56:33 PM



PS C:\Projects\NVL\.docs> Get-ChildItem "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 8 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String


Name                                        Length LastWriteTime        
----                                        ------ -------------        
2026_22_NVLH_30k_UPM_data.jmp             58049737 5/27/2026 9:29:46 AM 
2026_19_nvl_min_to _max.jmp               22934394 5/20/2026 10:42:27 AM
2026_04_NVLH_NVLHX_NVLAX Vmin stacked.jmp 26777189 1/27/2026 3:01:12 PM 
2026_04_NVLH_NVLHX_NVLAX RAW DATA.jmp     11908300 1/27/2026 2:27:06 PM 
2026_04_NVLH_NVLHX_NVLAX.jmp              43811345 1/27/2026 2:26:04 PM 



PS C:\Projects\NVL\.docs> Get-ChildItem "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs" -File -Filter "_raw_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String

PS C:\Projects\NVL\.docs> Get-ChildItem "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs" -File -Filter "Vmin_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String

PS C:\Projects\NVL\.docs> $path='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; if(Test-Path $path){'PATH_OK'; Get-ChildItem $path -File | Where-Object { $_.Name -like '_raw_*.csv' -or $_.Name -like 'Vmin_*.csv' -or $_.Name -like '_clean_*.csv' -or $_.Name -like '_ilas_*.csv' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String}else{'PATH_MISSING'}
PATH_OK

PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_RY0NTn7RFNX71FuqGw1vZeyX__vscode-1780385092022\content.txt" -Tail 80 | Out-String
         Generic  637 days" -f $RetentionDays...                               
      Identifier  641 ILAS                                                     
         Generic  641 enrichment:                                              
      Identifier  641 enabled                                                  
           Comma  641 ,                                                        
      Identifier  641 added                                                    
      Identifier  641 test                                                     
         Generic  641 instance/LP/DTS                                          
      Identifier  641 columns                                                  
         Generic  641 for                                                      
          LCurly  641 {                                                        
          Number  641 0                                                        
          RCurly  641 }                                                        
         Generic  641 mappings" -f $ilasLookup.Count...                        
         Generic  645 JMP:                                                     
         Generic  645 $cleanCsvPath"...                                        
         Generic  646 CSV:                                                     
         Generic  646 $csvPath"...                                             
         Generic  647 file:                                                    
         Generic  647 $logPath"...                                             
         Generic  648 before:                                                  
     DollarParen  648 $(                                                       
        Variable  648 $rows                                                    
             Dot  648 .                                                        
      Identifier  648 Count                                                    
          RParen  648 )                                                        
StringExpandable  648 "...                                                     
      Identifier  649 Rows                                                     
         Generic  649 after:                                                   
     DollarParen  649 $(                                                       
        Variable  649 $filteredRows                                            
             Dot  649 .                                                        
      Identifier  649 Count                                                    
          RParen  649 )                                                        
StringExpandable  649 "...                                                     
      Identifier  650 AQUA                                                     
      Identifier  650 sampling                                                 
         Generic  650 cap:                                                     
         Generic  650 $AquaMaxRows"...                                         
      Identifier  651 units                                                    
         Generic  651 kept:                                                    
         Generic  651 $visualUnitCount"...                                     
         Generic  652 program:                                                 
         Generic  652 $mostAbundantProgram"...                                 
      Identifier  655 completed                                                
         Generic  655 successfully"...                                         
      EndOfInput  675                                                          



PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "CHARS: " + (($l.ToCharArray()|%{[int][char]$_}) -join ',')}
At line:1 char:104
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> $f='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv'; if(Test-Path $f){Get-Item $f | Select-Object FullName,Length,LastWriteTime | Format-List | Out-String}else{'RAW_NOT_CREATED'}
RAW_NOT_CREATED
PS C:\Projects\NVL\.docs> Get-Process -Id 32416 | Select-Object Id,ProcessName,CPU,StartTime,Responding,WS | Format-List | Out-String


Id          : 32416
ProcessName : AquaCmdLine
CPU         : 2.8125
StartTime   : 6/2/2026 1:56:33 PM
Responding  : True
WS          : 71016448




PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_S6VmBMllfsOw3DBfUBxyneg8__vscode-1780385092026\content.txt" -Tail 20 | Out-String
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> if (Test-Path .\Scripts\_tmp_parse_test.ps1) { Remove-Item .\Scripts\_tmp_parse_test.ps1 -Force }
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,CPU,StartTime,@{N='ElapsedMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String

  Id      CPU StartTime           ElapsedMin
  --      --- ---------           ----------
1584 1.890625 6/2/2026 2:04:19 PM        0.6



PS C:\Projects\NVL\.docs> $path='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; Get-ChildItem $path -File | Where-Object { $_.Name -like '_raw_20260602_*.csv' -or $_.Name -like '_clean_20260602_*.csv' -or $_.Name -like 'Vmin_*_WW23_2026*.csv' -or $_.Name -like '_ilas_20260602_*.csv' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String

Name                      Length LastWriteTime      
----                      ------ -------------      
_raw_20260602_135633.csv 1782311 6/2/2026 2:04:15 PM



PS C:\Projects\NVL\.docs> $path='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; Get-ChildItem $path -File | Where-Object { $_.Name -like 'Vmin_*.csv' -or $_.Name -like '_clean_20260602_*.csv' -or $_.Name -like '_ilas_20260602_*.csv' } | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String

PS C:\Projects\NVL\.docs> $p='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; Get-ChildItem $p -File -Filter 'Vmin_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,Length,LastWriteTime
PS C:\Projects\NVL\.docs> $p='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; Get-ChildItem $p -File -Filter '_clean_20260602_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name,Length,LastWriteTime
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_OELKP6EcmIx0UGlBfoAPsv9u__vscode-1780385092031\content.txt" -Tail 60
      Identifier  649 Count                                                    
          RParen  649 )                                                        
StringExpandable  649 "...                                                     
      Identifier  650 AQUA                                                     
      Identifier  650 sampling                                                 
         Generic  650 cap:                                                     
         Generic  650 $AquaMaxRows"...                                         
      Identifier  651 units                                                    
         Generic  651 kept:                                                    
         Generic  651 $visualUnitCount"...                                     
         Generic  652 program:                                                 
         Generic  652 $mostAbundantProgram"...                                 
      Identifier  655 completed                                                
         Generic  655 successfully"...                                         
      EndOfInput  675                                                          



PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "CHARS: " + (($l.ToCharArray()|%{[int][char]$_}) -join ',')}
At line:1 char:104
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_nWw2CLP8FsZubwvgQXgmK0nf__vscode-1780385092037\content.txt" -Tail 80
          RCurly  641 }                                                        
         Generic  641 mappings" -f $ilasLookup.Count...                        
         Generic  645 JMP:                                                     
         Generic  645 $cleanCsvPath"...                                        
         Generic  646 CSV:                                                     
         Generic  646 $csvPath"...                                             
         Generic  647 file:                                                    
         Generic  647 $logPath"...                                             
         Generic  648 before:                                                  
     DollarParen  648 $(                                                       
        Variable  648 $rows                                                    
             Dot  648 .                                                        
      Identifier  648 Count                                                    
          RParen  648 )                                                        
StringExpandable  648 "...                                                     
      Identifier  649 Rows                                                     
         Generic  649 after:                                                   
     DollarParen  649 $(                                                       
        Variable  649 $filteredRows                                            
             Dot  649 .                                                        
      Identifier  649 Count                                                    
          RParen  649 )                                                        
StringExpandable  649 "...                                                     
      Identifier  650 AQUA                                                     
      Identifier  650 sampling                                                 
         Generic  650 cap:                                                     
         Generic  650 $AquaMaxRows"...                                         
      Identifier  651 units                                                    
         Generic  651 kept:                                                    
         Generic  651 $visualUnitCount"...                                     
         Generic  652 program:                                                 
         Generic  652 $mostAbundantProgram"...                                 
      Identifier  655 completed                                                
         Generic  655 successfully"...                                         
      EndOfInput  675                                                          



PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "CHARS: " + (($l.ToCharArray()|%{[int][char]$_}) -join ',')}
At line:1 char:104
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> $f='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv'; if(Test-Path $f){Get-Item $f | Select-Object FullName,Length,LastWriteTime | Format-List | Out-String}else{'ILAS_NOT_CREATED'}
ILAS_NOT_CREATED
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,CPU,StartTime,@{N='ElapsedMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String

  Id     CPU StartTime           ElapsedMin
  --     --- ---------           ----------
1584 2.15625 6/2/2026 2:04:19 PM        2.4



PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_q4f4EV68VYy2lUDYxkEvaPcc__vscode-1780385092041\content.txt" -Tail 30
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,CPU | Format-Table -AutoSize | Out-String

  Id ProcessName StartTime               CPU
  -- ----------- ---------               ---
1584 AquaCmdLine 6/2/2026 2:04:19 PM 2.15625



PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_q4f4EV68VYy2lUDYxkEvaPcc__vscode-1780385092041\content.txt" -Tail 40 | Out-String
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_141628.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
AQUA did not create output file. Check AQUA message for report path/permission 
errors.
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1:313 char:9
+         throw "AQUA did not create output file. Check AQUA message fo ...
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (AQUA did not cr...mission err 
   ors.:String) [], RuntimeException
    + FullyQualifiedErrorId : AQUA did not create output file. Check AQUA mess 
   age for report path/permission errors.

---

### Assistant

I now have a concrete failure message from the lot run; I’m grabbing the active reduced-sampling run status too so I can give you one definitive validation verdict.

---

## User — Message 6

[Terminal b7d9d509-aa21-4281-96dd-b6cc00ea4fdf notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> $p='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs'; Get-ChildItem $p -File | Where-Object { $_.Name -like '_raw_20260602_*.csv' -or $_.Name -like '_clean_20260602_*.csv' -or $_.Name -like 'Vmin_*_WW23_2026*.csv' } | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String

Name                      Length LastWriteTime      
----                      ------ -------------      
_raw_20260602_135633.csv 1782311 6/2/2026 2:04:15 PM



PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,CPU,StartTime,@{N='ElapsedMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String

   Id    CPU StartTime           ElapsedMin
   --    --- ---------           ----------
48876 2.5625 6/2/2026 2:16:28 PM        2.6



PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_sId7hvimZu4oXEoCWvbDvo3f__vscode-1780385092057\content.txt" -Tail 80 | Out-String
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,CPU | Format-Table -AutoSize | Out-String

  Id ProcessName StartTime               CPU
  -- ----------- ---------               ---
1584 AquaCmdLine 6/2/2026 2:04:19 PM 2.15625



PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_q4f4EV68VYy2lUDYxkEvaPcc__vscode-1780385092041\content.txt" -Tail 40 | Out-String
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_141628.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> $f='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_141628.csv'; if(Test-Path $f){Get-Item $f | Select-Object FullName,Length,LastWriteTime | Format-List | Out-String}else{'RAW_141628_NOT_CREATED'}
RAW_141628_NOT_CREATED
PS C:\Projects\NVL\.docs> Get-Process -Id 48876 -ErrorAction SilentlyContinue | Select-Object Id,CPU,StartTime,@{N='ElapsedMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}},Responding | Format-List | Out-String


Id         : 48876
CPU        : 2.5625
StartTime  : 6/2/2026 2:16:28 PM
ElapsedMin : 3.4
Responding : True




PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_rNiSHu7i8Dhqi6x45GCTYb4H__vscode-1780385092063\content.txt" -Tail 60 | Out-String
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,CPU | Format-Table -AutoSize | Out-String

  Id ProcessName StartTime               CPU
  -- ----------- ---------               ---
1584 AquaCmdLine 6/2/2026 2:04:19 PM 2.15625



PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_q4f4EV68VYy2lUDYxkEvaPcc__vscode-1780385092041\content.txt" -Tail 40 | Out-String
+ ... _pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; "LINE $n: $l"; "C ...
+                                                               ~~~
Variable reference is not valid. ':' was not followed by a valid variable name 
character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordEx 
   ception
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
 
PS C:\Projects\NVL\.docs> $lines=Get-Content .\Scripts\aqua_nvlh_weekly_pull.ps1; foreach($n in 633..637){$l=$lines[$n-1]; ('LINE {0}: {1}' -f $n,$l); ('CHARS: ' + (($l.ToCharArray()|ForEach-Object {[int][char]$_}) -join ','))}
LINE 633:         "- Visual units kept: {0} (cap {1})" -f $visualUnitCount, $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,86,105,115,117,97,108,32,117,110,105,116,115,32,107,101,112,116,58,32,123,48,125,32,40,99,97,112,32,123,49,125,41,34,32,45,102,32,36,118,105,115,117,97,108,85,110,105,116,67,111,117,110,116,44,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 634:         "- Clean CSV: {0}" -f $cleanCsvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,67,108,101,97,110,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,108,101,97,110,67,115,118,80,97,116,104,44
LINE 635:         "- Final output CSV: {0}" -f $csvPath,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,110,97,108,32,111,117,116,112,117,116,32,67,83,86,58,32,123,48,125,34,32,45,102,32,36,99,115,118,80,97,116,104,44
LINE 636:         "- Filters: exclude lot suffix MV; keep RCS_PROCESSSTEP=Classhot; limit to {0} visual units" -f $MaxVisualUnits,
CHARS: 32,32,32,32,32,32,32,32,34,45,32,70,105,108,116,101,114,115,58,32,101,120,99,108,117,100,101,32,108,111,116,32,115,117,102,102,105,120,32,77,86,59,32,107,101,101,112,32,82,67,83,95,80,82,79,67,69,83,83,83,84,69,80,61,67,108,97,115,115,104,111,116,59,32,108,105,109,105,116,32,116,111,32,123,48,125,32,118,105,115,117,97,108,32,117,110,105,116,115,34,32,45,102,32,36,77,97,120,86,105,115,117,97,108,85,110,105,116,115,44
LINE 637:         "- Retention: prune files and log entries older than {0} days" -f $RetentionDays
CHARS: 32,32,32,32,32,32,32,32,34,45,32,82,101,116,101,110,116,105,111,110,58,32,112,114,117,110,101,32,102,105,108,101,115,32,97,110,100,32,108,111,103,32,101,110,116,114,105,101,115,32,111,108,100,101,114,32,116,104,97,110,32,123,48,125,32,100,97,121,115,34,32,45,102,32,36,82,101,116,101,110,116,105,111,110,68,97,121,115
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv
Done.

Dropping 75 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Pulling ILAS VMIN_DTS for post-cleaning enrichment...
  - Allowed Visual IDs: 47
  - ILAS lot args: -lots Y6220110
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_20260602_135633.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_weekly_pull.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110"
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_141628.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...

PS C:\Projects\NVL\.docs> Get-Process -Name AquaCmdLine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; .\Scripts\aqua_nvlh_weekly_pull.ps1 -LotsOverride "Y6220110" -AquaMaxRows 20000
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_142037.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
AQUA did not create output file. Check AQUA message for report path/permission 
errors.
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1:313 char:9
+         throw "AQUA did not create output file. Check AQUA message fo ...
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (AQUA did not cr...mission err 
   ors.:String) [], RuntimeException
    + FullyQualifiedErrorId : AQUA did not create output file. Check AQUA mess 
   age for report path/permission errors.

---

### Assistant

Validation for lot Y6220110 is failing at the AQUA pull stage.

What I validated:
1. Ran the updated script on Y6220110 from [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1).
2. Re-ran with reduced sampling (-AquaMaxRows 20000) to rule out volume/timeout effects.
3. Checked output directory artifacts after each run.

Result:
1. Validation failed in both runs.
2. Failure is at [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L313) where it throws:
   AQUA did not create output file. Check AQUA message for report path/permission errors.
3. No final clean/final CSV was produced for these new attempts, and the expected raw files for current run stamps were not created.

Conclusion:
The script logic is parsing fine, but AQUA is not returning/writing the raw output file for this lot run, so end-to-end validation cannot complete right now.

Next steps:
1. Retry later (AQUA prep stage appears intermittently stalled).
2. Run AquaCmdLine manually with the same report and lot to capture any server-side or permission detail.
3. Verify write access to the target share path and confirm the report path is currently valid on the AQUA server.

---

## User — Message 7

automation did not wait sufficient time for Aqua to finish pulling. give time in the automation for the Aqua pull to finish. now, complete run with the already pulled data from Aqua instead of re-running

---

### Assistant

I’ll update the script in two ways: add a robust wait window for AQUA file creation, and add a “reuse existing raw file” mode so we can finish this run from already pulled data without hitting AQUA again. Then I’ll execute it against your existing raw file.

---

### Assistant

I’m patching the script now with a timed wait-for-file mechanism plus a `RawInputFile` override, then I’ll run it using your existing `_raw_20260602_135633.csv` so it completes without another AQUA pull.

---

### Assistant

The reuse path worked and got all the way to retention logging; it failed on a strict-mode edge case in `Update-LogRetention` when the log has a single line. I’ll apply a one-line robustness fix and rerun from the same raw file.

---

### Assistant

Completed. I implemented both requested changes and finished the run from already pulled data (no new AQUA pull).

1. Added wait time in automation for AQUA output readiness:
- New params in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L13):
  - `AquaPullTimeoutSeconds = 900`
  - `AquaPullPollSeconds = 10`
- New wait helper in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L226):
  - `Wait-ForFileReady` waits for file creation and stable size before continuing.
- Applied after AQUA call in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L362).

2. Added “use already pulled raw data” mode:
- New param in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L15):
  - `RawInputFile`
- Branch to skip AQUA query and reuse existing raw file in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L341).

3. Fixed a strict-mode edge case encountered during completion:
- `Update-LogRetention` now always treats content as an array in [Scripts/aqua_nvlh_weekly_pull.ps1](Scripts/aqua_nvlh_weekly_pull.ps1#L148).

Run completed from existing raw file:
- Command used:
  - `.\Scripts\aqua_nvlh_weekly_pull.ps1 -RawInputFile "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_raw_20260602_135633.csv"`
- Completion summary:
  - Rows before: 55
  - Rows after: 55
  - Visual units kept: 47
  - Top program: `NVLHM66A0H30M00S622`
- Output files created:
  - `\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026_clean.csv`
  - `\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv`
- Validation check on final CSV:
  - Distinct lot = `Y6220110`
  - Distinct process step = `CLASSHOT`

---

## User — Message 8

in a new automation code I would like to excute seperatly the Vmin limiter analysis from the "ILAS_VMIN_DTS"  querry.  the Vmin of the units is set by different tests, Scan Functional and Array. the raw results of these tests and thier temeprature are pulled by this Aqua querry -aquaserver GER -reportpath sbelyy\ILAS\ILAS_VMIN_DTS. the data format for the ILAS Vmin_DTS querry is: 1. each class test, include the test name.for example "IPC::FUN_CORE_CX48::SBFT_CORE_VMIN_K_F5XCR_X_CR_F7_5000_SLC_DRG" and the out put is the Vmin per Core delimited by _ so 1.150_1.170 is the Vmin for PHYSICAL Core1 And PHYSICAL Core2. 2. Limiter pattern: second print IPC::FUN_CORE_CX48::SBFT_CORE_VMIN_K_F5XCR_X_CR_F7_5000_SLC_DRG_lp
 is the limiter pattern which is a name of a specific test. 3. third print is the IPC::FUN_CORE_CX48::SBFT_CORE_VMIN_K_F5XCR_X_CR_F7_5000_SLC_DRG_vminFwCfg
 which defines the domain and frequecy this test reports to CR1@F7:1:5.000_CR0@F7:1:5.000
4. print is the test temperature DTS: "IPC::FUN_CORE_CX48::SBFT_CORE_VMIN_K_F5XCR_X_CR_F7_5000_SLC_DRG_DTS
" and the test result is a concatenated list of temperature readouts. "AON:75.00|CCF0S0:79.00|CCF0S1:79.00|CCF0S2:80.50|CCF0S3:78.00|CCF0S4:78.00|CCF0S5:82.50|CCF0S6:78.50|CCF0S7:77.50|CCF0S8:78.00|CCF0S9:78.00|CCF1S0:78.00|CCF1S1:79.50|CCF1S2:79.50|CCF1S3:79.00|A0S0:78.00|A0S2:78.50|A0S3:77.50|A0S4:78.00|A0S5:78.00|A0S6:78.00|A0S7:78.00|A0S8:77.00|A0S9:78.00|A0S10:78.00|A0S11:78.00|A0S12:78.00|A0S13:77.50|A0S14:77.00|A0S16:77.50|A0S17:78.50|A0S18:77.50|A0S19:78.00|A0S20:78.50|A0S21:78.50|A0S24:79.00|A0S25:78.50|A0S26:78.50|A0S27:79.00|A0S28:79.50|A0S29:78.50|A1S0:78.50|A1S2:78.00|A1S3:78.00|A1S4:78.50|A1S5:77.50|A1S6:78.00|A1S7:78.00|A1S8:78.50|A1S9:78.50|A1S10:78.00|A1S11:79.00|A1S12:78.50|A1S13:78.50|A1S14:78.00|A1S16:77.50|A1S17:78.00|A1S18:77.50|A1S19:77.50|A1S20:77.50|A1S21:77.50|A1S24:79.00|A1S25:79.00|A1S26:79.00|A1S27:80.00|A1S28:81.50|A1S29:80.00|C0S0:91.00|C0S1:90.50|C0S2:86.00|C0S3:91.50|C0S4:89.50|C0S5:85.00|C0S6:97.00|C0S7:81.50|C0S8:87.00|C0S9:91.50|C0S10:90.00|C0S11:85.00|C0S12:91.50|C0S13:91.50|C0S14:79.50|C0S15:81.00|C0S16:90.00|C0S17:90.50|C0S18:87.00|C1S0:86.50|C1S1:87.50|C1S2:87.50|C1S3:86.00|C1S4:86.00|C1S5:82.50|C1S6:88.00|C1S7:80.00|C1S8:84.00|C1S9:87.00|C1S10:86.50|C1S11:87.00|C1S12:89.50|C1S13:87.50|C1S14:80.50|C1S15:81.00|C1S16:85.00|C1S17:86.50|C1S18:86.00|C2S0:90.00|C2S1:90.50|C2S2:85.50|C2S3:91.00|C2S4:88.50|C2S5:84.00|C2S6:96.00|C2S7:79.50|C2S8:86.00|C2S9:91.00|C2S10:89.50|C2S11:83.50|C2S12:90.50|C2S13:91.00|C2S14:78.50|C2S15:79.50|C2S16:89.00|C2S17:89.00|C2S18:86.00|C3S0:86.00|C3S1:87.00|C3S2:87.00|C3S3:85.00|C3S4:85.00|C3S5:83.00|C3S6:88.00|C3S7:80.50|C3S8:84.50|C3S9:86.00|C3S10:86.50|C3S11:85.50|C3S12:89.00|C3S13:86.00|C3S14:80.50|C3S15:79.50|C3S16:84.50|C3S17:85.50|C3S18:85.00
" post parsing only the temperature reading is significant for example for  |A0S28:79.5| temp is 79.5. from the genral large DTS print only max of all temperatures should be considered per test.

---

### Assistant

I'll read the existing script's structure (parameters, helpers, `Wait-ForFileReady`) first to reuse them cleanly in the new analysis script.

---

### Assistant

I have everything I need. Creating the new ILAS Vmin analysis script now.

---

### Assistant

Script created at [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1) — `PARSER_OK`.

**What the script does:**

| Step | Detail |
|------|--------|
| Pull | Calls `sbelyy\ILAS\ILAS_VMIN_DTS` via AquaCmdLine with the same wait-for-file logic as the weekly pull. Supports `-RawInputFile` to skip re-pulling. |
| Detect columns | Finds all columns matching `*VMIN*` that are NOT `_lp`/`_DTS`/`_vminFwCfg` suffixes — those are the base test columns. |
| Expand Vmin | Splits the `_`-delimited Vmin string (e.g. `1.150_1.170`) into one row per core slot. Skips zero/untested slots. |
| Decode config | Parses `_vminFwCfg` (e.g. `CR1@F7:1:5.000_CR0@F7:1:5.000`) — extracts `Domain` (`CR1`) and `FreqGHz` (`5.000`) per core slot. |
| Max DTS | Parses the `\|`-delimited `Sensor:Temp` string from `_DTS`, returns the single max value across all sensors for that test. |
| Output | Flat CSV with one row per (VisualID, TestName, CoreSlot, Domain, FreqGHz, Vmin, LimiterPattern, MaxDTS_C). |

**Usage examples:**
```powershell
# Pull from AQUA for a specific lot
.\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -LotsOverride "Y6220110"

# Use an already pulled ILAS raw file
.\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "\\ger\...\Weekly Runs\_ilas_20260602_135633.csv"
```

---

## User — Message 9

BEFORE VALIDATION, on top of this, 
1. the rule for test instances that impact Vmin is that the instance name include the word Vmin- exclude any instance that does not contain "_VMIN_". 

2. in the ILAS Aqua querry output, the data is stacked by TEST name. so for each VISUAL_ID all tests results are printed, by row. for example 1 visual_id will have both "IPC::FUN_CORE_CX48::SBFT_CORE_VMIN_K_F5XCR_X_CR_F7_5000_SLC_DRG" as well as "XSA_HUB_VMIN_K_F2XSN_X_VCCSA_F2_X_DISP" and all test results along side with thier DTS _lp and _vminFwCfg.

3. for any Domain, i.e. Core, and every test frequency many instances may impact the Vmin. the max of all that report Vmin to this specific vminFwCfg will set the Vmin which is reported to the UPSVF token "VA-IN-NA-GSDS_D_S::UPSVFPASSFLOWPU5_RCS_CR_5.000_1" there is one artifact, the physucal core numeration as dipicted in the vminFwCfg is reversed in the UPSVFPASSFLOW. meaning physical Core0 is printed first in the UPS. See attached screanshot where upper view is Aqua print out and lower is the test configuration. this is also relevant for products with larger number of cores. 

4. create an ilas final file that includes for each unit 1 rows, and the data of the Vmin limiter per domain and test corner, and core number. at columns. meaning for test freq and domain according to the VminFwCfg find the max Vmin result that set the vmin for the unit-domain-freq-core, and then sumarrize in the columns the Vmin and the Vmin setter test instance for example "XSA_HUB_VMIN_K_F2XSN_X_VCCSA_F2_X_DISP" & its DTS_MAX & its _lp of that unit-domain-freq-core

---

### Assistant

All 4 changes are deeply intertwined — rewriting the script as a whole is cleaner than patching. Here's what I'm building:

- **Point 1**: Column filter → `*_VMIN_*` (underscore-flanked)
- **Point 2/3**: `Domain` name from `vminFwCfg` (e.g. `CR0`, `CR1`) *is* the physical core identifier — no separate `CoreSlot` index needed; just map `vminValues[i]` → `cfgList[i].Domain`
- **Point 3 (reversal note)**: vminFwCfg lists cores highest-first (`CR1, CR0`) but since we use the domain name directly, the reversal is encoded in the domain name itself (no arithmetic needed)
- **Point 4**: Aggregate max-Vmin per `(VisualID, Domain, FreqGHz)`, then pivot to 1 row per unit with 4 columns per combo: `_Vmin`, `_Setter`, `_MaxDTS_C`, `_LP`

---

## User — Message 10

i did not understand Point 3 can you explain in differnt word/ give numeric example?

---

### Assistant

**The reversal issue — numeric example:**

Imagine a 2-core product. AQUA's `vminFwCfg` column for one test prints:

```
CR1@F7:1:5.000_CR0@F7:1:5.000
```

And the paired Vmin column prints:

```
1.150_1.170
```

So positionally: slot 0 = `CR1` = 1.150 V, slot 1 = `CR0` = 1.170 V.

The UPS token `UPSVFPASSFLOWPU5_RCS_CR_5.000_1` then reports it as:
```
Core0=1.170  Core1=1.150
```
i.e. **CR0 appears first in UPS**, which is slot 1 in AQUA — the order is flipped.

---

**Why the script handles this automatically without any arithmetic:**

The script never uses slot index (0, 1, 2…) as the identifier. It reads the *domain name* (`CR0`, `CR1`) directly from `vminFwCfg` and uses that as the column key:

| vminFwCfg slot | Domain name | Vmin | Script column |
|---|---|---|---|
| slot 0 | CR1 | 1.150 | `CR1_F5_000_Vmin` |
| slot 1 | CR0 | 1.170 | `CR0_F5_000_Vmin` |

So in the summary CSV you get `CR0_F5_000_Vmin = 1.170` and `CR1_F5_000_Vmin = 1.150` — which matches UPS's Core0 = 1.170. **The domain name encodes the identity; the reversal is transparent.**

---

## User — Message 11

great. I understand. now continue with the code building and validation. you can excute for example on "Y6220110"

---

### Assistant

Let me check the current file state first, then validate syntax and run.

---

### Assistant

Script looks good. Parser-validate, then pull ILAS data for lot Y6220110:

---

### Assistant

Good. Now launch the AQUA ILAS pull for lot Y6220110 — this will take several minutes while AQUA prepares data on the server:

---

### Assistant

AQUA is running — those blank lines are normal while it prepares data on the server. Polling for progress:

---

### Assistant

AQUA pull is in progress (blank lines = server processing). I'll check again in a moment — this typically takes 5–15 minutes.

---

### Assistant

Still processing on the AQUA server. I'll keep polling:

---

### Assistant

Still waiting on AQUA. This is normal for the ILAS query — it's a heavier pull than the weekly Vmin report. I'll continue polling — you don't need to do anything.

---

### Assistant

AQUA has started — server is `HASAPP3301.ger.corp.intel.com` and the report is queued. Now waiting for data transfer to complete.

---

### Assistant

The script's `Wait-ForFileReady` polling loop is now active. It will check every 10 seconds until the file appears and stabilises.

---

### Assistant

"Ready. Writing results" — AQUA has finished preparing data and is writing the file now.

---

### Assistant

AQUA finished writing — now the `Wait-ForFileReady` polling loop is waiting for the file to stabilise (size unchanging for 2 consecutive checks). Nearly there.

---

## User — Message 12

Continue: "Continue to iterate?"

---

### Assistant

I’m checking from a separate command whether the run already produced files (it may be done but quiet during CSV processing).

---

## User — Message 13

[Terminal b05ce152-897d-4a1d-80a1-f3a95cade96c notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -LotsOverride "Y6220110" -Verbose
Pulling ILAS VMIN_DTS from AQUA...
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_raw_20260602_152427.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_raw_20260602_152427.csv
Done.

Waiting for AQUA output file to be ready...
AQUA pull complete: \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_raw_20260602_152427.csv
Loaded 964810 rows from ILAS file.
Found 0 _VMIN_ test columns.
No _VMIN_ base columns found in ILAS data.
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1:291 char:44
+ ... t.Count -eq 0) { throw "No _VMIN_ base columns found in ILAS data." }
+                      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (No _VMIN_ base ...d in ILAS d 
   ata.:String) [], RuntimeException
    + FullyQualifiedErrorId : No _VMIN_ base columns found in ILAS data.

---

### Assistant

Thanks, this failure is clear: ILAS output for this query is not in the “wide columns per test” layout. I’m going to adapt the parser to also support the “stacked by test name” format, then re-run validation on Y6220110.

---

## User — Message 14

[Terminal 98a4b7ce-5eb4-48e0-940c-00157b53b846 notification: command completed with exit code 0. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { 'PARSER_OK' } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize | Out-String }
PARSER_OK
PS C:\Projects\NVL\.docs> Set-Content -LiteralPath "C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1" -Encoding UTF8 -Value @'
>> param(
>>     [string]$AquaExe = "\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe",
>>     [string]$AquaServer = "GER",
>>     [string]$IlasReportPath = "sbelyy\ILAS\ILAS_VMIN_DTS",
>>     [string]$ProgramPattern = "NVLHM66*",
>>     [string]$Operations = "6248",
>>     [string]$OutputDirectory = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs",
>>     [string]$FunctionalBin = "100",
>>     [int]$LastNDaysTestEnd = 7,
>>     [int]$AquaMaxRows = 150000,
>>     [int]$AquaPullTimeoutSeconds = 900,
>>     [int]$AquaPullPollSeconds = 10,
>>     [string]$RawInputFile = "",
>>     [string]$LotsOverride = ""
>> )
>> 
>> Set-StrictMode -Version Latest
>> $ErrorActionPreference = "Stop"
>> 
>> # ---------------------------------------------------------------------------
>> # Helpers
>> # ---------------------------------------------------------------------------
>> 
>> function Get-SafeFileNamePart {
>>     param([string]$Value)
>>     $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
>>     $safe = $Value
>>     foreach ($c in $invalidChars) { $safe = $safe.Replace($c, "_") }
>>     return ($safe -replace "\s+", "_").Trim("_")
>> }
>> 
>> function Get-IsoWeekYear {
>>     param([datetime]$Date)
>>     $isoWeekType = [type]::GetType("System.Globalization.ISOWeek")
>>     if ($isoWeekType) {
>>         return [pscustomobject]@{
>>             Week = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
>>             Year = [System.Globalization.ISOWeek]::GetYear($Date)
>>         }
>>     }
>>     $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
>>     $dateForWeek = $Date
>>     if ($Date.DayOfWeek -in @([System.DayOfWeek]::Monday, [System.DayOfWeek]::Tuesday, [System.DayOfWeek]::Wednesday)) {
>>         $dateForWeek = $Date.AddDays(3)
>>     }
>>     return [pscustomobject]@{
>>         Week = $cal.GetWeekOfYear($dateForWeek, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
>>         Year = $dateForWeek.Year
>>     }
>> }
>> 
>> function Assert-NonEmptyFile {
>>     param([string]$Path, [string]$Label)
>>     if (-not (Test-Path -LiteralPath $Path)) { throw "$Label was not created: $Path" }
>>     if ((Get-Item -LiteralPath $Path).Length -le 0) { throw "$Label is empty: $Path" }
>> }
>> 
>> function Wait-ForFileReady {
>>     param([string]$Path, [int]$TimeoutSeconds, [int]$PollSeconds, [int]$StableChecks = 2)
>>     $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
>>     $lastLength = -1
>>     $stableCount = 0
>>     while ((Get-Date) -lt $deadline) {
>>         if (Test-Path -LiteralPath $Path) {
>>             $currentLength = (Get-Item -LiteralPath $Path).Length
>>             if ($currentLength -gt 0 -and $currentLength -eq $lastLength) {
>>                 $stableCount++
>>                 if ($stableCount -ge $StableChecks) { return $true }
>>             }
>>             else {
>>                 $stableCount = 0
>>                 $lastLength = $currentLength
>>             }
>>         }
>>         Start-Sleep -Seconds $PollSeconds
>>     }
>>     return $false
>> }
>> 
>> # ---------------------------------------------------------------------------
>> # Parse-VminFwCfg
>> # Input  : "CR1@F7:1:5.000_CR0@F7:1:5.000"
>> # Output : ordered array of [pscustomobject]@{ Domain; FreqGHz } matching the
>> #          position of each Vmin value in the Vmin string.
>> #
>> # NOTE on physical-core order:
>> #   vminFwCfg lists cores from highest to lowest (e.g. CR1 before CR0).
>> #   Vmin values are in the same positional order as vminFwCfg entries.
>> #   UPS/UPSVFPASSFLOW lists Core 0 first (reversed vs. AQUA printout).
>> #   Because we key on the Domain NAME (CR0, CR1, ...) rather than a slot index,
>> #   the reversal is automatically encoded in the column name - no arithmetic needed.
>> # ---------------------------------------------------------------------------
>> function Parse-VminFwCfg {
>>     param([string]$CfgValue)
>>     $result = @()
>>     if ([string]::IsNullOrWhiteSpace($CfgValue)) { return $result }
>>     foreach ($entry in ($CfgValue -split "_")) {
>>         if ([string]::IsNullOrWhiteSpace($entry)) { continue }
>>         $atParts = $entry -split "@", 2
>>         $domain  = $atParts[0]
>>         $freqGHz = ""
>>         if ($atParts.Count -gt 1) {
>>             $colonParts = $atParts[1] -split ":"
>>             $freqGHz    = $colonParts[-1]
>>         }
>>         $result += [pscustomobject]@{ Domain = $domain; FreqGHz = $freqGHz }
>>     }
>>     return $result
>> }
>> 
>> # ---------------------------------------------------------------------------
>> # Get-MaxDts
>> # Input  : "AON:75.00|CCF0S0:79.00|C0S6:97.00|..."
>> # Output : maximum temperature value (double), or $null if none parseable.
>> # ---------------------------------------------------------------------------
>> function Get-MaxDts {
>>     param([string]$DtsValue)
>>     if ([string]::IsNullOrWhiteSpace($DtsValue)) { return $null }
>>     $maxTemp = $null
>>     foreach ($sensor in ($DtsValue -split "\|")) {
>>         $parts = $sensor.Trim() -split ":", 2
>>         if ($parts.Count -lt 2) { continue }
>>         $tempVal = 0.0
>>         if ([double]::TryParse($parts[1].Trim(),
>>                 [System.Globalization.NumberStyles]::Any,
>>                 [System.Globalization.CultureInfo]::InvariantCulture,
>>                 [ref]$tempVal)) {
>>             if ($null -eq $maxTemp -or $tempVal -gt $maxTemp) { $maxTemp = $tempVal }
>>         }
>>     }
>>     return $maxTemp
>> }
>> 
>> # ---------------------------------------------------------------------------
>> # Expand-IlasRow
>> # Expands one AQUA row (one unit) into flat detail records.
>> # One record per (test instance, domain/core slot in vminFwCfg).
>> #
>> # Rules:
>> #   - Only columns whose name contains "_VMIN_" are considered test instances.
>> #   - Columns ending in _lp, _DTS, _vminFwCfg are suffix companions, not tests.
>> #   - Slots with Vmin <= 0 or unparseable are skipped (untested/masked cores).
>> #   - Domain name (from vminFwCfg, e.g. CR0, CR1, VCCSA) identifies the core;
>> #     no separate numeric CoreSlot index is stored in output.
>> # ---------------------------------------------------------------------------
>> function Expand-IlasRow {
>>     param(
>>         [object]  $Row,
>>         [string]  $VisualId,
>>         [string[]]$BaseTestColumns,
>>         [string[]]$AllColumns
>>     )
>> 
>>     $records = New-Object System.Collections.Generic.List[object]
>> 
>>     foreach ($baseCol in $BaseTestColumns) {
>>         $vminRaw = [string]$Row.$baseCol
>>         if ([string]::IsNullOrWhiteSpace($vminRaw)) { continue }
>> 
>>         $lpCol  = $baseCol + "_lp"
>>         $cfgCol = $baseCol + "_vminFwCfg"
>>         $dtsCol = $baseCol + "_DTS"
>> 
>>         $limiterPattern = if ($lpCol  -in $AllColumns) { [string]$Row.$lpCol  } else { "" }
>>         $cfgRaw         = if ($cfgCol -in $AllColumns) { [string]$Row.$cfgCol } else { "" }
>>         $dtsRaw         = if ($dtsCol -in $AllColumns) { [string]$Row.$dtsCol } else { "" }
>> 
>>         $maxDts  = Get-MaxDts    -DtsValue $dtsRaw
>>         $cfgList = Parse-VminFwCfg -CfgValue $cfgRaw
>> 
>>         $vminValues = $vminRaw -split "_"
>> 
>>         for ($idx = 0; $idx -lt $vminValues.Count; $idx++) {
>>             $vminStr = $vminValues[$idx].Trim()
>>             $vminVal = 0.0
>>             if (-not [double]::TryParse($vminStr,
>>                     [System.Globalization.NumberStyles]::Any,
>>                     [System.Globalization.CultureInfo]::InvariantCulture,
>>                     [ref]$vminVal)) { continue }
>>             if ($vminVal -le 0) { continue }
>> 
>>             # Domain name IS the physical core identifier (CR0, CR1, VCCSA, etc.).
>>             # vminFwCfg order may differ from UPS order; domain name encodes that correctly.
>>             $domain  = if ($idx -lt $cfgList.Count) { $cfgList[$idx].Domain  } else { "Slot$idx" }
>>             $freqGHz = if ($idx -lt $cfgList.Count) { $cfgList[$idx].FreqGHz } else { "" }
>> 
>>             $records.Add([pscustomobject]@{
>>                 VisualID       = $VisualId
>>                 TestName       = $baseCol
>>                 Domain         = $domain
>>                 FreqGHz        = $freqGHz
>>                 Vmin           = $vminVal
>>                 LimiterPattern = $limiterPattern
>>                 MaxDTS_C       = if ($null -ne $maxDts) { $maxDts } else { "" }
>>             })
>>         }
>>     }
>> 
>>     # Return items individually into the pipeline; caller wraps with @()
>>     return $records
>> }
>> 
>> # ---------------------------------------------------------------------------
>> # Main
>> # ---------------------------------------------------------------------------
>> $runStart           = Get-Date
>> $tempRawFile        = ""
>> $pulledRawInThisRun = $false
>> 
>> try {
>>     if (-not (Test-Path -LiteralPath $OutputDirectory)) {
>>         New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
>>     }
>> 
>>     $runStamp      = Get-Date -Format "yyyyMMdd_HHmmss"
>>     $tempRawFile   = Join-Path $OutputDirectory ("_ilas_raw_{0}.csv" -f $runStamp)
>>     $sourceRawFile = ""
>> 
>>     $lotArgs = if ([string]::IsNullOrWhiteSpace($LotsOverride)) {
>>         @("-lotsfromfs")
>>     }
>>     else {
>>         @("-lots", $LotsOverride)
>>     }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 1 - Obtain raw ILAS CSV (pull from AQUA or reuse existing)
>>     # ------------------------------------------------------------------
>>     if (-not [string]::IsNullOrWhiteSpace($RawInputFile)) {
>>         if (-not (Test-Path -LiteralPath $RawInputFile)) {
>>             throw "Provided RawInputFile does not exist: $RawInputFile"
>>         }
>>         Write-Host "Using existing ILAS raw file: $RawInputFile"
>>         $sourceRawFile = $RawInputFile
>>     }
>>     else {
>>         if (-not (Test-Path -LiteralPath $AquaExe)) {
>>             throw "Aqua executable not found: $AquaExe"
>>         }
>> 
>>         Write-Host "Pulling ILAS VMIN_DTS from AQUA..."
>>         & $AquaExe `
>>             -aquaserver $AquaServer `
>>             -reportpath $IlasReportPath `
>>             -outputfilename $tempRawFile `
>>             -programNames $ProgramPattern `
>>             -lastNDaysTestEnd $LastNDaysTestEnd `
>>             -operations $Operations `
>>             -dataSampling $AquaMaxRows `
>>             $lotArgs `
>>             -UnitFunctionalBin $FunctionalBin
>> 
>>         Write-Host "Waiting for AQUA output file to be ready..."
>>         $isReady = Wait-ForFileReady -Path $tempRawFile `
>>             -TimeoutSeconds $AquaPullTimeoutSeconds -PollSeconds $AquaPullPollSeconds
>>         if (-not $isReady) {
>>             throw "AQUA ILAS output was not ready within $AquaPullTimeoutSeconds seconds: $tempRawFile"
>>         }
>> 
>>         $sourceRawFile      = $tempRawFile
>>         $pulledRawInThisRun = $true
>>         Write-Host "AQUA pull complete: $sourceRawFile"
>>     }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 2 - Load raw CSV and detect columns
>>     # ------------------------------------------------------------------
>>     $rawRows = @(Import-Csv -LiteralPath $sourceRawFile)
>>     if ($rawRows.Count -eq 0) { throw "ILAS raw file is empty: $sourceRawFile" }
>>     Write-Host ("Loaded {0} rows from ILAS file." -f $rawRows.Count)
>> 
>>     $allColumns = $rawRows[0].PSObject.Properties.Name
>> 
>>     # VisualID column detection
>>     $visualIdColumn = @("Visual ID", "VISUAL_ID", "VisualId", "VISUALID", "VID") |
>>         Where-Object { $allColumns -contains $_ } | Select-Object -First 1
>>     if (-not $visualIdColumn) { throw "Could not find a Visual ID column in the ILAS output." }
>> 
>>     # Base VMIN test columns: name must contain "_VMIN_" (underscore-flanked).
>>     # Excludes companion-suffix columns (_lp, _DTS, _vminFwCfg).
>>     $baseTestColumnList = @(
>>         $allColumns | Where-Object {
>>             $_ -like "*_VMIN_*" -and
>>             $_ -notlike "*_lp"  -and
>>             $_ -notlike "*_DTS" -and
>>             $_ -notlike "*_vminFwCfg"
>>         }
>>     )
>> 
>>     Write-Host ("Found {0} _VMIN_ test columns." -f $baseTestColumnList.Count)
>>     if ($baseTestColumnList.Count -eq 0) { throw "No _VMIN_ base columns found in ILAS data." }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 3 - Expand each unit row into flat detail records
>>     # ------------------------------------------------------------------
>>     $allRecords = New-Object System.Collections.Generic.List[object]
>>     $unitCount  = 0
>> 
>>     foreach ($row in $rawRows) {
>>         $visualId = [string]$row.$visualIdColumn
>>         if ([string]::IsNullOrWhiteSpace($visualId)) { continue }
>> 
>>         $expanded = @(Expand-IlasRow -Row $row -VisualId $visualId `
>>             -BaseTestColumns $baseTestColumnList -AllColumns $allColumns)
>> 
>>         foreach ($rec in $expanded) { $allRecords.Add($rec) }
>>         $unitCount++
>>     }
>> 
>>     Write-Host ("Expanded {0} units into {1} detail records." -f $unitCount, $allRecords.Count)
>>     if ($allRecords.Count -eq 0) { throw "No detail records produced. Check _VMIN_ column values are non-zero." }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 4 - Aggregate: for each (VisualID, Domain, FreqGHz) keep the
>>     #          record with the MAX Vmin. That record's TestName is the
>>     #          "Vmin setter" for that unit-domain-frequency combination.
>>     # ------------------------------------------------------------------
>>     $maxVminLookup = @{}   # key = "VisualID||Domain||FreqGHz" ; value = detail record
>> 
>>     foreach ($rec in $allRecords) {
>>         $key = "{0}||{1}||{2}" -f $rec.VisualID, $rec.Domain, $rec.FreqGHz
>>         if (-not $maxVminLookup.ContainsKey($key) -or $rec.Vmin -gt $maxVminLookup[$key].Vmin) {
>>             $maxVminLookup[$key] = $rec
>>         }
>>     }
>> 
>>     # Collect unique sorted VisualIDs and unique sorted (Domain||FreqGHz) combos
>>     $uniqueVisualIds = New-Object 'System.Collections.Generic.SortedSet[string]'
>>     $uniqueCombos    = New-Object 'System.Collections.Generic.SortedSet[string]'
>> 
>>     foreach ($key in $maxVminLookup.Keys) {
>>         $parts = $key -split "\|\|", 3
>>         [void]$uniqueVisualIds.Add($parts[0])
>>         [void]$uniqueCombos.Add("{0}||{1}" -f $parts[1], $parts[2])
>>     }
>> 
>>     Write-Host ("Aggregated: {0} units x {1} domain/freq combinations." -f `
>>         $uniqueVisualIds.Count, $uniqueCombos.Count)
>> 
>>     # ------------------------------------------------------------------
>>     # Step 5 - Pivot to wide format: one row per VisualID
>>     #
>>     # Column layout per (Domain, FreqGHz) combo (dots replaced with underscores):
>>     #   {Domain}_F{FreqGHz}_Vmin      - max Vmin that sets this domain/freq for this unit
>>     #   {Domain}_F{FreqGHz}_Setter    - test instance name that produced that max Vmin
>>     #   {Domain}_F{FreqGHz}_MaxDTS_C  - max die temperature during the setter test
>>     #   {Domain}_F{FreqGHz}_LP        - limiter pattern (_lp) of the setter test
>>     #
>>     # Example column for CR0 at 5.000 GHz: CR0_F5_000_Vmin
>>     # ------------------------------------------------------------------
>>     $finalRows = New-Object System.Collections.Generic.List[object]
>> 
>>     foreach ($vid in $uniqueVisualIds) {
>>         $rowData = [ordered]@{ VisualID = $vid }
>> 
>>         foreach ($combo in $uniqueCombos) {
>>             $comboParts = $combo -split "\|\|", 2
>>             $domain     = $comboParts[0]
>>             $freqGHz    = $comboParts[1]
>>             $lookupKey  = "{0}||{1}||{2}" -f $vid, $domain, $freqGHz
>>             $colPrefix  = "{0}_F{1}" -f $domain, ($freqGHz -replace "\.", "_")
>> 
>>             if ($maxVminLookup.ContainsKey($lookupKey)) {
>>                 $rec = $maxVminLookup[$lookupKey]
>>                 $rowData["${colPrefix}_Vmin"]     = $rec.Vmin
>>                 $rowData["${colPrefix}_Setter"]   = $rec.TestName
>>                 $rowData["${colPrefix}_MaxDTS_C"] = $rec.MaxDTS_C
>>                 $rowData["${colPrefix}_LP"]       = $rec.LimiterPattern
>>             }
>>             else {
>>                 $rowData["${colPrefix}_Vmin"]     = ""
>>                 $rowData["${colPrefix}_Setter"]   = ""
>>                 $rowData["${colPrefix}_MaxDTS_C"] = ""
>>                 $rowData["${colPrefix}_LP"]       = ""
>>             }
>>         }
>> 
>>         $finalRows.Add([pscustomobject]$rowData)
>>     }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 6 - Write output CSVs
>>     # ------------------------------------------------------------------
>>     $isoInfo = Get-IsoWeekYear -Date (Get-Date)
>>     $suffix  = "WW{0:D2}_{1}" -f $isoInfo.Week, $isoInfo.Year
>> 
>>     if (-not [string]::IsNullOrWhiteSpace($LotsOverride)) {
>>         $safeLot = ($LotsOverride -replace '[^A-Za-z0-9]', '_')
>>         $suffix  = "{0}_{1}" -f $safeLot, $suffix
>>     }
>> 
>>     $detailCsv = Join-Path $OutputDirectory ("ILAS_Vmin_Detail_{0}.csv"  -f $suffix)
>>     $finalCsv  = Join-Path $OutputDirectory ("ILAS_Vmin_Summary_{0}.csv" -f $suffix)
>> 
>>     $allRecords | Export-Csv -LiteralPath $detailCsv -NoTypeInformation
>>     $finalRows  | Export-Csv -LiteralPath $finalCsv  -NoTypeInformation
>> 
>>     Assert-NonEmptyFile -Path $detailCsv -Label "ILAS Vmin detail CSV"
>>     Assert-NonEmptyFile -Path $finalCsv  -Label "ILAS Vmin summary CSV"
>> 
>>     $elapsed = [int]((Get-Date) - $runStart).TotalSeconds
>> 
>>     Write-Host ""
>>     Write-Host ("Detail CSV  : {0}" -f $detailCsv)
>>     Write-Host ("Summary CSV : {0}" -f $finalCsv)
>>     Write-Host ("Units       : {0}" -f $uniqueVisualIds.Count)
>>     Write-Host ("Domain/Freq : {0} combinations" -f $uniqueCombos.Count)
>>     Write-Host ("Detail rows : {0}" -f $allRecords.Count)
>>     Write-Host ("Elapsed     : {0}s" -f $elapsed)
>> }
>> finally {
>>     if ($pulledRawInThisRun -and $tempRawFile -ne "" -and (Test-Path -LiteralPath $tempRawFile)) {
>>         Remove-Item -LiteralPath $tempRawFile -Force -ErrorAction SilentlyContinue
>>     }
>> }
>> '@
PS C:\Projects\NVL\.docs> Write-Host "File written"
File written
PS C:\Projects\NVL\.docs> Set-Location "C:\Projects\NVL\.docs"
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null
PS C:\Projects\NVL\.docs> [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1), [ref]$tokens, [ref]$errors) | Out-Null
PS C:\Projects\NVL\.docs> if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> Get-ChildItem "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs" -Filter "ILAS_Vmin_*Y6220110*" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,Length,LastWriteTime | Format-Table -AutoSize
PS C:\Projects\NVL\.docs> $p='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_raw_20260602_152427.csv'; if (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p | Select-Object FullName,Length,LastWriteTime | Format-List } else { 'RAW_NOT_FOUND' }
RAW_NOT_FOUND
PS C:\Projects\NVL\.docs> $aqua="\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe"; $out="C:\Projects\NVL\.docs\Scripts\_ilas_probe_$(Get-Date -Format yyyyMMdd_HHmmss).csv"; & $aqua -aquaserver GER -reportpath "sbelyy\ILAS\ILAS_VMIN_DTS" -outputfilename $out -programNames "NVLHM66*" -lastNDaysTestEnd 7 -operations 6248 -dataSampling 200 -lots Y6220110 -UnitFunctionalBin 100; Write-Host "OUT=$out"
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Done.

OUT=C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv

---

### Assistant

Great, the probe pull finished and we now have a sample file. I’ll inspect its real schema and patch the script to handle it.

---

### Assistant

I identified the schema mismatch: ILAS returns stacked rows (`TEST_NAME` + `TEST_RESULT`), not one-column-per-test. I’m patching the script now to support stacked parsing (including `_DTS`, `_VMINFWCFG`, `_LP`) and then I’ll re-run Y6220110 validation.

---

### Assistant

Using the probe file now to validate logic quickly. I’ll grab the completion output and then run full Y6220110 from AQUA.

---

## User — Message 15

[Terminal e04dddc6-6ebe-494e-be6a-e8c3fd212e28 notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> Get-ChildItem "C:\Projects\NVL\.docs\Scripts" -Filter "_ilas_probe_*.csv" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 3 FullName,Length,LastWriteTime | Format-Table -AutoSize
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_wC4rOGaDGtGdbht91ggdYtDs__vscode-1780385092207\content.txt" -Tail 80
>> 
>>         foreach ($combo in $uniqueCombos) {
>>             $comboParts = $combo -split "\|\|", 2
>>             $domain     = $comboParts[0]
>>             $freqGHz    = $comboParts[1]
>>             $lookupKey  = "{0}||{1}||{2}" -f $vid, $domain, $freqGHz
>>             $colPrefix  = "{0}_F{1}" -f $domain, ($freqGHz -replace "\.", "_")
>> 
>>             if ($maxVminLookup.ContainsKey($lookupKey)) {
>>                 $rec = $maxVminLookup[$lookupKey]
>>                 $rowData["${colPrefix}_Vmin"]     = $rec.Vmin
>>                 $rowData["${colPrefix}_Setter"]   = $rec.TestName
>>                 $rowData["${colPrefix}_MaxDTS_C"] = $rec.MaxDTS_C
>>                 $rowData["${colPrefix}_LP"]       = $rec.LimiterPattern
>>             }
>>             else {
>>                 $rowData["${colPrefix}_Vmin"]     = ""
>>                 $rowData["${colPrefix}_Setter"]   = ""
>>                 $rowData["${colPrefix}_MaxDTS_C"] = ""
>>                 $rowData["${colPrefix}_LP"]       = ""
>>             }
>>         }
>> 
>>         $finalRows.Add([pscustomobject]$rowData)
>>     }
>> 
>>     # ------------------------------------------------------------------
>>     # Step 6 - Write output CSVs
>>     # ------------------------------------------------------------------
>>     $isoInfo = Get-IsoWeekYear -Date (Get-Date)
>>     $suffix  = "WW{0:D2}_{1}" -f $isoInfo.Week, $isoInfo.Year
>> 
>>     if (-not [string]::IsNullOrWhiteSpace($LotsOverride)) {
>>         $safeLot = ($LotsOverride -replace '[^A-Za-z0-9]', '_')
>>         $suffix  = "{0}_{1}" -f $safeLot, $suffix
>>     }
>> 
>>     $detailCsv = Join-Path $OutputDirectory ("ILAS_Vmin_Detail_{0}.csv"  -f $suffix)
>>     $finalCsv  = Join-Path $OutputDirectory ("ILAS_Vmin_Summary_{0}.csv" -f $suffix)
>> 
>>     $allRecords | Export-Csv -LiteralPath $detailCsv -NoTypeInformation
>>     $finalRows  | Export-Csv -LiteralPath $finalCsv  -NoTypeInformation
>> 
>>     Assert-NonEmptyFile -Path $detailCsv -Label "ILAS Vmin detail CSV"
>>     Assert-NonEmptyFile -Path $finalCsv  -Label "ILAS Vmin summary CSV"
>> 
>>     $elapsed = [int]((Get-Date) - $runStart).TotalSeconds
>> 
>>     Write-Host ""
>>     Write-Host ("Detail CSV  : {0}" -f $detailCsv)
>>     Write-Host ("Summary CSV : {0}" -f $finalCsv)
>>     Write-Host ("Units       : {0}" -f $uniqueVisualIds.Count)
>>     Write-Host ("Domain/Freq : {0} combinations" -f $uniqueCombos.Count)
>>     Write-Host ("Detail rows : {0}" -f $allRecords.Count)
>>     Write-Host ("Elapsed     : {0}s" -f $elapsed)
>> }
>> finally {
>>     if ($pulledRawInThisRun -and $tempRawFile -ne "" -and (Test-Path -LiteralPath $tempRawFile)) {
>>         Remove-Item -LiteralPath $tempRawFile -Force -ErrorAction SilentlyContinue
>>     }
>> }
>> '@
PS C:\Projects\NVL\.docs> Write-Host "File written"
File written
PS C:\Projects\NVL\.docs> Set-Location "C:\Projects\NVL\.docs"
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null
PS C:\Projects\NVL\.docs> [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1), [ref]$tokens, [ref]$errors) | Out-Null
PS C:\Projects\NVL\.docs> if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> Get-ChildItem "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs" -Filter "ILAS_Vmin_*Y6220110*" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name,Length,LastWriteTime | Format-Table -AutoSize
PS C:\Projects\NVL\.docs> $p='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_raw_20260602_152427.csv'; if (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p | Select-Object FullName,Length,LastWriteTime | Format-List } else { 'RAW_NOT_FOUND' }
RAW_NOT_FOUND
PS C:\Projects\NVL\.docs> $aqua="\\ger.corp.intel.com\ec\proj\ha\stav\DIS_Downloads\AquaHbase\AquaCMDClient\Client\AquaCmdLine.exe"; $out="C:\Projects\NVL\.docs\Scripts\_ilas_probe_$(Get-Date -Format yyyyMMdd_HHmmss).csv"; & $aqua -aquaserver GER -reportpath "sbelyy\ILAS\ILAS_VMIN_DTS" -outputfilename $out -programNames "NVLHM66*" -lastNDaysTestEnd 7 -operations 6248 -dataSampling 200 -lots Y6220110 -UnitFunctionalBin 100; Write-Host "OUT=$out"
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> $f='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; $row=Import-Csv -LiteralPath $f | Select-Object -First 1; $row.PSObject.Properties.Name
VISUAL_ID
SUBSTRUCTURE_ID
SORT_LOT
SORT_WAFER
SORT_X
SORT_Y
LOTFROMFS
OPERGROUP
Lot
Program Name
FUNCTIONAL_BIN
INTERFACE_BIN
TEST_NAME
DISTINCTIVE_VALUE
CATEGORIZING_VALUE
TEST_RESULT_NUMERIC
TEST_RESULT
TEST_RESULT_ORDER_NUM
STRING_DISTINCTIVE_VALUE
PARAMETER_GROUP
PS C:\Projects\NVL\.docs> $f='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; Import-Csv -LiteralPath $f | Select-Object -First 8 | Format-List *


VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_E_ENDCPU_HITO_VCCIA
                           _X_X_L2_TAG_DTS
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : AON:94.50|CCF0S0:94.50|CCF0S1:94.50|CCF0S2:94.00|CCF
                           0S3:94.50|CCF0S4:94.50|CCF0S5:94.50|CCF0S6:94.00|CCF
                           0S7:93.00|CCF0S8:93.50|CCF0S9:95.00|CCF1S0:95.50|CCF
                           1S1:95.50|CCF1S2:96.00|CCF1S3:95.00|A0S0:97.00|A0S2:
                           97.50|A0S3:97.50|A0S4:98.00|A0S5:97.50|A0S6:97.00|A0
                           S7:95.50|A0S8:95.50|A0S9:97.00|A0S10:97.00|A0S11:96.
                           50|A0S12:96.50|A0S13:97.50|A0S14:97.00|A0S16:97.00|A
                           0S17:99.00|A0S18:97.50|A0S19:98.00|A0S20:98.00|A0S21
                           :98.00|A0S24:96.50|A0S25:94.50|A0S26:96.50|A0S27:96.
                           00|A0S28:95.00|A0S29:96.00|A1S0:97.50|A1S2:98.00|A1S
                           3:98.50|A1S4:98.50|A1S5:98.00|A1S6:97.50|A1S7:98.00|
                           A1S8:96.50|A1S9:97.50|A1S10:97.00|A1S11:97.50|A1S12:
                           97.00|A1S13:98.00|A1S14:97.50|A1S16:98.50|A1S17:98.5
                           0|A1S18:99.50|A1S19:99.50|A1S20:100.00|A1S21:99.00|A
                           1S24:96.50|A1S25:95.50|A1S26:96.00|A1S27:97.50|A1S28
                           :96.50|A1S29:97.00|C0S0:95.00|C0S1:95.50|C0S2:95.50|
                           C0S3:94.50|C0S4:95.50|C0S5:95.50|C0S6:95.00|C0S7:94.
                           50|C0S8:94.50|C0S9:95.00|C0S10:95.00|C0S11:95.50|C0S
                           12:95.50|C0S13:94.50|C0S14:94.00|C0S15:95.00|C1S0:94
                           .00|C1S1:94.00|C1S2:93.50|C1S3:93.50|C1S4:94.50|C1S5
                           :95.00|C1S6:94.00|C1S7:95.00|C1S8:94.50|C1S9:93.50|C
                           1S10:93.50|C1S11:94.00|C1S12:95.00|C1S13:93.50|C1S14
                           :93.50|C1S15:94.00|C2S0:95.50|C2S1:95.00|C2S2:95.00|
                           C2S3:95.00|C2S4:94.50|C2S5:95.50|C2S6:94.50|C2S7:95.
                           50|C2S8:95.50|C2S9:94.00|C2S10:94.50|C2S11:94.50|C2S
                           12:95.00|C2S13:95.50|C2S14:95.00|C2S15:95.00|C3S0:94
                           .50|C3S1:94.50|C3S2:94.00|C3S3:94.50|C3S4:94.50|C3S5
                           :94.50|C3S6:94.50|C3S7:95.00|C3S8:94.50|C3S9:94.00|C
                           3S10:95.50|C3S11:94.00|C3S12:95.00|C3S13:94.50|C3S14
                           :94.00|C3S15:94.50
TEST_RESULT_ORDER_NUM    : 19576
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_COMBINED
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0.450_0.450|0.450_0.450|0.800_0.800|1
TEST_RESULT_ORDER_NUM    : 17577
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_COMBINED_DTS
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : AON:90.50|CCF0S0:91.00|CCF0S1:90.00|CCF0S2:90.00|CCF
                           0S3:91.00|CCF0S4:91.00|CCF0S5:90.50|CCF0S6:90.00|CCF
                           0S7:89.50|CCF0S8:90.00|CCF0S9:91.00|CCF1S0:89.50|CCF
                           1S1:90.50|CCF1S2:90.00|CCF1S3:89.50|A0S0:91.50|A0S2:
                           92.50|A0S3:91.50|A0S4:92.00|A0S5:92.50|A0S6:92.00|A0
                           S7:91.00|A0S8:91.00|A0S9:91.50|A0S10:92.00|A0S11:91.
                           50|A0S12:91.50|A0S13:92.00|A0S14:92.00|A0S16:91.50|A
                           0S17:92.50|A0S18:92.00|A0S19:92.50|A0S20:92.00|A0S21
                           :92.50|A0S24:92.00|A0S25:91.00|A0S26:92.50|A0S27:91.
                           00|A0S28:90.50|A0S29:91.50|A1S0:90.50|A1S2:90.50|A1S
                           3:91.00|A1S4:91.50|A1S5:91.00|A1S6:91.00|A1S7:91.00|
                           A1S8:90.00|A1S9:91.00|A1S10:91.00|A1S11:91.00|A1S12:
                           90.00|A1S13:91.00|A1S14:91.00|A1S16:91.50|A1S17:90.5
                           0|A1S18:91.50|A1S19:92.00|A1S20:92.00|A1S21:92.00|A1
                           S24:90.50|A1S25:90.50|A1S26:90.50|A1S27:91.50|A1S28:
                           91.50|A1S29:91.00|C0S0:89.50|C0S1:91.00|C0S2:90.00|C
                           0S3:90.50|C0S4:91.00|C0S5:91.50|C0S6:90.50|C0S7:91.0
                           0|C0S8:91.00|C0S9:90.50|C0S10:90.00|C0S11:91.50|C0S1
                           2:91.00|C0S13:90.00|C0S14:91.00|C0S15:90.00|C1S0:90.
                           50|C1S1:90.00|C1S2:90.00|C1S3:90.00|C1S4:90.50|C1S5:
                           91.50|C1S6:90.00|C1S7:91.00|C1S8:90.50|C1S9:90.00|C1
                           S10:90.00|C1S11:90.50|C1S12:91.00|C1S13:90.00|C1S14:
                           89.00|C1S15:90.50|C2S0:92.00|C2S1:91.50|C2S2:91.00|C
                           2S3:91.00|C2S4:91.00|C2S5:91.50|C2S6:91.00|C2S7:92.0
                           0|C2S8:90.50|C2S9:90.50|C2S10:90.50|C2S11:90.50|C2S1
                           2:91.00|C2S13:92.00|C2S14:91.00|C2S15:91.50|C3S0:90.
                           50|C3S1:90.00|C3S2:90.00|C3S3:90.50|C3S4:90.50|C3S5:
                           90.50|C3S6:90.50|C3S7:90.50|C3S8:90.50|C3S9:90.00|C3
                           S10:91.00|C3S11:89.50|C3S12:91.00|C3S13:90.50|C3S14:
                           89.50|C3S15:90.50
TEST_RESULT_ORDER_NUM    : 17576
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_COMBINED_IT
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0_0
TEST_RESULT_ORDER_NUM    : 17578
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_COMBINED_VMINFWCFG
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : AT1@F1:1:1.200_AT0@F1:1:1.200
TEST_RESULT_ORDER_NUM    : 17579
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0.450_0.450|0.450_0.450|0.800_0.800|1
TEST_RESULT_ORDER_NUM    : 17571
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_DTS
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : AON:94.00|CCF0S0:94.00|CCF0S1:93.00|CCF0S2:93.00|CCF
                           0S3:94.00|CCF0S4:93.50|CCF0S5:93.00|CCF0S6:93.00|CCF
                           0S7:92.00|CCF0S8:93.00|CCF0S9:93.50|CCF1S0:93.50|CCF
                           1S1:94.50|CCF1S2:94.00|CCF1S3:94.00|A0S0:95.00|A0S2:
                           95.50|A0S3:94.50|A0S4:95.00|A0S5:95.50|A0S6:95.00|A0
                           S7:94.00|A0S8:94.00|A0S9:94.50|A0S10:95.00|A0S11:94.
                           50|A0S12:95.00|A0S13:95.50|A0S14:95.00|A0S16:95.00|A
                           0S17:95.50|A0S18:95.00|A0S19:95.50|A0S20:94.50|A0S21
                           :96.00|A0S24:94.50|A0S25:94.00|A0S26:95.00|A0S27:94.
                           50|A0S28:93.50|A0S29:94.50|A1S0:94.50|A1S2:94.50|A1S
                           3:95.00|A1S4:95.50|A1S5:95.00|A1S6:94.50|A1S7:95.50|
                           A1S8:94.50|A1S9:94.50|A1S10:94.50|A1S11:95.00|A1S12:
                           94.00|A1S13:95.50|A1S14:95.00|A1S16:95.00|A1S17:95.0
                           0|A1S18:96.00|A1S19:96.00|A1S20:96.00|A1S21:96.00|A1
                           S24:94.00|A1S25:94.50|A1S26:94.50|A1S27:95.50|A1S28:
                           95.00|A1S29:95.50|C0S0:94.50|C0S1:95.00|C0S2:95.00|C
                           0S3:94.50|C0S4:95.00|C0S5:95.00|C0S6:95.00|C0S7:94.0
                           0|C0S8:94.00|C0S9:95.00|C0S10:94.50|C0S11:95.50|C0S1
                           2:95.00|C0S13:94.00|C0S14:94.00|C0S15:95.00|C1S0:93.
                           50|C1S1:93.50|C1S2:93.00|C1S3:93.00|C1S4:94.00|C1S5:
                           94.50|C1S6:93.50|C1S7:94.00|C1S8:94.00|C1S9:93.00|C1
                           S10:93.50|C1S11:93.50|C1S12:94.50|C1S13:93.00|C1S14:
                           92.50|C1S15:93.50|C2S0:95.00|C2S1:94.50|C2S2:94.50|C
                           2S3:94.00|C2S4:94.00|C2S5:94.50|C2S6:94.00|C2S7:95.0
                           0|C2S8:95.00|C2S9:93.50|C2S10:94.00|C2S11:94.00|C2S1
                           2:94.00|C2S13:95.00|C2S14:94.50|C2S15:94.50|C3S0:93.
                           50|C3S1:93.50|C3S2:93.50|C3S3:94.00|C3S4:94.00|C3S5:
                           94.00|C3S6:93.50|C3S7:94.00|C3S8:94.00|C3S9:93.50|C3
                           S10:94.50|C3S11:93.00|C3S12:94.50|C3S13:93.50|C3S14:
                           93.00|C3S15:93.50
TEST_RESULT_ORDER_NUM    : 17570
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_IT
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0_0
TEST_RESULT_ORDER_NUM    : 17572
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING



PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110"
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
The property 'Count' cannot be found on this object. Verify that the property 
exists.
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1:233 char:24
+         for ($idx = 0; $idx -lt $vminValues.Count; $idx++) {
+                        ~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (:) [], ParentContainsErrorRecordE 
   xception
    + FullyQualifiedErrorId : PropertyNotFoundStrict

---

### Assistant

Found the strict-mode bug: when only one core value exists, PowerShell treats it as scalar and `.Count` fails. I’m patching that now (`@(...)` wrapping), then re-running validation.

---

## User — Message 16

[Terminal df1eae45-4bd6-4e5c-98e0-37cee36562b6 notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_8JeZjfSh3yrjEk87hRblF1Em__vscode-1780385092216\content.txt" -Tail 80

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_DTS
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : AON:94.00|CCF0S0:94.00|CCF0S1:93.00|CCF0S2:93.00|CCF
                           0S3:94.00|CCF0S4:93.50|CCF0S5:93.00|CCF0S6:93.00|CCF
                           0S7:92.00|CCF0S8:93.00|CCF0S9:93.50|CCF1S0:93.50|CCF
                           1S1:94.50|CCF1S2:94.00|CCF1S3:94.00|A0S0:95.00|A0S2:
                           95.50|A0S3:94.50|A0S4:95.00|A0S5:95.50|A0S6:95.00|A0
                           S7:94.00|A0S8:94.00|A0S9:94.50|A0S10:95.00|A0S11:94.
                           50|A0S12:95.00|A0S13:95.50|A0S14:95.00|A0S16:95.00|A
                           0S17:95.50|A0S18:95.00|A0S19:95.50|A0S20:94.50|A0S21
                           :96.00|A0S24:94.50|A0S25:94.00|A0S26:95.00|A0S27:94.
                           50|A0S28:93.50|A0S29:94.50|A1S0:94.50|A1S2:94.50|A1S
                           3:95.00|A1S4:95.50|A1S5:95.00|A1S6:94.50|A1S7:95.50|
                           A1S8:94.50|A1S9:94.50|A1S10:94.50|A1S11:95.00|A1S12:
                           94.00|A1S13:95.50|A1S14:95.00|A1S16:95.00|A1S17:95.0
                           0|A1S18:96.00|A1S19:96.00|A1S20:96.00|A1S21:96.00|A1
                           S24:94.00|A1S25:94.50|A1S26:94.50|A1S27:95.50|A1S28:
                           95.00|A1S29:95.50|C0S0:94.50|C0S1:95.00|C0S2:95.00|C
                           0S3:94.50|C0S4:95.00|C0S5:95.00|C0S6:95.00|C0S7:94.0
                           0|C0S8:94.00|C0S9:95.00|C0S10:94.50|C0S11:95.50|C0S1
                           2:95.00|C0S13:94.00|C0S14:94.00|C0S15:95.00|C1S0:93.
                           50|C1S1:93.50|C1S2:93.00|C1S3:93.00|C1S4:94.00|C1S5:
                           94.50|C1S6:93.50|C1S7:94.00|C1S8:94.00|C1S9:93.00|C1
                           S10:93.50|C1S11:93.50|C1S12:94.50|C1S13:93.00|C1S14:
                           92.50|C1S15:93.50|C2S0:95.00|C2S1:94.50|C2S2:94.50|C
                           2S3:94.00|C2S4:94.00|C2S5:94.50|C2S6:94.00|C2S7:95.0
                           0|C2S8:95.00|C2S9:93.50|C2S10:94.00|C2S11:94.00|C2S1
                           2:94.00|C2S13:95.00|C2S14:94.50|C2S15:94.50|C3S0:93.
                           50|C3S1:93.50|C3S2:93.50|C3S3:94.00|C3S4:94.00|C3S5:
                           94.00|C3S6:93.50|C3S7:94.00|C3S8:94.00|C3S9:93.50|C3
                           S10:94.50|C3S11:93.00|C3S12:94.50|C3S13:93.50|C3S14:
                           93.00|C3S15:93.50
TEST_RESULT_ORDER_NUM    : 17570
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_IT
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0_0
TEST_RESULT_ORDER_NUM    : 17572
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING



PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110"
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_TBRQJzu7zw5KzjDLnxukwsRN__vscode-1780385092218\content.txt" -Tail 60
                           95.50|A0S3:94.50|A0S4:95.00|A0S5:95.50|A0S6:95.00|A0
                           S7:94.00|A0S8:94.00|A0S9:94.50|A0S10:95.00|A0S11:94.
                           50|A0S12:95.00|A0S13:95.50|A0S14:95.00|A0S16:95.00|A
                           0S17:95.50|A0S18:95.00|A0S19:95.50|A0S20:94.50|A0S21
                           :96.00|A0S24:94.50|A0S25:94.00|A0S26:95.00|A0S27:94.
                           50|A0S28:93.50|A0S29:94.50|A1S0:94.50|A1S2:94.50|A1S
                           3:95.00|A1S4:95.50|A1S5:95.00|A1S6:94.50|A1S7:95.50|
                           A1S8:94.50|A1S9:94.50|A1S10:94.50|A1S11:95.00|A1S12:
                           94.00|A1S13:95.50|A1S14:95.00|A1S16:95.00|A1S17:95.0
                           0|A1S18:96.00|A1S19:96.00|A1S20:96.00|A1S21:96.00|A1
                           S24:94.00|A1S25:94.50|A1S26:94.50|A1S27:95.50|A1S28:
                           95.00|A1S29:95.50|C0S0:94.50|C0S1:95.00|C0S2:95.00|C
                           0S3:94.50|C0S4:95.00|C0S5:95.00|C0S6:95.00|C0S7:94.0
                           0|C0S8:94.00|C0S9:95.00|C0S10:94.50|C0S11:95.50|C0S1
                           2:95.00|C0S13:94.00|C0S14:94.00|C0S15:95.00|C1S0:93.
                           50|C1S1:93.50|C1S2:93.00|C1S3:93.00|C1S4:94.00|C1S5:
                           94.50|C1S6:93.50|C1S7:94.00|C1S8:94.00|C1S9:93.00|C1
                           S10:93.50|C1S11:93.50|C1S12:94.50|C1S13:93.00|C1S14:
                           92.50|C1S15:93.50|C2S0:95.00|C2S1:94.50|C2S2:94.50|C
                           2S3:94.00|C2S4:94.00|C2S5:94.50|C2S6:94.00|C2S7:95.0
                           0|C2S8:95.00|C2S9:93.50|C2S10:94.00|C2S11:94.00|C2S1
                           2:94.00|C2S13:95.00|C2S14:94.50|C2S15:94.50|C3S0:93.
                           50|C3S1:93.50|C3S2:93.50|C3S3:94.00|C3S4:94.00|C3S5:
                           94.00|C3S6:93.50|C3S7:94.00|C3S8:94.00|C3S9:93.50|C3
                           S10:94.50|C3S11:93.00|C3S12:94.50|C3S13:93.50|C3S14:
                           93.00|C3S15:93.50
TEST_RESULT_ORDER_NUM    : 17570
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_IT
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0_0
TEST_RESULT_ORDER_NUM    : 17572
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING



PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110"
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
PS C:\Projects\NVL\.docs> Get-Content "C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_Oiw5IGC4OTaNDKvn22K6FBqc__vscode-1780385092220\content.txt" -Tail 50
                           S24:94.00|A1S25:94.50|A1S26:94.50|A1S27:95.50|A1S28:
                           95.00|A1S29:95.50|C0S0:94.50|C0S1:95.00|C0S2:95.00|C
                           0S3:94.50|C0S4:95.00|C0S5:95.00|C0S6:95.00|C0S7:94.0
                           0|C0S8:94.00|C0S9:95.00|C0S10:94.50|C0S11:95.50|C0S1
                           2:95.00|C0S13:94.00|C0S14:94.00|C0S15:95.00|C1S0:93.
                           50|C1S1:93.50|C1S2:93.00|C1S3:93.00|C1S4:94.00|C1S5:
                           94.50|C1S6:93.50|C1S7:94.00|C1S8:94.00|C1S9:93.00|C1
                           S10:93.50|C1S11:93.50|C1S12:94.50|C1S13:93.00|C1S14:
                           92.50|C1S15:93.50|C2S0:95.00|C2S1:94.50|C2S2:94.50|C
                           2S3:94.00|C2S4:94.00|C2S5:94.50|C2S6:94.00|C2S7:95.0
                           0|C2S8:95.00|C2S9:93.50|C2S10:94.00|C2S11:94.00|C2S1
                           2:94.00|C2S13:95.00|C2S14:94.50|C2S15:94.50|C3S0:93.
                           50|C3S1:93.50|C3S2:93.50|C3S3:94.00|C3S4:94.00|C3S5:
                           94.00|C3S6:93.50|C3S7:94.00|C3S8:94.00|C3S9:93.50|C3
                           S10:94.50|C3S11:93.00|C3S12:94.50|C3S13:93.50|C3S14:
                           93.00|C3S15:93.50
TEST_RESULT_ORDER_NUM    : 17570
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING

VISUAL_ID                : U6XH126700474
SUBSTRUCTURE_ID          : U1.U4
SORT_LOT                 : D513862
SORT_WAFER               : 798
SORT_X                   : -15
SORT_Y                   : 11
LOTFROMFS                : Y6220110
OPERGROUP                : 6248_CLASSHOT
Lot                      : Y6220110
Program Name             : NVLHM66A0H30M00S622
FUNCTIONAL_BIN           : 100
INTERFACE_BIN            : 1
TEST_NAME                : IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_
                           F1_1200_SSA_L2DATA_IT
DISTINCTIVE_VALUE        : 
CATEGORIZING_VALUE       : 
TEST_RESULT_NUMERIC      : 
TEST_RESULT              : 0_0
TEST_RESULT_ORDER_NUM    : 17572
STRING_DISTINCTIVE_VALUE : 
PARAMETER_GROUP          : STRING



PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110"
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
PS C:\Projects\NVL\.docs> $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1", [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -eq 0) { "PARSER_OK" } else { $errors | Select-Object Message, @{N='Line';E={$_.Extent.StartLineNumber}} | Format-Table -AutoSize }
PARSER_OK
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110"
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 23896 detail records.
Error formatting a string: Index (zero based) must be greater than or equal to 
zero and less than the size of the argument list..
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1:341 char:9
+         [void]$uniqueCombos.Add("{0}||{1}" -f $parts[1], $parts[2])
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: ({0}||{1}:String) [], ParentCo 
   ntainsErrorRecordException
    + FullyQualifiedErrorId : FormatError

---

### Assistant

Great progress: parser now builds `23896` detail records. One bug left in combo-key parsing when `FreqGHz` is blank; I’m fixing that and re-running immediately.

---

### Assistant

The full probe file run is taking too long to complete in this session, so I’m doing a deterministic fast validation on a subset of Y6220110 data to confirm end-to-end output generation now.

---

### Assistant

Subset validation is now successful end-to-end. I’ll start the full Y6220110 run from AQUA with the fixed parser so you get production-size output.

---

### Assistant

Implemented and validated major fixes in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1).

What was fixed:
1. Added support for actual ILAS stacked schema:
- Uses TEST_NAME + TEST_RESULT (instead of assuming one column per test instance).
- Handles companion rows by suffix:
- _DTS
- _VMINFWCFG
- _LP
- Ignores _IT metadata rows.

2. Enforced your Vmin-instance rule:
- Only rows/tests containing _VMIN_ are considered.

3. Kept domain/core identity from vminFwCfg:
- Uses domain names (CR0, CR1, etc.) directly as the core identity.

4. Aggregation and final output:
- Max Vmin per VisualID + Domain + FreqGHz.
- Summary is one row per unit with columns:
- _Vmin
- _Setter
- _MaxDTS_C
- _LP
- Detail CSV is still generated as intermediate/output traceability.

5. Fixed strict-mode/runtime issues found during validation:
- Scalar vs array Count issue.
- Key/formatting failure when FreqGHz is empty.

Validation status:
- Parser: PASS (PARSER_OK).
- End-to-end functional run on Y6220110 subset (20k rows): PASS.
- Produced:
- ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
- ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
- Stats from subset run:
- Loaded 20000 rows
- Built 1018 detail records
- Units: 2
- Domain/Freq combos: 54

Full run status:
- Full AQUA Y6220110 run is currently in progress in terminal (it can take several minutes for ILAS).  
- No action needed from you unless you want me to stop it.

If you want, next I can add a lightweight progress print every N rows during stacked parsing so long runs are visibly alive.

---

## User — Message 17

[Terminal bfafe207-c808-4f85-9a62-c51dcb7a1f6f notification: command completed with exit code 1. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -LotsOverride "Y6220110"
Pulling ILAS VMIN_DTS from AQUA...
Waiting for AQUA output file to be ready...
AQUA ILAS output was not ready within 900 seconds: 
\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly 
Runs\_ilas_raw_20260602_155624.csv
At C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1:292 char:30
+ ... $isReady) { throw "AQUA ILAS output was not ready within $AquaPullTim ...
+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (AQUA ILAS outpu...0602_155624 
   .csv:String) [], RuntimeException
    + FullyQualifiedErrorId : AQUA ILAS output was not ready within 900 second 
   s: \\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\_ilas_r  
  aw_20260602_155624.csv

---

### Assistant

The AQUA exe returns immediately after submitting the job (it's async server-side). The file is written by the server — for 150k rows that takes much longer than 900 seconds. I'll increase the default timeout to 1 hour.

---

## User — Message 18

few corrections: 
1. Aqua ILAS report has 47 Visual_ID where the final csv file include only 2 
2. The final report is stacked, meaning that every unit has a row per domain and freq. whereas I need the final output to be split so it will be easier to merge with the UPSVF vmin results. so each unit will have 1 row and all of the Vmin results depicted with the DTS LP Test instance as columns for the Domain-Freq-Core number 
3. most important issue there is an integrity issue the data is incorrecl for example for  U6XH126700474 SAC 1.4GHz Vmin is 0.57 set by ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X and the csv out put file has vmin of 0.821 set by IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC- validate code and dfinal results

---

### Assistant

Let me read the current script and examine the probe data to understand all three issues.

---

### Assistant

Let me examine the actual data for the problematic unit to understand the integrity issue:

---

### Assistant

Now let me look for the specific test the code is picking as the "setter" and examine its structure:

---

## User — Message 19

[Terminal b46a97e0-db3a-4641-9186-0de7e6d109b8 notification: command completed with exit code 0. The terminal has been cleaned up.]
Terminal output:


[... PREVIOUS OUTPUT TRUNCATED ...]

_HUB_HXX::ATSPEED_NONR_VMIN_K_F4XSN_X_VCCSA_F5_X_1001_DTS                         HUBAON_MX:80.50|HUBAON_TR:79.50|MEM1S0_MX:86.00|MEM1S0_TR:77.50|MEM1S1_MX:77.00|MEM1S1_TR:74.00|MEM1S2_MX:77.00|MEM1S2_TR:76.50|MEM1S3_MX:77.50|MEM1S3_TR:76.00|DIS1S4_MX:86.50|DIS1S4_TR:85.00|DIS1S5_MX:86.00|DI
                                                                                          S1S5_TR:77.50|DIS1S6_MX:75.50|DIS1S6_TR:74.00|DIS1S7_MX:76.00|DIS1S7_TR:76.50|MEM1S8_MX:77.50|MEM1S8_TR:76.00|VPU2S0_MX:79.50|VPU2S0_TR:79.50|VPU2S1_MX:79.00|VPU2S1_TR:78.00|VPU2S2_MX:80.50|VPU2S2_TR:79.00|VPU2
                                                                                          S3_MX:80.50|VPU2S3_TR:78.00|VPU2S4_MX:80.00|VPU2S4_TR:80.00|VPU2S5_MX:78.50|VPU2S5_TR:77.00|VPU2S6_MX:79.00|VPU2S6_TR:78.00|VPU2S7_MX:80.50|VPU2S7_TR:79.00|VPU2S8_MX:79.00|VPU2S8_TR:77.00|MED3S0_MX:78.50|MED3S0
                                                                                          _TR:79.50|MED3S1_MX:78.00|MED3S1_TR:78.50|MED3S2_MX:79.50|MED3S2_TR:80.00|MED3S3_MX:79.00|MED3S3_TR:81.00|MED3S4_MX:81.00|MED3S4_TR:81.00|IPU3S5_MX:78.50|IPU3S5_TR:78.50|IPU3S6_MX:77.00|IPU3S6_TR:77.00|IPU3S7_M
                                                                                          X:79.50|IPU3S7_TR:80.00|MED3S8_MX:79.00|MED3S8_TR:79.50|HUBA0S0_MX:77.50|HUBA0S0_TR:78.00|HUBA0S2_MX:78.00|HUBA0S2_TR:77.00|HUBA0S3_MX:77.00|HUBA0S3_TR:78.50|HUBA0S4_MX:78.00|HUBA0S4_TR:77.00|HUBA0S5_MX:78.50|H
                                                                                          UBA0S5_TR:77.50|HUBA0S6_MX:77.00|HUBA0S6_TR:78.00|HUBA0S7_MX:77.50|HUBA0S7_TR:76.00|HUBA0S8_MX:76.50|HUBA0S8_TR:76.50|HUBA0S9_MX:75.50|HUBA0S9_TR:75.50|HUBA0S10_MX:75.50|HUBA0S10_TR:76.00|HUBA0S11_MX:77.00|HUBA
                                                                                          0S11_TR:76.00|HUBA0S12_MX:77.00|HUBA0S12_TR:75.00|HUBA0S13_MX:77.00|HUBA0S13_TR:76.50|HUBA0S16_MX:77.00|HUBA0S16_TR:78.00|HUBA0S17_MX:78.00|HUBA0S17_TR:77.00|HUBA0S18_MX:77.50|HUBA0S18_TR:78.00|HUBA0S19_MX:78.0
                                                                                          0|HUBA0S19_TR:76.00|HUBA0S20_MX:77.00|HUBA0S20_TR:78.00|HUBA0S21_MX:77.50|HUBA0S21_TR:77.00|HUBA0S24_MX:78.50|HUBA0S24_TR:79.50|HUBA0S25_MX:79.50|HUBA0S25_TR:78.00|HUBA0S26_MX:79.00|HUBA0S26_TR:78.00|HUBA0S27_M
                                                                                          X:78.00|HUBA0S27_TR:78.50|HUBA0S28_MX:78.00|HUBA0S28_TR:79.00|HUBA0S29_MX:78.50|HUBA0S29_TR:78.00                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F4XSN_X_VCCSA_F5_X_1001_LP                          0092630^0092630                                                                                                                                                                                                   
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F4XSN_X_VCCSA_F5_X_1001_VMINFWCFG                   SAC0@F5:1:3.000_SAQ0@F5:1:4.000                                                                                                                                                                                   
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F1_X                                0.710|0.710|0.741|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F1_X_DTS                            HUBAON_MX:18.00|HUBAON_TR:18.00|MEM1S0_MX:19.50|MEM1S0_TR:18.50|MEM1S1_MX:18.50|MEM1S1_TR:18.00|MEM1S2_MX:17.50|MEM1S2_TR:20.00|MEM1S3_MX:19.00|MEM1S3_TR:19.50|DIS1S4_MX:19.50|DIS1S4_TR:18.50|DIS1S5_MX:18.50|DI
                                                                                          S1S5_TR:16.00|DIS1S6_MX:17.00|DIS1S6_TR:17.00|DIS1S7_MX:17.50|DIS1S7_TR:18.50|MEM1S8_MX:18.00|MEM1S8_TR:18.50|VPU2S0_MX:18.50|VPU2S0_TR:18.00|VPU2S1_MX:18.50|VPU2S1_TR:19.00|VPU2S2_MX:19.00|VPU2S2_TR:19.50|VPU2
                                                                                          S3_MX:19.00|VPU2S3_TR:18.50|VPU2S4_MX:18.50|VPU2S4_TR:18.50|VPU2S5_MX:17.00|VPU2S5_TR:17.00|VPU2S6_MX:17.50|VPU2S6_TR:15.50|VPU2S7_MX:17.50|VPU2S7_TR:18.50|VPU2S8_MX:19.00|VPU2S8_TR:17.00|MED3S0_MX:19.00|MED3S0
                                                                                          _TR:17.50|MED3S1_MX:18.50|MED3S1_TR:18.50|MED3S2_MX:18.50|MED3S2_TR:18.50|MED3S3_MX:19.50|MED3S3_TR:18.50|MED3S4_MX:19.00|MED3S4_TR:17.50|IPU3S5_MX:17.50|IPU3S5_TR:17.50|IPU3S6_MX:18.50|IPU3S6_TR:18.50|IPU3S7_M
                                                                                          X:17.50|IPU3S7_TR:18.50|MED3S8_MX:19.50|MED3S8_TR:17.00|HUBA0S0_MX:18.50|HUBA0S0_TR:19.00|HUBA0S2_MX:18.50|HUBA0S2_TR:19.50|HUBA0S3_MX:19.00|HUBA0S3_TR:18.50|HUBA0S4_MX:19.00|HUBA0S4_TR:18.00|HUBA0S5_MX:19.00|H
                                                                                          UBA0S5_TR:18.00|HUBA0S6_MX:17.50|HUBA0S6_TR:18.50|HUBA0S7_MX:17.50|HUBA0S7_TR:17.50|HUBA0S8_MX:16.00|HUBA0S8_TR:16.50|HUBA0S9_MX:17.50|HUBA0S9_TR:17.50|HUBA0S10_MX:18.00|HUBA0S10_TR:18.50|HUBA0S11_MX:17.50|HUBA
                                                                                          0S11_TR:18.00|HUBA0S12_MX:17.50|HUBA0S12_TR:18.00|HUBA0S13_MX:17.50|HUBA0S13_TR:17.50|HUBA0S16_MX:18.00|HUBA0S16_TR:17.00|HUBA0S17_MX:17.50|HUBA0S17_TR:20.00|HUBA0S18_MX:17.50|HUBA0S18_TR:19.50|HUBA0S19_MX:19.5
                                                                                          0|HUBA0S19_TR:18.50|HUBA0S20_MX:19.00|HUBA0S20_TR:19.50|HUBA0S21_MX:18.00|HUBA0S21_TR:17.50|HUBA0S24_MX:19.00|HUBA0S24_TR:18.00|HUBA0S25_MX:19.00|HUBA0S25_TR:20.00|HUBA0S26_MX:19.00|HUBA0S26_TR:19.50|HUBA0S27_M
                                                                                          X:19.50|HUBA0S27_TR:20.00|HUBA0S28_MX:19.00|HUBA0S28_TR:19.50|HUBA0S29_MX:19.50|HUBA0S29_TR:19.00                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F2_X                                0.880|0.880|0.911|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F2_X_DTS                            HUBAON_MX:18.00|HUBAON_TR:15.50|MEM1S0_MX:23.50|MEM1S0_TR:19.50|MEM1S1_MX:19.50|MEM1S1_TR:19.50|MEM1S2_MX:19.00|MEM1S2_TR:21.00|MEM1S3_MX:20.50|MEM1S3_TR:21.00|DIS1S4_MX:23.50|DIS1S4_TR:22.00|DIS1S5_MX:22.00|DI
                                                                                          S1S5_TR:18.50|DIS1S6_MX:18.50|DIS1S6_TR:17.00|DIS1S7_MX:17.50|DIS1S7_TR:20.00|MEM1S8_MX:19.00|MEM1S8_TR:19.50|VPU2S0_MX:18.50|VPU2S0_TR:18.00|VPU2S1_MX:18.50|VPU2S1_TR:18.00|VPU2S2_MX:17.50|VPU2S2_TR:19.50|VPU2
                                                                                          S3_MX:19.00|VPU2S3_TR:18.50|VPU2S4_MX:19.50|VPU2S4_TR:18.50|VPU2S5_MX:17.00|VPU2S5_TR:18.00|VPU2S6_MX:17.50|VPU2S6_TR:18.00|VPU2S7_MX:17.50|VPU2S7_TR:18.50|VPU2S8_MX:18.00|VPU2S8_TR:17.00|MED3S0_MX:19.00|MED3S0
                                                                                          _TR:18.50|MED3S1_MX:18.50|MED3S1_TR:18.50|MED3S2_MX:20.00|MED3S2_TR:18.50|MED3S3_MX:19.50|MED3S3_TR:18.50|MED3S4_MX:19.00|MED3S4_TR:19.00|IPU3S5_MX:19.00|IPU3S5_TR:17.50|IPU3S6_MX:18.50|IPU3S6_TR:18.50|IPU3S7_M
                                                                                          X:18.50|IPU3S7_TR:18.50|MED3S8_MX:19.50|MED3S8_TR:18.50|HUBA0S0_MX:18.50|HUBA0S0_TR:19.00|HUBA0S2_MX:18.50|HUBA0S2_TR:19.50|HUBA0S3_MX:19.00|HUBA0S3_TR:18.50|HUBA0S4_MX:20.00|HUBA0S4_TR:18.00|HUBA0S5_MX:20.00|H
                                                                                          UBA0S5_TR:18.00|HUBA0S6_MX:17.50|HUBA0S6_TR:18.50|HUBA0S7_MX:17.50|HUBA0S7_TR:17.50|HUBA0S8_MX:17.50|HUBA0S8_TR:18.00|HUBA0S9_MX:18.50|HUBA0S9_TR:19.50|HUBA0S10_MX:18.00|HUBA0S10_TR:17.50|HUBA0S11_MX:17.50|HUBA
                                                                                          0S11_TR:18.00|HUBA0S12_MX:17.50|HUBA0S12_TR:15.50|HUBA0S13_MX:17.50|HUBA0S13_TR:17.50|HUBA0S16_MX:18.00|HUBA0S16_TR:17.00|HUBA0S17_MX:16.00|HUBA0S17_TR:17.00|HUBA0S18_MX:16.00|HUBA0S18_TR:18.00|HUBA0S19_MX:18.0
                                                                                          0|HUBA0S19_TR:17.00|HUBA0S20_MX:19.00|HUBA0S20_TR:18.00|HUBA0S21_MX:18.00|HUBA0S21_TR:19.00|HUBA0S24_MX:18.00|HUBA0S24_TR:18.00|HUBA0S25_MX:19.00|HUBA0S25_TR:20.00|HUBA0S26_MX:19.00|HUBA0S26_TR:19.50|HUBA0S27_M
                                                                                          X:19.50|HUBA0S27_TR:20.00|HUBA0S28_MX:19.00|HUBA0S28_TR:20.50|HUBA0S29_MX:19.50|HUBA0S29_TR:19.00                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F3_X                                0.940|0.940|0.971|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F3_X_DTS                            HUBAON_MX:22.00|HUBAON_TR:20.50|MEM1S0_MX:27.50|MEM1S0_TR:22.00|MEM1S1_MX:22.00|MEM1S1_TR:22.00|MEM1S2_MX:21.50|MEM1S2_TR:23.50|MEM1S3_MX:23.00|MEM1S3_TR:23.50|DIS1S4_MX:27.00|DIS1S4_TR:27.00|DIS1S5_MX:27.50|DI
                                                                                          S1S5_TR:22.00|DIS1S6_MX:21.00|DIS1S6_TR:20.50|DIS1S7_MX:21.50|DIS1S7_TR:22.50|MEM1S8_MX:21.50|MEM1S8_TR:23.50|VPU2S0_MX:22.00|VPU2S0_TR:21.50|VPU2S1_MX:21.00|VPU2S1_TR:21.50|VPU2S2_MX:22.50|VPU2S2_TR:23.00|VPU2
                                                                                          S3_MX:22.50|VPU2S3_TR:22.00|VPU2S4_MX:23.00|VPU2S4_TR:23.00|VPU2S5_MX:21.00|VPU2S5_TR:20.50|VPU2S6_MX:21.00|VPU2S6_TR:20.00|VPU2S7_MX:21.00|VPU2S7_TR:22.00|VPU2S8_MX:21.50|VPU2S8_TR:21.00|MED3S0_MX:22.50|MED3S0
                                                                                          _TR:22.50|MED3S1_MX:23.50|MED3S1_TR:22.00|MED3S2_MX:22.50|MED3S2_TR:24.00|MED3S3_MX:23.00|MED3S3_TR:22.00|MED3S4_MX:22.50|MED3S4_TR:21.50|IPU3S5_MX:21.50|IPU3S5_TR:21.00|IPU3S6_MX:21.00|IPU3S6_TR:21.00|IPU3S7_M
                                                                                          X:21.00|IPU3S7_TR:21.50|MED3S8_MX:22.00|MED3S8_TR:21.00|HUBA0S0_MX:21.00|HUBA0S0_TR:21.50|HUBA0S2_MX:21.00|HUBA0S2_TR:22.00|HUBA0S3_MX:21.50|HUBA0S3_TR:21.00|HUBA0S4_MX:22.50|HUBA0S4_TR:21.50|HUBA0S5_MX:22.50|H
                                                                                          UBA0S5_TR:20.50|HUBA0S6_MX:21.50|HUBA0S6_TR:22.00|HUBA0S7_MX:21.50|HUBA0S7_TR:20.00|HUBA0S8_MX:21.00|HUBA0S8_TR:21.50|HUBA0S9_MX:21.00|HUBA0S9_TR:19.50|HUBA0S10_MX:20.50|HUBA0S10_TR:21.00|HUBA0S11_MX:20.00|HUBA
                                                                                          0S11_TR:19.00|HUBA0S12_MX:20.00|HUBA0S12_TR:20.50|HUBA0S13_MX:20.00|HUBA0S13_TR:19.50|HUBA0S16_MX:20.50|HUBA0S16_TR:19.50|HUBA0S17_MX:20.00|HUBA0S17_TR:21.00|HUBA0S18_MX:21.50|HUBA0S18_TR:20.50|HUBA0S19_MX:22.0
                                                                                          0|HUBA0S19_TR:21.00|HUBA0S20_MX:21.50|HUBA0S20_TR:22.00|HUBA0S21_MX:20.50|HUBA0S21_TR:21.50|HUBA0S24_MX:22.00|HUBA0S24_TR:22.00|HUBA0S25_MX:21.50|HUBA0S25_TR:22.50|HUBA0S26_MX:21.50|HUBA0S26_TR:22.00|HUBA0S27_M
                                                                                          X:23.50|HUBA0S27_TR:22.50|HUBA0S28_MX:23.00|HUBA0S28_TR:23.00|HUBA0S29_MX:23.00|HUBA0S29_TR:23.00                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F5_X_1001                           1.050|1.050|1.081|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_LTTCHUB_X_VCCSA_F5_X_1001_DTS                       HUBAON_MX:23.50|HUBAON_TR:20.50|MEM1S0_MX:32.50|MEM1S0_TR:24.50|MEM1S1_MX:23.50|MEM1S1_TR:22.00|MEM1S2_MX:22.50|MEM1S2_TR:25.00|MEM1S3_MX:24.00|MEM1S3_TR:24.50|DIS1S4_MX:32.00|DIS1S4_TR:32.00|DIS1S5_MX:32.50|DI
                                                                                          S1S5_TR:22.00|DIS1S6_MX:23.50|DIS1S6_TR:22.00|DIS1S7_MX:22.50|DIS1S7_TR:25.00|MEM1S8_MX:23.00|MEM1S8_TR:23.50|VPU2S0_MX:23.00|VPU2S0_TR:23.00|VPU2S1_MX:23.50|VPU2S1_TR:21.50|VPU2S2_MX:22.50|VPU2S2_TR:24.50|VPU2
                                                                                          S3_MX:24.00|VPU2S3_TR:23.00|VPU2S4_MX:25.50|VPU2S4_TR:23.00|VPU2S5_MX:22.00|VPU2S5_TR:21.50|VPU2S6_MX:22.00|VPU2S6_TR:21.50|VPU2S7_MX:22.50|VPU2S7_TR:22.00|VPU2S8_MX:22.50|VPU2S8_TR:22.00|MED3S0_MX:24.00|MED3S0
                                                                                          _TR:23.50|MED3S1_MX:23.50|MED3S1_TR:23.50|MED3S2_MX:23.50|MED3S2_TR:24.00|MED3S3_MX:24.50|MED3S3_TR:23.50|MED3S4_MX:24.00|MED3S4_TR:24.00|IPU3S5_MX:22.50|IPU3S5_TR:22.50|IPU3S6_MX:23.50|IPU3S6_TR:22.00|IPU3S7_M
                                                                                          X:22.50|IPU3S7_TR:24.00|MED3S8_MX:23.00|MED3S8_TR:23.50|HUBA0S0_MX:23.50|HUBA0S0_TR:23.00|HUBA0S2_MX:23.50|HUBA0S2_TR:22.00|HUBA0S3_MX:21.50|HUBA0S3_TR:23.50|HUBA0S4_MX:22.50|HUBA0S4_TR:23.00|HUBA0S5_MX:22.50|H
                                                                                          UBA0S5_TR:23.00|HUBA0S6_MX:22.50|HUBA0S6_TR:22.00|HUBA0S7_MX:22.50|HUBA0S7_TR:20.00|HUBA0S8_MX:21.00|HUBA0S8_TR:20.50|HUBA0S9_MX:21.00|HUBA0S9_TR:21.00|HUBA0S10_MX:21.50|HUBA0S10_TR:21.00|HUBA0S11_MX:22.50|HUBA
                                                                                          0S11_TR:20.50|HUBA0S12_MX:22.50|HUBA0S12_TR:20.50|HUBA0S13_MX:20.00|HUBA0S13_TR:22.00|HUBA0S16_MX:22.00|HUBA0S16_TR:21.00|HUBA0S17_MX:21.50|HUBA0S17_TR:22.50|HUBA0S18_MX:21.50|HUBA0S18_TR:22.00|HUBA0S19_MX:22.0
                                                                                          0|HUBA0S19_TR:22.50|HUBA0S20_MX:21.50|HUBA0S20_TR:22.00|HUBA0S21_MX:22.00|HUBA0S21_TR:21.50|HUBA0S24_MX:23.00|HUBA0S24_TR:23.50|HUBA0S25_MX:23.00|HUBA0S25_TR:22.50|HUBA0S26_MX:23.00|HUBA0S26_TR:23.50|HUBA0S27_M
                                                                                          X:23.50|HUBA0S27_TR:23.50|HUBA0S28_MX:23.00|HUBA0S28_TR:24.50|HUBA0S29_MX:23.00|HUBA0S29_TR:24.50                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F1XSN_X_VCCSA_F1_X                                   0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|1                                               
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F1XSN_X_VCCSA_F1_X_DTS                               HUBAON_MX:96.00|HUBAON_TR:96.00|MEM1S0_MX:96.00|MEM1S0_TR:95.00|MEM1S1_MX:95.50|MEM1S1_TR:95.00|MEM1S2_MX:95.00|MEM1S2_TR:95.50|MEM1S3_MX:96.50|MEM1S3_TR:95.00|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DI
                                                                                          S1S5_TR:95.00|DIS1S6_MX:95.50|DIS1S6_TR:93.50|DIS1S7_MX:95.00|DIS1S7_TR:94.50|MEM1S8_MX:95.00|MEM1S8_TR:95.00|VPU2S0_MX:95.00|VPU2S0_TR:96.00|VPU2S1_MX:96.50|VPU2S1_TR:94.50|VPU2S2_MX:95.50|VPU2S2_TR:97.00|VPU2
                                                                                          S3_MX:95.50|VPU2S3_TR:95.50|VPU2S4_MX:96.50|VPU2S4_TR:95.00|VPU2S5_MX:94.00|VPU2S5_TR:94.50|VPU2S6_MX:95.50|VPU2S6_TR:94.50|VPU2S7_MX:95.50|VPU2S7_TR:97.00|VPU2S8_MX:94.50|VPU2S8_TR:94.50|MED3S0_MX:97.00|MED3S0
                                                                                          _TR:95.50|MED3S1_MX:95.50|MED3S1_TR:95.50|MED3S2_MX:95.50|MED3S2_TR:97.50|MED3S3_MX:96.50|MED3S3_TR:96.50|MED3S4_MX:97.00|MED3S4_TR:95.50|IPU3S5_MX:95.50|IPU3S5_TR:95.50|IPU3S6_MX:95.50|IPU3S6_TR:94.50|IPU3S7_M
                                                                                          X:95.50|IPU3S7_TR:96.50|MED3S8_MX:96.50|MED3S8_TR:95.50|HUBA0S0_MX:95.00|HUBA0S0_TR:96.50|HUBA0S2_MX:95.50|HUBA0S2_TR:95.50|HUBA0S3_MX:95.50|HUBA0S3_TR:96.00|HUBA0S4_MX:97.00|HUBA0S4_TR:96.00|HUBA0S5_MX:97.00|H
                                                                                          UBA0S5_TR:95.50|HUBA0S6_MX:95.50|HUBA0S6_TR:96.50|HUBA0S7_MX:95.00|HUBA0S7_TR:95.00|HUBA0S8_MX:95.00|HUBA0S8_TR:94.00|HUBA0S9_MX:94.00|HUBA0S9_TR:94.50|HUBA0S10_MX:94.50|HUBA0S10_TR:96.00|HUBA0S11_MX:95.50|HUBA
                                                                                          0S11_TR:96.00|HUBA0S12_MX:94.50|HUBA0S12_TR:94.50|HUBA0S13_MX:94.50|HUBA0S13_TR:95.00|HUBA0S16_MX:95.50|HUBA0S16_TR:95.50|HUBA0S17_MX:95.50|HUBA0S17_TR:94.00|HUBA0S18_MX:94.50|HUBA0S18_TR:95.00|HUBA0S19_MX:95.0
                                                                                          0|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR:94.00|HUBA0S24_MX:95.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:96.50|HUBA0S26_MX:97.50|HUBA0S26_TR:96.50|HUBA0S27_M
                                                                                          X:96.50|HUBA0S27_TR:95.50|HUBA0S28_MX:96.50|HUBA0S28_TR:97.00|HUBA0S29_MX:97.00|HUBA0S29_TR:96.50                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F1XSN_X_VCCSA_F1_X_VMINFWCFG                         SAQ0@F1:1:1.400_SAC0@F1:1:1.400_SAN0@F1:1:0.600_SACD0@F1:1:0.403_SAVPU0@F1:1:0.629_SAME0@F1:1:0.450_SAIOC0@F1:1:0.500_SAPS0@F1:1:0.500_SADPU0@F1:1:1.100                                                          
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F2XSN_X_VCCSA_F2_X                                   0.790_0.790_0.790_0.790_0.790_0.790_0.790_0.790_0.790|0.790_0.790_0.790_0.790_0.790_0.790_0.790_0.790_0.790|1.100_1.100_1.100_1.100_1.100_1.100_1.100_1.100_1.100|1                                               
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F2XSN_X_VCCSA_F2_X_DTS                               HUBAON_MX:92.50|HUBAON_TR:91.50|MEM1S0_MX:94.50|MEM1S0_TR:89.50|MEM1S1_MX:89.00|MEM1S1_TR:88.00|MEM1S2_MX:89.50|MEM1S2_TR:90.50|MEM1S3_MX:90.00|MEM1S3_TR:89.50|DIS1S4_MX:92.00|DIS1S4_TR:92.00|DIS1S5_MX:94.50|DI
                                                                                          S1S5_TR:89.50|DIS1S6_MX:89.00|DIS1S6_TR:88.00|DIS1S7_MX:88.00|DIS1S7_TR:89.00|MEM1S8_MX:90.00|MEM1S8_TR:88.50|VPU2S0_MX:91.50|VPU2S0_TR:92.50|VPU2S1_MX:93.00|VPU2S1_TR:91.00|VPU2S2_MX:91.00|VPU2S2_TR:91.00|VPU2
                                                                                          S3_MX:91.00|VPU2S3_TR:90.00|VPU2S4_MX:91.50|VPU2S4_TR:90.50|VPU2S5_MX:90.50|VPU2S5_TR:91.00|VPU2S6_MX:92.00|VPU2S6_TR:90.00|VPU2S7_MX:91.00|VPU2S7_TR:91.00|VPU2S8_MX:89.50|VPU2S8_TR:88.50|MED3S0_MX:92.00|MED3S0
                                                                                          _TR:92.00|MED3S1_MX:90.50|MED3S1_TR:90.50|MED3S2_MX:93.00|MED3S2_TR:92.50|MED3S3_MX:92.50|MED3S3_TR:91.50|MED3S4_MX:92.00|MED3S4_TR:92.00|IPU3S5_MX:91.00|IPU3S5_TR:90.50|IPU3S6_MX:90.50|IPU3S6_TR:90.50|IPU3S7_M
                                                                                          X:92.00|IPU3S7_TR:92.50|MED3S8_MX:92.50|MED3S8_TR:90.50|HUBA0S0_MX:90.00|HUBA0S0_TR:90.50|HUBA0S2_MX:90.50|HUBA0S2_TR:90.50|HUBA0S3_MX:90.50|HUBA0S3_TR:91.00|HUBA0S4_MX:90.50|HUBA0S4_TR:91.00|HUBA0S5_MX:91.00|H
                                                                                          UBA0S5_TR:91.00|HUBA0S6_MX:90.50|HUBA0S6_TR:90.50|HUBA0S7_MX:90.00|HUBA0S7_TR:88.50|HUBA0S8_MX:89.00|HUBA0S8_TR:89.00|HUBA0S9_MX:89.00|HUBA0S9_TR:89.50|HUBA0S10_MX:89.50|HUBA0S10_TR:91.00|HUBA0S11_MX:90.50|HUBA
                                                                                          0S11_TR:89.50|HUBA0S12_MX:89.50|HUBA0S12_TR:89.50|HUBA0S13_MX:89.50|HUBA0S13_TR:89.00|HUBA0S16_MX:90.50|HUBA0S16_TR:90.00|HUBA0S17_MX:90.00|HUBA0S17_TR:88.50|HUBA0S18_MX:91.00|HUBA0S18_TR:91.00|HUBA0S19_MX:89.5
                                                                                          0|HUBA0S19_TR:89.00|HUBA0S20_MX:88.50|HUBA0S20_TR:89.50|HUBA0S21_MX:89.00|HUBA0S21_TR:88.50|HUBA0S24_MX:90.50|HUBA0S24_TR:90.00|HUBA0S25_MX:90.00|HUBA0S25_TR:91.50|HUBA0S26_MX:92.00|HUBA0S26_TR:91.00|HUBA0S27_M
                                                                                          X:91.00|HUBA0S27_TR:91.50|HUBA0S28_MX:91.50|HUBA0S28_TR:92.00|HUBA0S29_MX:90.50|HUBA0S29_TR:91.50                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F2XSN_X_VCCSA_F2_X_VMINFWCFG                         SAQ0@F2:1:3.000_SAC0@F2:1:2.450_SAN0@F2:1:1.500_SACD0@F2:1:0.787_SAVPU0@F2:1:1.257_SAME0@F2:1:1.200_SAIOC0@F2:1:0.750_SAPS0@F2:1:0.750_SADPU0@F2:1:2.200                                                          
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F3XSN_X_VCCSA_F3_X                                   0.870_0.870_0.870_0.870_0.870_0.870|0.860_0.860_0.860_0.860_0.860_0.860|1.100_1.100_1.100_1.100_1.100_1.100|2                                                                                                     
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F3XSN_X_VCCSA_F3_X_DTS                               HUBAON_MX:92.50|HUBAON_TR:90.00|MEM1S0_MX:96.00|MEM1S0_TR:91.00|MEM1S1_MX:90.00|MEM1S1_TR:89.50|MEM1S2_MX:91.00|MEM1S2_TR:90.50|MEM1S3_MX:91.00|MEM1S3_TR:91.00|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DI
                                                                                          S1S5_TR:89.50|DIS1S6_MX:90.00|DIS1S6_TR:88.00|DIS1S7_MX:91.00|DIS1S7_TR:90.50|MEM1S8_MX:91.00|MEM1S8_TR:89.50|VPU2S0_MX:91.50|VPU2S0_TR:91.00|VPU2S1_MX:93.00|VPU2S1_TR:90.00|VPU2S2_MX:92.00|VPU2S2_TR:92.00|VPU2
                                                                                          S3_MX:92.00|VPU2S3_TR:91.00|VPU2S4_MX:93.00|VPU2S4_TR:91.50|VPU2S5_MX:90.50|VPU2S5_TR:91.00|VPU2S6_MX:90.50|VPU2S6_TR:90.00|VPU2S7_MX:91.00|VPU2S7_TR:91.00|VPU2S8_MX:92.00|VPU2S8_TR:91.00|MED3S0_MX:92.00|MED3S0
                                                                                          _TR:92.00|MED3S1_MX:90.50|MED3S1_TR:90.50|MED3S2_MX:93.00|MED3S2_TR:92.50|MED3S3_MX:92.50|MED3S3_TR:93.00|MED3S4_MX:93.00|MED3S4_TR:92.00|IPU3S5_MX:91.00|IPU3S5_TR:90.50|IPU3S6_MX:90.50|IPU3S6_TR:90.50|IPU3S7_M
                                                                                          X:92.00|IPU3S7_TR:92.50|MED3S8_MX:91.50|MED3S8_TR:91.50|HUBA0S0_MX:90.00|HUBA0S0_TR:90.50|HUBA0S2_MX:90.50|HUBA0S2_TR:90.50|HUBA0S3_MX:89.50|HUBA0S3_TR:91.00|HUBA0S4_MX:92.00|HUBA0S4_TR:91.00|HUBA0S5_MX:91.00|H
                                                                                          UBA0S5_TR:89.50|HUBA0S6_MX:89.50|HUBA0S6_TR:90.50|HUBA0S7_MX:90.00|HUBA0S7_TR:88.50|HUBA0S8_MX:89.00|HUBA0S8_TR:89.00|HUBA0S9_MX:88.00|HUBA0S9_TR:88.00|HUBA0S10_MX:88.00|HUBA0S10_TR:88.50|HUBA0S11_MX:89.50|HUBA
                                                                                          0S11_TR:89.50|HUBA0S12_MX:89.50|HUBA0S12_TR:89.50|HUBA0S13_MX:88.50|HUBA0S13_TR:89.00|HUBA0S16_MX:90.50|HUBA0S16_TR:90.00|HUBA0S17_MX:90.00|HUBA0S17_TR:88.50|HUBA0S18_MX:89.50|HUBA0S18_TR:90.00|HUBA0S19_MX:89.5
                                                                                          0|HUBA0S19_TR:89.00|HUBA0S20_MX:88.50|HUBA0S20_TR:89.50|HUBA0S21_MX:89.00|HUBA0S21_TR:88.50|HUBA0S24_MX:90.50|HUBA0S24_TR:90.00|HUBA0S25_MX:90.00|HUBA0S25_TR:91.50|HUBA0S26_MX:92.00|HUBA0S26_TR:91.00|HUBA0S27_M
                                                                                          X:91.00|HUBA0S27_TR:91.50|HUBA0S28_MX:91.50|HUBA0S28_TR:92.00|HUBA0S29_MX:91.50|HUBA0S29_TR:91.50                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F3XSN_X_VCCSA_F3_X_LP                                0099515^0099515^0099515^0099515^0099515^0099515                                                                                                                                                                   
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_F3XSN_X_VCCSA_F3_X_VMINFWCFG                         SAC0@F3:1:2.700_SADPU0@F3:1:2.500_SAME0@F3:1:1.450_SAN0@F3:1:1.650_SAQ0@F3:1:3.400_SAVPU0@F3:1:1.429                                                                                                              
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_LTTCHUB_X_VCCSA_F1_X                                 0.710|0.710|0.741|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_LTTCHUB_X_VCCSA_F1_X_DTS                             HUBAON_MX:18.00|HUBAON_TR:15.50|MEM1S0_MX:19.50|MEM1S0_TR:18.50|MEM1S1_MX:18.50|MEM1S1_TR:18.00|MEM1S2_MX:19.00|MEM1S2_TR:20.00|MEM1S3_MX:19.00|MEM1S3_TR:19.50|DIS1S4_MX:19.50|DIS1S4_TR:18.50|DIS1S5_MX:18.50|DI
                                                                                          S1S5_TR:17.00|DIS1S6_MX:17.00|DIS1S6_TR:17.00|DIS1S7_MX:16.50|DIS1S7_TR:18.50|MEM1S8_MX:18.00|MEM1S8_TR:18.50|VPU2S0_MX:18.50|VPU2S0_TR:18.00|VPU2S1_MX:17.50|VPU2S1_TR:18.00|VPU2S2_MX:19.00|VPU2S2_TR:19.50|VPU2
                                                                                          S3_MX:19.00|VPU2S3_TR:17.00|VPU2S4_MX:18.50|VPU2S4_TR:17.00|VPU2S5_MX:16.00|VPU2S5_TR:17.00|VPU2S6_MX:17.50|VPU2S6_TR:16.50|VPU2S7_MX:17.50|VPU2S7_TR:17.00|VPU2S8_MX:16.50|VPU2S8_TR:16.00|MED3S0_MX:19.00|MED3S0
                                                                                          _TR:17.50|MED3S1_MX:18.50|MED3S1_TR:18.50|MED3S2_MX:17.50|MED3S2_TR:18.50|MED3S3_MX:19.50|MED3S3_TR:18.50|MED3S4_MX:19.00|MED3S4_TR:17.50|IPU3S5_MX:16.50|IPU3S5_TR:17.50|IPU3S6_MX:18.50|IPU3S6_TR:17.00|IPU3S7_M
                                                                                          X:17.50|IPU3S7_TR:18.50|MED3S8_MX:17.00|MED3S8_TR:17.00|HUBA0S0_MX:18.50|HUBA0S0_TR:19.00|HUBA0S2_MX:18.50|HUBA0S2_TR:19.50|HUBA0S3_MX:19.00|HUBA0S3_TR:18.50|HUBA0S4_MX:20.00|HUBA0S4_TR:18.00|HUBA0S5_MX:19.00|H
                                                                                          UBA0S5_TR:18.00|HUBA0S6_MX:17.50|HUBA0S6_TR:19.50|HUBA0S7_MX:17.50|HUBA0S7_TR:15.00|HUBA0S8_MX:16.00|HUBA0S8_TR:16.50|HUBA0S9_MX:16.50|HUBA0S9_TR:17.50|HUBA0S10_MX:16.50|HUBA0S10_TR:16.00|HUBA0S11_MX:17.50|HUBA
                                                                                          0S11_TR:15.50|HUBA0S12_MX:17.50|HUBA0S12_TR:15.50|HUBA0S13_MX:15.50|HUBA0S13_TR:17.50|HUBA0S16_MX:16.50|HUBA0S16_TR:17.00|HUBA0S17_MX:16.00|HUBA0S17_TR:17.00|HUBA0S18_MX:16.00|HUBA0S18_TR:18.00|HUBA0S19_MX:18.0
                                                                                          0|HUBA0S19_TR:17.00|HUBA0S20_MX:19.00|HUBA0S20_TR:18.00|HUBA0S21_MX:18.00|HUBA0S21_TR:17.50|HUBA0S24_MX:18.00|HUBA0S24_TR:18.00|HUBA0S25_MX:19.00|HUBA0S25_TR:20.00|HUBA0S26_MX:19.00|HUBA0S26_TR:19.50|HUBA0S27_M
                                                                                          X:19.50|HUBA0S27_TR:20.00|HUBA0S28_MX:19.00|HUBA0S28_TR:20.50|HUBA0S29_MX:19.50|HUBA0S29_TR:19.00                                                                                                                 
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_LTTCHUB_X_VCCSA_F2_X                                 0.880|0.880|0.911|1                                                                                                                                                                                               
IPH::SCN_HUB_HXX::ATSPEED_NPU_VMIN_K_LTTCHUB_X_VCCSA_F2_X_DTS                             HUBAON_MX:18.00|HUBAON_TR:18.00|MEM1S0_MX:23.50|MEM1S0_TR:18.50|MEM1S1_MX:19.50|MEM1S1_TR:18.00|MEM1S2_MX:17.50|MEM1S2_TR:20.00|MEM1S3_MX:19.00|MEM1S3_TR:19.50|DIS1S4_MX:22.00|DIS1S4_TR:22.00|DIS1S5_MX:22.00|DI
                                                                                          S1S5_TR:18.50|DIS1S6_MX:17.00|DIS1S6_TR:17.00|DIS1S7_MX:17.50|DIS1S7_TR:18.50|MEM1S8_MX:18.00|MEM1S8_TR:18.50|VPU2S0_MX:18.50|VPU2S0_TR:19.00|VPU2S1_MX:18.50|VPU2S1_TR:18.00|VPU2S2_MX:19.00|VPU2S2_TR:19.50|VPU2
                                                                                          S3_MX:19.00|VPU2S3_TR:17.00|VPU2S4_MX:19.50|VPU2S4_TR:17.00|VPU2S5_MX:17.00|VPU2S5_TR:17.00|VPU2S6_MX:17.50|VPU2S6_TR:16.50|VPU2S7_MX:17.50|VPU2S7_TR:18.50|VPU2S8_MX:18.00|VPU2S8_TR:17.00|MED3S0_MX:19.00|MED3S0
                                                                                          _TR:18.50|MED3S1_MX:18.50|MED3S1_TR:18.50|MED3S2_MX:20.00|MED3S2_TR:18.50|MED3S3_MX:19.50|MED3S3_TR:18.50|MED3S4_MX:19.00|MED3S4_TR:19.00|IPU3S5_MX:19.00|IPU3S5_TR:17.50|IPU3S6_MX:18.50|IPU3S6_TR:18.50|IPU3S7_M
                                                                                          X:20.00|IPU3S7_TR:18.50|MED3S8_MX:19.50|MED3S8_TR:18.50|HUBA0S0_MX:18.50|HUBA0S0_TR:19.00|HUBA0S2_MX:18.50|HUBA0S2_TR:19.50|HUBA0S3_MX:19.00|HUBA0S3_TR:18.50|HUBA0S4_MX:20.00|HUBA0S4_TR:18.00|HUBA0S5_MX:20.00|H
                                                                                          UBA0S5_TR:18.00|HUBA0S6_MX:19.00|HUBA0S6_TR:19.50|HUBA0S7_MX:17.50|HUBA0S7_TR:17.50|HUBA0S8_MX:17.50|HUBA0S8_TR:18.00|HUBA0S9_MX:18.50|HUBA0S9_TR:18.50|HUBA0S10_MX:19.00|HUBA0S10_TR:18.50|HUBA0S11_MX:19.00|HUBA
                                                                                          0S11_TR:18.00|HUBA0S12_MX:17.50|HUBA0S12_TR:18.00|HUBA0S13_MX:17.50|HUBA0S13_TR:17.50|HUBA0S16_MX:18.00|HUBA0S16_TR:17.00|HUBA0S17_MX:19.00|HUBA0S17_TR:20.00|HUBA0S18_MX:19.00|HUBA0S18_TR:18.00|HUBA0S19_MX:18.0
                                                                                          0|HUBA0S19_TR:18.50|HUBA0S20_MX:19.00|HUBA0S20_TR:18.00|HUBA0S21_MX:18.00|HUBA0S21_TR:19.00|HUBA0S24_MX:19.00|HUBA0S24_TR:18.00|HUBA0S25_MX:20.00|HUBA0S25_TR:20.00|HUBA0S26_MX:19.00|HUBA0S26_TR:19.50|HUBA0S27_M
                                                                                          X:21.00|HUBA0S27_TR:20.00|HUBA0S28_MX:20.50|HUBA0S28_TR:20.50|HUBA0S29_MX:20.50|HUBA0S29_TR:20.50                                                                                                                 



PS C:\Projects\NVL\.docs> Import-Csv "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" | Where-Object { $_.'VISUAL_ID' -eq 'U6XH126700474' -and $_.'TEST_NAME' -like '*FMINXSN*' } | Select-Object TEST_NAME, TEST_RESULT | Format-Table -AutoSize -Wrap | Out-String -Width 400

TEST_NAME                                                                                TEST_RESULT                                                                                                                                                                                                                                                                                                            
---------                                                                                -----------                                                                                                                                                                                                                                                                                                            
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_COMBINED                 0.480|0.480|1.121|1                                                                                                                                                                                                                                                                                                    
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_COMBINED_VMINFWCFG       SAAT0@F1:1:1.200                                                                                                                                                                                                                                                                                                       
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_ECCON_L2_DATA            0.480|0.480|1.121|1                                                                                                                                                                                                                                                                                                    
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE                          0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_IT                       0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_VMINFWCFG                SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP                             0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_IT                          0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_VMINFWCFG                   SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU                              0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_IT                           0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_VMINFWCFG                    SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA                            0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_IT                         0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_VMINFWCFG                  SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC                           0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC_IT                        0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC_VMINFWCFG                 SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED           0.480|0.480|0.811|1                                                                                                                                                                                                                                                                                                    
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED_DTS       HUBAON_MX:97.50|HUBAON_TR:96.00|MEM1S0_MX:96.00|MEM1S0_TR:96.50|MEM1S1_MX:95.50|MEM1S1_TR:95.00|MEM1S2_MX:96.50|MEM1S2_TR:97.00|MEM1S3_MX:96.50|MEM1S3_TR:96.50|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DIS1S5_TR:95.00|DIS1S6_MX:95.50|DIS1S6_TR:92.00|DIS1S7_MX:95.00|DIS1S7_TR:94.50|MEM1S8_MX:95.00|MEM1S8_
                                                                                         TR:94.00|VPU2S0_MX:96.00|VPU2S0_TR:96.00|VPU2S1_MX:96.50|VPU2S1_TR:94.50|VPU2S2_MX:97.00|VPU2S2_TR:97.00|VPU2S3_MX:96.50|VPU2S3_TR:95.50|VPU2S4_MX:96.50|VPU2S4_TR:95.00|VPU2S5_MX:94.00|VPU2S5_TR:94.50|VPU2S6_MX:94.00|VPU2S6_TR:93.50|VPU2S7_MX:95.50|VPU2S7_TR:95.50|VPU2S8_MX:94.50|VPU2S8_TR:94.50|MED3S0_MX:97.0
                                                                                         0|MED3S0_TR:96.50|MED3S1_MX:95.50|MED3S1_TR:95.50|MED3S2_MX:96.50|MED3S2_TR:97.50|MED3S3_MX:97.50|MED3S3_TR:97.50|MED3S4_MX:97.00|MED3S4_TR:95.50|IPU3S5_MX:95.50|IPU3S5_TR:95.50|IPU3S6_MX:94.00|IPU3S6_TR:94.50|IPU3S7_MX:95.50|IPU3S7_TR:96.50|MED3S8_MX:96.50|MED3S8_TR:95.50|HUBA0S0_MX:95.00|HUBA0S0_TR:95.50|HUB
                                                                                         A0S2_MX:95.50|HUBA0S2_TR:95.50|HUBA0S3_MX:95.50|HUBA0S3_TR:96.00|HUBA0S4_MX:95.50|HUBA0S4_TR:96.00|HUBA0S5_MX:97.00|HUBA0S5_TR:94.50|HUBA0S6_MX:94.50|HUBA0S6_TR:95.00|HUBA0S7_MX:95.00|HUBA0S7_TR:95.00|HUBA0S8_MX:92.50|HUBA0S8_TR:94.00|HUBA0S9_MX:95.50|HUBA0S9_TR:93.00|HUBA0S10_MX:93.00|HUBA0S10_TR:96.00|HUBA0S
                                                                                         11_MX:94.50|HUBA0S11_TR:93.50|HUBA0S12_MX:94.50|HUBA0S12_TR:93.50|HUBA0S13_MX:94.50|HUBA0S13_TR:94.00|HUBA0S16_MX:94.50|HUBA0S16_TR:95.50|HUBA0S17_MX:95.50|HUBA0S17_TR:94.00|HUBA0S18_MX:97.50|HUBA0S18_TR:96.50|HUBA0S19_MX:95.00|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR
                                                                                         :94.00|HUBA0S24_MX:95.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:95.50|HUBA0S26_MX:97.50|HUBA0S26_TR:96.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:95.50|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:95.50                                                                                         
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED_VMINFWCFG SAAT0@F1:1:1.200                                                                                                                                                                                                                                                                                                       
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL                 0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.811_0.811_0.811_0.811_0.811_0.811_0.811_0.811_0.811|1                                                                                                                                                    
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL_DTS             HUBAON_MX:92.50|HUBAON_TR:91.50|MEM1S0_MX:90.50|MEM1S0_TR:89.50|MEM1S1_MX:90.00|MEM1S1_TR:89.50|MEM1S2_MX:91.00|MEM1S2_TR:90.50|MEM1S3_MX:91.00|MEM1S3_TR:91.00|DIS1S4_MX:89.00|DIS1S4_TR:89.00|DIS1S5_MX:90.50|DIS1S5_TR:89.50|DIS1S6_MX:90.00|DIS1S6_TR:89.50|DIS1S7_MX:89.50|DIS1S7_TR:90.50|MEM1S8_MX:90.00|MEM1S8_
                                                                                         TR:89.50|VPU2S0_MX:90.50|VPU2S0_TR:91.00|VPU2S1_MX:92.00|VPU2S1_TR:90.00|VPU2S2_MX:92.00|VPU2S2_TR:92.00|VPU2S3_MX:92.00|VPU2S3_TR:91.00|VPU2S4_MX:91.50|VPU2S4_TR:91.50|VPU2S5_MX:89.00|VPU2S5_TR:90.00|VPU2S6_MX:92.00|VPU2S6_TR:90.00|VPU2S7_MX:91.00|VPU2S7_TR:91.00|VPU2S8_MX:91.00|VPU2S8_TR:91.00|MED3S0_MX:91.0
                                                                                         0|MED3S0_TR:92.00|MED3S1_MX:90.50|MED3S1_TR:90.50|MED3S2_MX:92.00|MED3S2_TR:92.50|MED3S3_MX:91.50|MED3S3_TR:91.50|MED3S4_MX:92.00|MED3S4_TR:90.50|IPU3S5_MX:91.00|IPU3S5_TR:90.50|IPU3S6_MX:89.50|IPU3S6_TR:89.50|IPU3S7_MX:90.50|IPU3S7_TR:91.50|MED3S8_MX:91.50|MED3S8_TR:91.50|HUBA0S0_MX:91.50|HUBA0S0_TR:91.50|HUB
                                                                                         A0S2_MX:90.50|HUBA0S2_TR:90.50|HUBA0S3_MX:90.50|HUBA0S3_TR:91.00|HUBA0S4_MX:90.50|HUBA0S4_TR:91.00|HUBA0S5_MX:91.00|HUBA0S5_TR:89.50|HUBA0S6_MX:90.50|HUBA0S6_TR:90.50|HUBA0S7_MX:91.00|HUBA0S7_TR:90.00|HUBA0S8_MX:90.00|HUBA0S8_TR:90.50|HUBA0S9_MX:89.00|HUBA0S9_TR:89.50|HUBA0S10_MX:90.50|HUBA0S10_TR:91.00|HUBA0S
                                                                                         11_MX:90.50|HUBA0S11_TR:89.50|HUBA0S12_MX:91.00|HUBA0S12_TR:89.50|HUBA0S13_MX:89.50|HUBA0S13_TR:90.50|HUBA0S16_MX:90.50|HUBA0S16_TR:90.00|HUBA0S17_MX:90.00|HUBA0S17_TR:91.50|HUBA0S18_MX:92.00|HUBA0S18_TR:91.00|HUBA0S19_MX:92.50|HUBA0S19_TR:90.50|HUBA0S20_MX:90.00|HUBA0S20_TR:90.50|HUBA0S21_MX:91.50|HUBA0S21_TR
                                                                                         :91.50|HUBA0S24_MX:90.50|HUBA0S24_TR:91.50|HUBA0S25_MX:91.50|HUBA0S25_TR:91.50|HUBA0S26_MX:92.00|HUBA0S26_TR:91.00|HUBA0S27_MX:92.50|HUBA0S27_TR:91.50|HUBA0S28_MX:91.50|HUBA0S28_TR:90.50|HUBA0S29_MX:91.50|HUBA0S29_TR:91.50                                                                                         
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL_VMINFWCFG       SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_COMBINED                 0.480|0.480|1.121|1                                                                                                                                                                                                                                                                                                    
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_COMBINED_VMINFWCFG       SAAT0@F1:1:1.200                                                                                                                                                                                                                                                                                                       
IPH::ARR_ATOM_HXPKGMB::ARR_ATOM_VMIN_K_FMINXSN_HITO_SAAT_FMIN_X_ECCON_L2_DATA            0.480|0.480|1.121|1                                                                                                                                                                                                                                                                                                    
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE                          0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_IT                       0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_VMINFWCFG                SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP                             0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_IT                          0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_VMINFWCFG                   SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU                              0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_IT                           0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_VMINFWCFG                    SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA                            0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_IT                         0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_VMINFWCFG                  SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC                           0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1                                                                                                                                                    
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC_IT                        0                                                                                                                                                                                                                                                                                                                      
IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC_VMINFWCFG                 SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629                                                                                                                                                               
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED           0.480|0.480|0.811|1                                                                                                                                                                                                                                                                                                    
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED_DTS       HUBAON_MX:97.50|HUBAON_TR:96.00|MEM1S0_MX:96.00|MEM1S0_TR:96.50|MEM1S1_MX:95.50|MEM1S1_TR:95.00|MEM1S2_MX:96.50|MEM1S2_TR:97.00|MEM1S3_MX:96.50|MEM1S3_TR:96.50|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DIS1S5_TR:95.00|DIS1S6_MX:95.50|DIS1S6_TR:92.00|DIS1S7_MX:95.00|DIS1S7_TR:94.50|MEM1S8_MX:95.00|MEM1S8_
                                                                                         TR:94.00|VPU2S0_MX:96.00|VPU2S0_TR:96.00|VPU2S1_MX:96.50|VPU2S1_TR:94.50|VPU2S2_MX:97.00|VPU2S2_TR:97.00|VPU2S3_MX:96.50|VPU2S3_TR:95.50|VPU2S4_MX:96.50|VPU2S4_TR:95.00|VPU2S5_MX:94.00|VPU2S5_TR:94.50|VPU2S6_MX:94.00|VPU2S6_TR:93.50|VPU2S7_MX:95.50|VPU2S7_TR:95.50|VPU2S8_MX:94.50|VPU2S8_TR:94.50|MED3S0_MX:97.0
                                                                                         0|MED3S0_TR:96.50|MED3S1_MX:95.50|MED3S1_TR:95.50|MED3S2_MX:96.50|MED3S2_TR:97.50|MED3S3_MX:97.50|MED3S3_TR:97.50|MED3S4_MX:97.00|MED3S4_TR:95.50|IPU3S5_MX:95.50|IPU3S5_TR:95.50|IPU3S6_MX:94.00|IPU3S6_TR:94.50|IPU3S7_MX:95.50|IPU3S7_TR:96.50|MED3S8_MX:96.50|MED3S8_TR:95.50|HUBA0S0_MX:95.00|HUBA0S0_TR:95.50|HUB
                                                                                         A0S2_MX:95.50|HUBA0S2_TR:95.50|HUBA0S3_MX:95.50|HUBA0S3_TR:96.00|HUBA0S4_MX:95.50|HUBA0S4_TR:96.00|HUBA0S5_MX:97.00|HUBA0S5_TR:94.50|HUBA0S6_MX:94.50|HUBA0S6_TR:95.00|HUBA0S7_MX:95.00|HUBA0S7_TR:95.00|HUBA0S8_MX:92.50|HUBA0S8_TR:94.00|HUBA0S9_MX:95.50|HUBA0S9_TR:93.00|HUBA0S10_MX:93.00|HUBA0S10_TR:96.00|HUBA0S
                                                                                         11_MX:94.50|HUBA0S11_TR:93.50|HUBA0S12_MX:94.50|HUBA0S12_TR:93.50|HUBA0S13_MX:94.50|HUBA0S13_TR:94.00|HUBA0S16_MX:94.50|HUBA0S16_TR:95.50|HUBA0S17_MX:95.50|HUBA0S17_TR:94.00|HUBA0S18_MX:97.50|HUBA0S18_TR:96.50|HUBA0S19_MX:95.00|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR
                                                                                         :94.00|HUBA0S24_MX:95.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:95.50|HUBA0S26_MX:97.50|HUBA0S26_TR:96.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:95.50|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:95.50                                                                                         
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCLPECORE_FMIN_X_ATOM_COMBINED_VMINFWCFG SAAT0@F1:1:1.200                                                                                                                                                                                                                                                                                                       
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL                 0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.811_0.811_0.811_0.811_0.811_0.811_0.811_0.811_0.811|1                                                                                                                                                    
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL_DTS             HUBAON_MX:92.50|HUBAON_TR:91.50|MEM1S0_MX:90.50|MEM1S0_TR:89.50|MEM1S1_MX:90.00|MEM1S1_TR:89.50|MEM1S2_MX:91.00|MEM1S2_TR:90.50|MEM1S3_MX:91.00|MEM1S3_TR:91.00|DIS1S4_MX:89.00|DIS1S4_TR:89.00|DIS1S5_MX:90.50|DIS1S5_TR:89.50|DIS1S6_MX:90.00|DIS1S6_TR:89.50|DIS1S7_MX:89.50|DIS1S7_TR:90.50|MEM1S8_MX:90.00|MEM1S8_
                                                                                         TR:89.50|VPU2S0_MX:90.50|VPU2S0_TR:91.00|VPU2S1_MX:92.00|VPU2S1_TR:90.00|VPU2S2_MX:92.00|VPU2S2_TR:92.00|VPU2S3_MX:92.00|VPU2S3_TR:91.00|VPU2S4_MX:91.50|VPU2S4_TR:91.50|VPU2S5_MX:89.00|VPU2S5_TR:90.00|VPU2S6_MX:92.00|VPU2S6_TR:90.00|VPU2S7_MX:91.00|VPU2S7_TR:91.00|VPU2S8_MX:91.00|VPU2S8_TR:91.00|MED3S0_MX:91.0
                                                                                         0|MED3S0_TR:92.00|MED3S1_MX:90.50|MED3S1_TR:90.50|MED3S2_MX:92.00|MED3S2_TR:92.50|MED3S3_MX:91.50|MED3S3_TR:91.50|MED3S4_MX:92.00|MED3S4_TR:90.50|IPU3S5_MX:91.00|IPU3S5_TR:90.50|IPU3S6_MX:89.50|IPU3S6_TR:89.50|IPU3S7_MX:90.50|IPU3S7_TR:91.50|MED3S8_MX:91.50|MED3S8_TR:91.50|HUBA0S0_MX:91.50|HUBA0S0_TR:91.50|HUB
                                                                                         A0S2_MX:90.50|HUBA0S2_TR:90.50|HUBA0S3_MX:90.50|HUBA0S3_TR:91.00|HUBA0S4_MX:90.50|HUBA0S4_TR:91.00|HUBA0S5_MX:91.00|HUBA0S5_TR:89.50|HUBA0S6_MX:90.50|HUBA0S6_TR:90.50|HUBA0S7_MX:91.00|HUBA0S7_TR:90.00|HUBA0S8_MX:90.00|HUBA0S8_TR:90.50|HUBA0S9_MX:89.00|HUBA0S9_TR:89.50|HUBA0S10_MX:90.50|HUBA0S10_TR:91.00|HUBA0S
                                                                                         11_MX:90.50|HUBA0S11_TR:89.50|HUBA0S12_MX:91.00|HUBA0S12_TR:89.50|HUBA0S13_MX:89.50|HUBA0S13_TR:90.50|HUBA0S16_MX:90.50|HUBA0S16_TR:90.00|HUBA0S17_MX:90.00|HUBA0S17_TR:91.50|HUBA0S18_MX:92.00|HUBA0S18_TR:91.00|HUBA0S19_MX:92.50|HUBA0S19_TR:90.50|HUBA0S20_MX:90.00|HUBA0S20_TR:90.50|HUBA0S21_MX:91.50|HUBA0S21_TR
                                                                                         :91.50|HUBA0S24_MX:90.50|HUBA0S24_TR:91.50|HUBA0S25_MX:91.50|HUBA0S25_TR:91.50|HUBA0S26_MX:92.00|HUBA0S26_TR:91.00|HUBA0S27_MX:92.50|HUBA0S27_TR:91.50|HUBA0S28_MX:91.50|HUBA0S28_TR:90.50|HUBA0S29_MX:91.50|HUBA0S29_TR:91.50                                                                                         
IPH::FUN_HUB_HXPKGMB::FUN_HUB_VMIN_K_FMINXSN_X_VCCSA_FMIN_X_NAPBIST_FULL_VMINFWCFG       SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629

---

## User — Message 20

Try Again

---

## User — Message 21

few corrections: 
1. Aqua ILAS report has 47 Visual_ID where the final csv file include only 2 
2. The final report is stacked, meaning that every unit has a row per domain and freq. whereas I need the final output to be split so it will be easier to merge with the UPSVF vmin results. so each unit will have 1 row and all of the Vmin results depicted with the DTS LP Test instance as columns for the Domain-Freq-Core number 
3. most important issue there is an integrity issue the data is incorrecl for example for  U6XH126700474 SAC 1.4GHz Vmin is 0.57 set by ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X and the csv out put file has vmin of 0.821 set by IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC- validate code and dfinal results

---

### Assistant

I’m going to inspect the parser and aggregation paths against the full probe CSV to reproduce the 47-vs-2 unit mismatch and the wrong Vmin setter mapping, then I’ll patch the script and rerun it on the full local raw file for validation.

---

### Assistant

I found two likely root causes: the AQUA pull is capped at 150k rows (which can easily truncate to 2 units), and the aggregation key currently ignores core index. I’ll patch both, then validate against the full local probe file and your specific SAC example.

---

## User — Message 22

that is not the rootcause, the raw data as pulled from Aqua has all 47 Visual_ID

---

### Assistant

You’re right; the 47 IDs are in the raw source, so truncation isn’t the root cause. I’m now fixing the parser to keep valid single-value Vmin rows (like 0.57) that were previously dropped, which can collapse units and distort setter selection.

---

### Assistant

Next I’ll run the updated script on the full local probe file with a local output folder, then verify summary row count and the specific U6XH126700474 SAC F1.4 mapping from the generated CSV.

---

### Assistant

I’ve applied the parser correction and the full-file validation run is currently processing 964k stacked rows; I’m polling until it finishes so we can confirm the exact unit count and your SAC case from the actual output.

---

### Assistant

I’m switching to a text-level search on the raw CSV for your exact VisualID and VCCSA_F1 patterns so we can verify the expected setter/value quickly without waiting on full CSV deserialization.

---

### Assistant

I found the integrity root cause: for pipe-delimited Vmin payloads, the code was taking max across segments, which inflates SAC F1 values to 0.821/0.800 instead of expected 0.570/0.500 in your examples. I’m changing it to use the first underscore-structured segment as the effective per-core Vmin vector.

---

### Assistant

I’m applying one more integrity refinement: the core key will come from the domain suffix when available (for example SAC0 → core 0) instead of slot position, and equal-Vmin ties will prefer rows that carry LP/DTS context so setter selection is meaningful.

---

### Assistant

Progress update: the SAC integrity example now matches exactly on the subset (SAC0_F1.400_C0 gives 0.57 with ATSPEED_NONR setter and LP present). I’ll now run the corrected script on the full 964,810-row raw file to confirm the final summary includes all 47 VisualIDs.

---

## User — Message 23

[Terminal 42fac80e-204b-44ff-81eb-8b16131e3b76 notification: command completed with exit code 0. The terminal has been cleaned up.]
Terminal output:
PS C:\Projects\NVL\.docs> rg -n "U6XH126700474.*VCCSA_F1.*_VMIN_" "Scripts\_ilas_probe_20260602_153216.csv" | Select-Object -First 30
rg : The term 'rg' is not recognized as the name of a cmdlet, function, script 
file, or operable program. Check the spelling of the name, or if a path was 
included, verify that the path is correct and try again.
At line:1 char:1
+ rg -n "U6XH126700474.*VCCSA_F1.*_VMIN_" "Scripts\_ilas_probe_20260602 ...
+ ~~
    + CategoryInfo          : ObjectNotFound: (rg:String) [], CommandNotFoundE 
   xception
    + FullyQualifiedErrorId : CommandNotFoundException
 
PS C:\Projects\NVL\.docs> Select-String -Path "Scripts\_ilas_probe_20260602_153216.csv" -Pattern "U6XH126700474.*VCCSA_F1.*_VMIN_" | Select-Object -First 30 | ForEach-Object { $_.Line }
PS C:\Projects\NVL\.docs> Select-String -Path "Scripts\_ilas_probe_20260602_153216.csv" -Pattern "U6XH126700474" | Select-Object -First 10 | ForEach-Object { $_.Line }
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_E_ENDCPU_HITO_VCCIA_X_X_L2_TAG_DTS","","","","AON:94.50|CCF0S0:94.50|CCF0S1:94.50|CCF0S2:94.00|CCF0S3:94.50|CCF0S4:94.50|CCF0S5:94.50|CCF0S6:94.00|CCF0S7:93.00|CCF0S8:93.50|CCF0S9:95.00|CCF1S0:95.50|CCF1S1:95.50|CCF1S2:96.00|CCF1S3:95.00|A0S0:97.00|A0S2:97.50|A0S3:97.50|A0S4:98.00|A0S5:97.50|A0S6:97.00|A0S7:95.50|A0S8:95.50|A0S9:97.00|A0S10:97.00|A0S11:96.50|A0S12:96.50|A0S13:97.50|A0S14:97.00|A0S16:97.00|A0S17:99.00|A0S18:97.50|A0S19:98.00|A0S20:98.00|A0S21:98.00|A0S24:96.50|A0S25:94.50|A0S26:96.50|A0S27:96.00|A0S28:95.00|A0S29:96.00|A1S0:97.50|A1S2:98.00|A1S3:98.50|A1S4:98.50|A1S5:98.00|A1S6:97.50|A1S7:98.00|A1S8:96.50|A1S9:97.50|A1S10:97.00|A1S11:97.50|A1S12:97.00|A1S13:98.00|A1S14:97.50|A1S16:98.50|A1S17:98.50|A1S18:99.50|A1S19:99.50|A1S20:100.00|A1S21:99.00|A1S24:96.50|A1S25:95.50|A1S26:96.00|A1S27:97.50|A1S28:96.50|A1S29:97.00|C0S0:95.00|C0S1:95.50|C0S2:95.50|C0S3:94.50|C0S4:95.50|C0S5:95.50|C0S6:95.00|C0S7:94.50|C0S8:94.50|C0S9:95.00|C0S10:95.00|C0S11:95.50|C0S12:95.50|C0S13:94.50|C0S14:94.00|C0S15:95.00|C1S0:94.00|C1S1:94.00|C1S2:93.50|C1S3:93.50|C1S4:94.50|C1S5:95.00|C1S6:94.00|C1S7:95.00|C1S8:94.50|C1S9:93.50|C1S10:93.50|C1S11:94.00|C1S12:95.00|C1S13:93.50|C1S14:93.50|C1S15:94.00|C2S0:95.50|C2S1:95.00|C2S2:95.00|C2S3:95.00|C2S4:94.50|C2S5:95.50|C2S6:94.50|C2S7:95.50|C2S8:95.50|C2S9:94.00|C2S10:94.50|C2S11:94.50|C2S12:95.00|C2S13:95.50|C2S14:95.00|C2S15:95.00|C3S0:94.50|C3S1:94.50|C3S2:94.00|C3S3:94.50|C3S4:94.50|C3S5:94.50|C3S6:94.50|C3S7:95.00|C3S8:94.50|C3S9:94.00|C3S10:95.50|C3S11:94.00|C3S12:95.00|C3S13:94.50|C3S14:94.00|C3S15:94.50","19576","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_COMBINED","","","","0.450_0.450|0.450_0.450|0.800_0.800|1","17577","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_COMBINED_DTS","","","","AON:90.50|CCF0S0:91.00|CCF0S1:90.00|CCF0S2:90.00|CCF0S3:91.00|CCF0S4:91.00|CCF0S5:90.50|CCF0S6:90.00|CCF0S7:89.50|CCF0S8:90.00|CCF0S9:91.00|CCF1S0:89.50|CCF1S1:90.50|CCF1S2:90.00|CCF1S3:89.50|A0S0:91.50|A0S2:92.50|A0S3:91.50|A0S4:92.00|A0S5:92.50|A0S6:92.00|A0S7:91.00|A0S8:91.00|A0S9:91.50|A0S10:92.00|A0S11:91.50|A0S12:91.50|A0S13:92.00|A0S14:92.00|A0S16:91.50|A0S17:92.50|A0S18:92.00|A0S19:92.50|A0S20:92.00|A0S21:92.50|A0S24:92.00|A0S25:91.00|A0S26:92.50|A0S27:91.00|A0S28:90.50|A0S29:91.50|A1S0:90.50|A1S2:90.50|A1S3:91.00|A1S4:91.50|A1S5:91.00|A1S6:91.00|A1S7:91.00|A1S8:90.00|A1S9:91.00|A1S10:91.00|A1S11:91.00|A1S12:90.00|A1S13:91.00|A1S14:91.00|A1S16:91.50|A1S17:90.50|A1S18:91.50|A1S19:92.00|A1S20:92.00|A1S21:92.00|A1S24:90.50|A1S25:90.50|A1S26:90.50|A1S27:91.50|A1S28:91.50|A1S29:91.00|C0S0:89.50|C0S1:91.00|C0S2:90.00|C0S3:90.50|C0S4:91.00|C0S5:91.50|C0S6:90.50|C0S7:91.00|C0S8:91.00|C0S9:90.50|C0S10:90.00|C0S11:91.50|C0S12:91.00|C0S13:90.00|C0S14:91.00|C0S15:90.00|C1S0:90.50|C1S1:90.00|C1S2:90.00|C1S3:90.00|C1S4:90.50|C1S5:91.50|C1S6:90.00|C1S7:91.00|C1S8:90.50|C1S9:90.00|C1S10:90.00|C1S11:90.50|C1S12:91.00|C1S13:90.00|C1S14:89.00|C1S15:90.50|C2S0:92.00|C2S1:91.50|C2S2:91.00|C2S3:91.00|C2S4:91.00|C2S5:91.50|C2S6:91.00|C2S7:92.00|C2S8:90.50|C2S9:90.50|C2S10:90.50|C2S11:90.50|C2S12:91.00|C2S13:92.00|C2S14:91.00|C2S15:91.50|C3S0:90.50|C3S1:90.00|C3S2:90.00|C3S3:90.50|C3S4:90.50|C3S5:90.50|C3S6:90.50|C3S7:90.50|C3S8:90.50|C3S9:90.00|C3S10:91.00|C3S11:89.50|C3S12:91.00|C3S13:90.50|C3S14:89.50|C3S15:90.50","17576","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_COMBINED_IT","","","","0_0","17578","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_COMBINED_VMINFWCFG","","","","AT1@F1:1:1.200_AT0@F1:1:1.200","17579","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_SSA_L2DATA","","","","0.450_0.450|0.450_0.450|0.800_0.800|1","17571","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_SSA_L2DATA_DTS","","","","AON:94.00|CCF0S0:94.00|CCF0S1:93.00|CCF0S2:93.00|CCF0S3:94.00|CCF0S4:93.50|CCF0S5:93.00|CCF0S6:93.00|CCF0S7:92.00|CCF0S8:93.00|CCF0S9:93.50|CCF1S0:93.50|CCF1S1:94.50|CCF1S2:94.00|CCF1S3:94.00|A0S0:95.00|A0S2:95.50|A0S3:94.50|A0S4:95.00|A0S5:95.50|A0S6:95.00|A0S7:94.00|A0S8:94.00|A0S9:94.50|A0S10:95.00|A0S11:94.50|A0S12:95.00|A0S13:95.50|A0S14:95.00|A0S16:95.00|A0S17:95.50|A0S18:95.00|A0S19:95.50|A0S20:94.50|A0S21:96.00|A0S24:94.50|A0S25:94.00|A0S26:95.00|A0S27:94.50|A0S28:93.50|A0S29:94.50|A1S0:94.50|A1S2:94.50|A1S3:95.00|A1S4:95.50|A1S5:95.00|A1S6:94.50|A1S7:95.50|A1S8:94.50|A1S9:94.50|A1S10:94.50|A1S11:95.00|A1S12:94.00|A1S13:95.50|A1S14:95.00|A1S16:95.00|A1S17:95.00|A1S18:96.00|A1S19:96.00|A1S20:96.00|A1S21:96.00|A1S24:94.00|A1S25:94.50|A1S26:94.50|A1S27:95.50|A1S28:95.00|A1S29:95.50|C0S0:94.50|C0S1:95.00|C0S2:95.00|C0S3:94.50|C0S4:95.00|C0S5:95.00|C0S6:95.00|C0S7:94.00|C0S8:94.00|C0S9:95.00|C0S10:94.50|C0S11:95.50|C0S12:95.00|C0S13:94.00|C0S14:94.00|C0S15:95.00|C1S0:93.50|C1S1:93.50|C1S2:93.00|C1S3:93.00|C1S4:94.00|C1S5:94.50|C1S6:93.50|C1S7:94.00|C1S8:94.00|C1S9:93.00|C1S10:93.50|C1S11:93.50|C1S12:94.50|C1S13:93.00|C1S14:92.50|C1S15:93.50|C2S0:95.00|C2S1:94.50|C2S2:94.50|C2S3:94.00|C2S4:94.00|C2S5:94.50|C2S6:94.00|C2S7:95.00|C2S8:95.00|C2S9:93.50|C2S10:94.00|C2S11:94.00|C2S12:94.00|C2S13:95.00|C2S14:94.50|C2S15:94.50|C3S0:93.50|C3S1:93.50|C3S2:93.50|C3S3:94.00|C3S4:94.00|C3S5:94.00|C3S6:93.50|C3S7:94.00|C3S8:94.00|C3S9:93.50|C3S10:94.50|C3S11:93.00|C3S12:94.50|C3S13:93.50|C3S14:93.00|C3S15:93.50","17570","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_SSA_L2DATA_IT","","","","0_0","17572","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F1XAT_HITO_VCCIA_F1_1200_SSA_L2DATA_VMINFWCFG","","","","AT1@F1:1:1.200_AT0@F1:1:1.200","17573","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_F2XAT_HITO_VCCIA_F2_2800_COMBINED","","","","0.640_0.650|0.590_0.600|1.150_1.150|11","19112","","STRING"
PS C:\Projects\NVL\.docs> Select-String -Path "Scripts\_ilas_probe_20260602_153216.csv" -Pattern "U6XH126700474" | Where-Object { $_.Line -like '*VCCSA_F1*' -and $_.Line -like '*_VMIN_K_*' } | Select-Object -First 40 | ForEach-Object { $_.Line }
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_ENDHUB_X_VCCSA_F1_X_ALLTILE","","","","0.700|0.700|0.900|1","19729","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_ENDHUB_X_VCCSA_F1_X_DISP_F2","","","","0.700|0.700|0.900|1","19718","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_ENDHUB_X_VCCSA_F1_X_IPU","","","","0.700|0.700|0.900|1","19721","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_ENDHUB_X_VCCSA_F1_X_MEDIA","","","","0.700|0.700|0.900|1","19724","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_ENDHUB_X_VCCSA_F1_X_NONREC","","","","0.700|0.700|0.900|1","19727","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_ALLTILE","","","","0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|1","18097","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_ALLTILE_DTS","","","","HUBAON_MX:96.00|HUBAON_TR:95.00|MEM1S0_MX:96.00|MEM1S0_TR:93.50|MEM1S1_MX:93.00|MEM1S1_TR:92.00|MEM1S2_MX:95.00|MEM1S2_TR:94.50|MEM1S3_MX:95.00|MEM1S3_TR:94.00|DIS1S4_MX:94.50|DIS1S4_TR:92.00|DIS1S5_MX:94.50|DIS1S5_TR:92.50|DIS1S6_MX:93.00|DIS1S6_TR:92.00|DIS1S7_MX:93.50|DIS1S7_TR:94.50|MEM1S8_MX:94.00|MEM1S8_TR:94.00|VPU2S0_MX:94.00|VPU2S0_TR:94.50|VPU2S1_MX:95.50|VPU2S1_TR:93.50|VPU2S2_MX:94.50|VPU2S2_TR:95.50|VPU2S3_MX:94.50|VPU2S3_TR:93.50|VPU2S4_MX:95.00|VPU2S4_TR:95.00|VPU2S5_MX:92.50|VPU2S5_TR:93.50|VPU2S6_MX:94.00|VPU2S6_TR:93.50|VPU2S7_MX:93.50|VPU2S7_TR:94.50|VPU2S8_MX:94.50|VPU2S8_TR:93.50|MED3S0_MX:95.50|MED3S0_TR:94.50|MED3S1_MX:94.00|MED3S1_TR:94.50|MED3S2_MX:94.50|MED3S2_TR:96.50|MED3S3_MX:96.50|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:95.50|IPU3S5_MX:94.50|IPU3S5_TR:94.50|IPU3S6_MX:94.00|IPU3S6_TR:93.00|IPU3S7_MX:94.50|IPU3S7_TR:95.00|MED3S8_MX:95.00|MED3S8_TR:94.00|HUBA0S0_MX:92.50|HUBA0S0_TR:94.00|HUBA0S2_MX:93.00|HUBA0S2_TR:93.00|HUBA0S3_MX:93.00|HUBA0S3_TR:93.50|HUBA0S4_MX:94.50|HUBA0S4_TR:93.50|HUBA0S5_MX:94.50|HUBA0S5_TR:93.50|HUBA0S6_MX:93.00|HUBA0S6_TR:94.00|HUBA0S7_MX:92.50|HUBA0S7_TR:92.50|HUBA0S8_MX:92.50|HUBA0S8_TR:93.00|HUBA0S9_MX:93.00|HUBA0S9_TR:93.00|HUBA0S10_MX:93.00|HUBA0S10_TR:93.50|HUBA0S11_MX:94.50|HUBA0S11_TR:93.50|HUBA0S12_MX:93.50|HUBA0S12_TR:92.00|HUBA0S13_MX:92.00|HUBA0S13_TR:92.50|HUBA0S16_MX:93.00|HUBA0S16_TR:94.00|HUBA0S17_MX:92.50|HUBA0S17_TR:94.00|HUBA0S18_MX:94.50|HUBA0S18_TR:93.50|HUBA0S19_MX:93.50|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR:94.00|HUBA0S24_MX:93.00|HUBA0S24_TR:95.50|HUBA0S25_MX:94.00|HUBA0S25_TR:94.00|HUBA0S26_MX:94.50|HUBA0S26_TR:93.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:94.00|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:94.00","18096","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_ALLTILE_IT","","","","0","18098","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_ALLTILE_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","18099","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1","19391","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_IT","","","","0","19392","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::SSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_ALLTILE_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","19393","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP","","","","0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.450_0.450_0.450_0.450_0.450_0.450_0.450_0.450_0.450|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|6","18073","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP_DTS","","","","HUBAON_MX:95.00|HUBAON_TR:94.00|MEM1S0_MX:94.50|MEM1S0_TR:92.50|MEM1S1_MX:93.00|MEM1S1_TR:92.00|MEM1S2_MX:95.00|MEM1S2_TR:93.00|MEM1S3_MX:94.00|MEM1S3_TR:94.00|DIS1S4_MX:93.00|DIS1S4_TR:92.00|DIS1S5_MX:93.00|DIS1S5_TR:92.50|DIS1S6_MX:91.50|DIS1S6_TR:90.50|DIS1S7_MX:92.50|DIS1S7_TR:91.50|MEM1S8_MX:92.50|MEM1S8_TR:92.50|VPU2S0_MX:92.50|VPU2S0_TR:93.50|VPU2S1_MX:94.00|VPU2S1_TR:92.00|VPU2S2_MX:94.50|VPU2S2_TR:94.50|VPU2S3_MX:94.50|VPU2S3_TR:93.50|VPU2S4_MX:94.00|VPU2S4_TR:93.00|VPU2S5_MX:91.50|VPU2S5_TR:91.00|VPU2S6_MX:93.00|VPU2S6_TR:92.00|VPU2S7_MX:92.00|VPU2S7_TR:93.50|VPU2S8_MX:92.00|VPU2S8_TR:91.00|MED3S0_MX:94.50|MED3S0_TR:94.50|MED3S1_MX:93.00|MED3S1_TR:93.00|MED3S2_MX:94.50|MED3S2_TR:95.00|MED3S3_MX:94.00|MED3S3_TR:94.00|MED3S4_MX:94.50|MED3S4_TR:93.00|IPU3S5_MX:93.50|IPU3S5_TR:93.00|IPU3S6_MX:93.00|IPU3S6_TR:92.00|IPU3S7_MX:93.00|IPU3S7_TR:94.00|MED3S8_MX:94.00|MED3S8_TR:93.00|HUBA0S0_MX:92.50|HUBA0S0_TR:93.00|HUBA0S2_MX:93.00|HUBA0S2_TR:93.00|HUBA0S3_MX:92.00|HUBA0S3_TR:93.50|HUBA0S4_MX:93.00|HUBA0S4_TR:93.50|HUBA0S5_MX:93.50|HUBA0S5_TR:92.00|HUBA0S6_MX:93.00|HUBA0S6_TR:92.50|HUBA0S7_MX:92.50|HUBA0S7_TR:91.00|HUBA0S8_MX:91.50|HUBA0S8_TR:91.50|HUBA0S9_MX:91.50|HUBA0S9_TR:92.00|HUBA0S10_MX:92.00|HUBA0S10_TR:92.00|HUBA0S11_MX:93.00|HUBA0S11_TR:92.00|HUBA0S12_MX:92.00|HUBA0S12_TR:91.00|HUBA0S13_MX:90.50|HUBA0S13_TR:91.50|HUBA0S16_MX:93.00|HUBA0S16_TR:92.50|HUBA0S17_MX:92.50|HUBA0S17_TR:91.50|HUBA0S18_MX:92.00|HUBA0S18_TR:93.50|HUBA0S19_MX:92.50|HUBA0S19_TR:91.50|HUBA0S20_MX:91.50|HUBA0S20_TR:92.00|HUBA0S21_MX:91.50|HUBA0S21_TR:91.50|HUBA0S24_MX:93.00|HUBA0S24_TR:92.50|HUBA0S25_MX:92.50|HUBA0S25_TR:92.50|HUBA0S26_MX:94.50|HUBA0S26_TR:93.50|HUBA0S27_MX:92.50|HUBA0S27_TR:91.50|HUBA0S28_MX:92.50|HUBA0S28_TR:93.50|HUBA0S29_MX:93.00|HUBA0S29_TR:92.50","18072","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP_IT","","","","5","18075","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP_LP","","","","0020654^0020654^0020654^0020654^0020654^0020654^0020654^0020654^0020654","18074","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP_SCRB","","","","423090000001,423090020596,423090045982,423090046001,423090020654,423090046047,423090020607,423090020608,423090020609,423090020610,423090020611,423090020612,423090045993,423090045994,423090045995,423099999999","18071","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_DISP_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","18076","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_IPU","","","","0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|1","18080","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_IPU_DTS","","","","HUBAON_MX:95.00|HUBAON_TR:94.00|MEM1S0_MX:94.50|MEM1S0_TR:92.50|MEM1S1_MX:93.00|MEM1S1_TR:92.00|MEM1S2_MX:93.50|MEM1S2_TR:94.50|MEM1S3_MX:94.00|MEM1S3_TR:94.00|DIS1S4_MX:93.00|DIS1S4_TR:92.00|DIS1S5_MX:93.00|DIS1S5_TR:92.50|DIS1S6_MX:91.50|DIS1S6_TR:90.50|DIS1S7_MX:92.50|DIS1S7_TR:91.50|MEM1S8_MX:92.50|MEM1S8_TR:91.00|VPU2S0_MX:94.00|VPU2S0_TR:93.50|VPU2S1_MX:94.00|VPU2S1_TR:92.00|VPU2S2_MX:94.50|VPU2S2_TR:94.50|VPU2S3_MX:94.50|VPU2S3_TR:93.50|VPU2S4_MX:95.00|VPU2S4_TR:93.00|VPU2S5_MX:91.50|VPU2S5_TR:91.00|VPU2S6_MX:93.00|VPU2S6_TR:92.00|VPU2S7_MX:92.00|VPU2S7_TR:93.50|VPU2S8_MX:93.00|VPU2S8_TR:92.00|MED3S0_MX:94.50|MED3S0_TR:94.50|MED3S1_MX:94.00|MED3S1_TR:93.00|MED3S2_MX:94.50|MED3S2_TR:96.50|MED3S3_MX:96.50|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:94.50|IPU3S5_MX:93.50|IPU3S5_TR:93.00|IPU3S6_MX:93.00|IPU3S6_TR:92.00|IPU3S7_MX:93.00|IPU3S7_TR:95.00|MED3S8_MX:95.00|MED3S8_TR:94.00|HUBA0S0_MX:92.50|HUBA0S0_TR:93.00|HUBA0S2_MX:93.00|HUBA0S2_TR:93.00|HUBA0S3_MX:93.00|HUBA0S3_TR:93.50|HUBA0S4_MX:93.00|HUBA0S4_TR:93.50|HUBA0S5_MX:93.50|HUBA0S5_TR:92.00|HUBA0S6_MX:93.00|HUBA0S6_TR:92.50|HUBA0S7_MX:92.50|HUBA0S7_TR:92.50|HUBA0S8_MX:92.50|HUBA0S8_TR:93.00|HUBA0S9_MX:93.00|HUBA0S9_TR:92.00|HUBA0S10_MX:92.00|HUBA0S10_TR:92.00|HUBA0S11_MX:93.00|HUBA0S11_TR:92.00|HUBA0S12_MX:92.00|HUBA0S12_TR:92.00|HUBA0S13_MX:92.00|HUBA0S13_TR:91.50|HUBA0S16_MX:93.00|HUBA0S16_TR:92.50|HUBA0S17_MX:92.50|HUBA0S17_TR:92.50|HUBA0S18_MX:94.50|HUBA0S18_TR:93.50|HUBA0S19_MX:92.50|HUBA0S19_TR:91.50|HUBA0S20_MX:91.50|HUBA0S20_TR:92.00|HUBA0S21_MX:91.50|HUBA0S21_TR:91.50|HUBA0S24_MX:93.00|HUBA0S24_TR:92.50|HUBA0S25_MX:92.50|HUBA0S25_TR:94.00|HUBA0S26_MX:94.50|HUBA0S26_TR:93.50|HUBA0S27_MX:93.50|HUBA0S27_TR:93.00|HUBA0S28_MX:94.00|HUBA0S28_TR:93.50|HUBA0S29_MX:93.00|HUBA0S29_TR:94.00","18079","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_IPU_IT","","","","0","18081","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_IPU_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","18082","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_MEDIA","","","","0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|1","18086","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_MEDIA_DTS","","","","HUBAON_MX:95.00|HUBAON_TR:94.00|MEM1S0_MX:94.50|MEM1S0_TR:92.50|MEM1S1_MX:93.00|MEM1S1_TR:92.00|MEM1S2_MX:93.50|MEM1S2_TR:94.50|MEM1S3_MX:94.00|MEM1S3_TR:94.00|DIS1S4_MX:93.00|DIS1S4_TR:92.00|DIS1S5_MX:93.00|DIS1S5_TR:92.50|DIS1S6_MX:93.00|DIS1S6_TR:90.50|DIS1S7_MX:92.50|DIS1S7_TR:91.50|MEM1S8_MX:92.50|MEM1S8_TR:92.50|VPU2S0_MX:94.00|VPU2S0_TR:93.50|VPU2S1_MX:95.50|VPU2S1_TR:93.50|VPU2S2_MX:94.50|VPU2S2_TR:94.50|VPU2S3_MX:94.50|VPU2S3_TR:93.50|VPU2S4_MX:94.00|VPU2S4_TR:94.00|VPU2S5_MX:92.50|VPU2S5_TR:93.50|VPU2S6_MX:94.00|VPU2S6_TR:92.00|VPU2S7_MX:93.50|VPU2S7_TR:93.50|VPU2S8_MX:93.00|VPU2S8_TR:93.50|MED3S0_MX:95.50|MED3S0_TR:94.50|MED3S1_MX:94.00|MED3S1_TR:94.50|MED3S2_MX:94.50|MED3S2_TR:96.50|MED3S3_MX:95.00|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:93.00|IPU3S5_MX:93.50|IPU3S5_TR:94.50|IPU3S6_MX:93.00|IPU3S6_TR:92.00|IPU3S7_MX:94.50|IPU3S7_TR:95.00|MED3S8_MX:94.00|MED3S8_TR:93.00|HUBA0S0_MX:92.50|HUBA0S0_TR:93.00|HUBA0S2_MX:93.00|HUBA0S2_TR:93.00|HUBA0S3_MX:93.00|HUBA0S3_TR:93.50|HUBA0S4_MX:93.00|HUBA0S4_TR:93.50|HUBA0S5_MX:93.50|HUBA0S5_TR:93.50|HUBA0S6_MX:93.00|HUBA0S6_TR:92.50|HUBA0S7_MX:92.50|HUBA0S7_TR:92.50|HUBA0S8_MX:92.50|HUBA0S8_TR:93.00|HUBA0S9_MX:93.00|HUBA0S9_TR:90.50|HUBA0S10_MX:92.00|HUBA0S10_TR:93.50|HUBA0S11_MX:93.00|HUBA0S11_TR:92.00|HUBA0S12_MX:92.00|HUBA0S12_TR:92.00|HUBA0S13_MX:92.00|HUBA0S13_TR:91.50|HUBA0S16_MX:93.00|HUBA0S16_TR:92.50|HUBA0S17_MX:92.50|HUBA0S17_TR:91.50|HUBA0S18_MX:92.00|HUBA0S18_TR:93.50|HUBA0S19_MX:92.50|HUBA0S19_TR:91.50|HUBA0S20_MX:91.50|HUBA0S20_TR:92.00|HUBA0S21_MX:93.00|HUBA0S21_TR:92.50|HUBA0S24_MX:93.00|HUBA0S24_TR:92.50|HUBA0S25_MX:92.50|HUBA0S25_TR:94.00|HUBA0S26_MX:94.50|HUBA0S26_TR:93.50|HUBA0S27_MX:93.50|HUBA0S27_TR:93.00|HUBA0S28_MX:94.00|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:94.00","18085","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_MEDIA_IT","","","","0","18087","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_MEDIA_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","18088","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_NONREC","","","","0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|1","18092","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_NONREC_DTS","","","","HUBAON_MX:96.00|HUBAON_TR:95.00|MEM1S0_MX:96.00|MEM1S0_TR:95.00|MEM1S1_MX:94.00|MEM1S1_TR:93.50|MEM1S2_MX:95.00|MEM1S2_TR:94.50|MEM1S3_MX:95.00|MEM1S3_TR:94.00|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:94.50|DIS1S5_TR:92.50|DIS1S6_MX:93.00|DIS1S6_TR:92.00|DIS1S7_MX:93.50|DIS1S7_TR:91.50|MEM1S8_MX:94.00|MEM1S8_TR:94.00|VPU2S0_MX:94.00|VPU2S0_TR:94.50|VPU2S1_MX:95.50|VPU2S1_TR:93.50|VPU2S2_MX:95.50|VPU2S2_TR:95.50|VPU2S3_MX:94.50|VPU2S3_TR:94.50|VPU2S4_MX:95.00|VPU2S4_TR:94.00|VPU2S5_MX:94.00|VPU2S5_TR:93.50|VPU2S6_MX:94.00|VPU2S6_TR:92.00|VPU2S7_MX:94.50|VPU2S7_TR:94.50|VPU2S8_MX:94.50|VPU2S8_TR:92.00|MED3S0_MX:95.50|MED3S0_TR:95.50|MED3S1_MX:95.50|MED3S1_TR:94.50|MED3S2_MX:95.50|MED3S2_TR:96.50|MED3S3_MX:96.50|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:95.50|IPU3S5_MX:94.50|IPU3S5_TR:94.50|IPU3S6_MX:93.00|IPU3S6_TR:93.00|IPU3S7_MX:94.50|IPU3S7_TR:95.00|MED3S8_MX:95.00|MED3S8_TR:94.00|HUBA0S0_MX:94.00|HUBA0S0_TR:94.00|HUBA0S2_MX:94.00|HUBA0S2_TR:93.00|HUBA0S3_MX:93.00|HUBA0S3_TR:94.50|HUBA0S4_MX:94.50|HUBA0S4_TR:93.50|HUBA0S5_MX:94.50|HUBA0S5_TR:93.50|HUBA0S6_MX:93.00|HUBA0S6_TR:94.00|HUBA0S7_MX:93.50|HUBA0S7_TR:92.50|HUBA0S8_MX:92.50|HUBA0S8_TR:93.00|HUBA0S9_MX:93.00|HUBA0S9_TR:92.00|HUBA0S10_MX:92.00|HUBA0S10_TR:93.50|HUBA0S11_MX:93.00|HUBA0S11_TR:92.00|HUBA0S12_MX:93.50|HUBA0S12_TR:92.00|HUBA0S13_MX:92.00|HUBA0S13_TR:92.50|HUBA0S16_MX:93.00|HUBA0S16_TR:92.50|HUBA0S17_MX:92.50|HUBA0S17_TR:94.00|HUBA0S18_MX:94.50|HUBA0S18_TR:93.50|HUBA0S19_MX:92.50|HUBA0S19_TR:91.50|HUBA0S20_MX:92.50|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR:94.00|HUBA0S24_MX:94.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:94.00|HUBA0S26_MX:94.50|HUBA0S26_TR:93.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:94.00|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:94.00","18091","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_NONREC_IT","","","","0","18093","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_F1XSN_X_VCCSA_F1_X_NONREC_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","18094","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1","19372","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_IT","","","","0","19373","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_DISP_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","19374","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1","19377","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_IT","","","","0","19378","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_IPU_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","19379","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1","19382","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_IT","","","","0","19383","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_MEDIA_VMINFWCFG","","","","SAC0@F1:1:1.400_SACD0@F1:1:0.403_SADPU0@F1:1:1.100_SAIOC0@F1:1:0.500_SAME0@F1:1:0.450_SAN0@F1:1:0.600_SAPS0@F1:1:0.500_SAQ0@F1:1:1.400_SAVPU0@F1:1:0.629","19384","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F1_X_NONREC","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821_0.821|1","19387","","STRING"
PS C:\Projects\NVL\.docs> Select-String -Path "Scripts\_ilas_probe_20260602_153216.csv" -Pattern "U6XH126700474" | Where-Object { $_.Line -like '*ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X*' } | Select-Object -First 20 | ForEach-Object { $_.Line }
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|8","18104","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_DTS","","","","HUBAON_MX:96.00|HUBAON_TR:95.00|MEM1S0_MX:96.00|MEM1S0_TR:95.00|MEM1S1_MX:94.00|MEM1S1_TR:93.50|MEM1S2_MX:95.00|MEM1S2_TR:94.50|MEM1S3_MX:95.00|MEM1S3_TR:95.00|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DIS1S5_TR:95.00|DIS1S6_MX:94.00|DIS1S6_TR:93.50|DIS1S7_MX:95.00|DIS1S7_TR:94.50|MEM1S8_MX:95.00|MEM1S8_TR:94.00|VPU2S0_MX:95.00|VPU2S0_TR:96.00|VPU2S1_MX:96.50|VPU2S1_TR:94.50|VPU2S2_MX:95.50|VPU2S2_TR:97.00|VPU2S3_MX:95.50|VPU2S3_TR:94.50|VPU2S4_MX:96.50|VPU2S4_TR:96.50|VPU2S5_MX:95.00|VPU2S5_TR:94.50|VPU2S6_MX:95.50|VPU2S6_TR:93.50|VPU2S7_MX:95.50|VPU2S7_TR:95.50|VPU2S8_MX:95.50|VPU2S8_TR:94.50|MED3S0_MX:95.50|MED3S0_TR:95.50|MED3S1_MX:94.00|MED3S1_TR:94.50|MED3S2_MX:95.50|MED3S2_TR:96.50|MED3S3_MX:96.50|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:95.50|IPU3S5_MX:95.50|IPU3S5_TR:95.50|IPU3S6_MX:94.00|IPU3S6_TR:94.50|IPU3S7_MX:95.50|IPU3S7_TR:96.50|MED3S8_MX:95.00|MED3S8_TR:95.50|HUBA0S0_MX:95.00|HUBA0S0_TR:95.50|HUBA0S2_MX:94.00|HUBA0S2_TR:94.50|HUBA0S3_MX:94.50|HUBA0S3_TR:94.50|HUBA0S4_MX:95.50|HUBA0S4_TR:94.50|HUBA0S5_MX:96.00|HUBA0S5_TR:94.50|HUBA0S6_MX:94.50|HUBA0S6_TR:95.00|HUBA0S7_MX:95.00|HUBA0S7_TR:95.00|HUBA0S8_MX:95.00|HUBA0S8_TR:95.50|HUBA0S9_MX:94.00|HUBA0S9_TR:94.50|HUBA0S10_MX:93.00|HUBA0S10_TR:94.50|HUBA0S11_MX:94.50|HUBA0S11_TR:93.50|HUBA0S12_MX:94.50|HUBA0S12_TR:93.50|HUBA0S13_MX:93.00|HUBA0S13_TR:94.00|HUBA0S16_MX:94.50|HUBA0S16_TR:95.50|HUBA0S17_MX:95.50|HUBA0S17_TR:94.00|HUBA0S18_MX:94.50|HUBA0S18_TR:93.50|HUBA0S19_MX:95.00|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR:94.00|HUBA0S24_MX:95.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:94.00|HUBA0S26_MX:96.00|HUBA0S26_TR:96.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:94.00|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:94.00","18103","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_LP","","","","0105049^0105049^0105049^0105049^0105049^0105049^0105049^0105049^0105049","18105","","STRING"
"U6XH126700474","U1.U4","D513862","798","-15","11","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_VMINFWCFG","","","","SAQ0@F1:1:1.400_SAC0@F1:1:1.400_SAN0@F1:1:0.600_SACD0@F1:1:0.403_SAVPU0@F1:1:0.629_SAME0@F1:1:0.450_SAIOC0@F1:1:0.500_SAPS0@F1:1:0.500_SADPU0@F1:1:1.100","18106","","STRING"
"U6XH126700474","U1.U5","Q533P4A","810","6","8","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X","","","","0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570_0.570|0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500_0.500|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|8","18104","","STRING"
"U6XH126700474","U1.U5","Q533P4A","810","6","8","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_DTS","","","","HUBAON_MX:96.00|HUBAON_TR:95.00|MEM1S0_MX:96.00|MEM1S0_TR:95.00|MEM1S1_MX:94.00|MEM1S1_TR:93.50|MEM1S2_MX:95.00|MEM1S2_TR:94.50|MEM1S3_MX:95.00|MEM1S3_TR:95.00|DIS1S4_MX:94.50|DIS1S4_TR:94.50|DIS1S5_MX:96.00|DIS1S5_TR:95.00|DIS1S6_MX:94.00|DIS1S6_TR:93.50|DIS1S7_MX:95.00|DIS1S7_TR:94.50|MEM1S8_MX:95.00|MEM1S8_TR:94.00|VPU2S0_MX:95.00|VPU2S0_TR:96.00|VPU2S1_MX:96.50|VPU2S1_TR:94.50|VPU2S2_MX:95.50|VPU2S2_TR:97.00|VPU2S3_MX:95.50|VPU2S3_TR:94.50|VPU2S4_MX:96.50|VPU2S4_TR:96.50|VPU2S5_MX:95.00|VPU2S5_TR:94.50|VPU2S6_MX:95.50|VPU2S6_TR:93.50|VPU2S7_MX:95.50|VPU2S7_TR:95.50|VPU2S8_MX:95.50|VPU2S8_TR:94.50|MED3S0_MX:95.50|MED3S0_TR:95.50|MED3S1_MX:94.00|MED3S1_TR:94.50|MED3S2_MX:95.50|MED3S2_TR:96.50|MED3S3_MX:96.50|MED3S3_TR:95.50|MED3S4_MX:95.50|MED3S4_TR:95.50|IPU3S5_MX:95.50|IPU3S5_TR:95.50|IPU3S6_MX:94.00|IPU3S6_TR:94.50|IPU3S7_MX:95.50|IPU3S7_TR:96.50|MED3S8_MX:95.00|MED3S8_TR:95.50|HUBA0S0_MX:95.00|HUBA0S0_TR:95.50|HUBA0S2_MX:94.00|HUBA0S2_TR:94.50|HUBA0S3_MX:94.50|HUBA0S3_TR:94.50|HUBA0S4_MX:95.50|HUBA0S4_TR:94.50|HUBA0S5_MX:96.00|HUBA0S5_TR:94.50|HUBA0S6_MX:94.50|HUBA0S6_TR:95.00|HUBA0S7_MX:95.00|HUBA0S7_TR:95.00|HUBA0S8_MX:95.00|HUBA0S8_TR:95.50|HUBA0S9_MX:94.00|HUBA0S9_TR:94.50|HUBA0S10_MX:93.00|HUBA0S10_TR:94.50|HUBA0S11_MX:94.50|HUBA0S11_TR:93.50|HUBA0S12_MX:94.50|HUBA0S12_TR:93.50|HUBA0S13_MX:93.00|HUBA0S13_TR:94.00|HUBA0S16_MX:94.50|HUBA0S16_TR:95.50|HUBA0S17_MX:95.50|HUBA0S17_TR:94.00|HUBA0S18_MX:94.50|HUBA0S18_TR:93.50|HUBA0S19_MX:95.00|HUBA0S19_TR:94.50|HUBA0S20_MX:94.00|HUBA0S20_TR:94.50|HUBA0S21_MX:94.50|HUBA0S21_TR:94.00|HUBA0S24_MX:95.50|HUBA0S24_TR:95.50|HUBA0S25_MX:95.50|HUBA0S25_TR:94.00|HUBA0S26_MX:96.00|HUBA0S26_TR:96.50|HUBA0S27_MX:95.00|HUBA0S27_TR:94.50|HUBA0S28_MX:94.00|HUBA0S28_TR:94.50|HUBA0S29_MX:94.50|HUBA0S29_TR:94.00","18103","","STRING"
"U6XH126700474","U1.U5","Q533P4A","810","6","8","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_LP","","","","0105049^0105049^0105049^0105049^0105049^0105049^0105049^0105049^0105049","18105","","STRING"
"U6XH126700474","U1.U5","Q533P4A","810","6","8","Y6220110","6248_CLASSHOT","Y6220110","NVLHM66A0H30M00S622","100","1","IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_VMINFWCFG","","","","SAQ0@F1:1:1.400_SAC0@F1:1:1.400_SAN0@F1:1:0.600_SACD0@F1:1:0.403_SAVPU0@F1:1:0.629_SAME0@F1:1:0.450_SAIOC0@F1:1:0.500_SAPS0@F1:1:0.500_SADPU0@F1:1:1.100","18106","","STRING"
PS C:\Projects\NVL\.docs> $out="C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate"; .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_subset_20000.csv" -LotsOverride "Y6220110" -OutputDirectory $out
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_subset_20000.csv
Loaded 20000 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 7074 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
Units       : 2
Domain/Freq : 72
Detail rows : 7074
PS C:\Projects\NVL\.docs> $sum='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv'; $r=Import-Csv -LiteralPath $sum | Where-Object { $_.VisualID -eq 'U6XH126700474' }; if ($null -eq $r) { 'RowNotFound' } else { $r.PSObject.Properties | Where-Object { $_.Name -like 'SAC0_F1_4*' -or $_.Name -like 'SAC0_F1_400*' } | Select-Object Name,Value | Sort-Object Name | Format-Table -AutoSize | Out-String }

Name                    Value                                                  
----                    -----                                                  
SAC0_F1_400_C0_LP                                                              
SAC0_F1_400_C0_MaxDTS_C                                                        
SAC0_F1_400_C0_Setter   IPH::ARR_HUB_HXNVL::XSA_HUB_VMIN_K_FMINXSN_X_VCCSA_F...
SAC0_F1_400_C0_Vmin     0.57                                                   
SAC0_F1_400_C1_LP                                                              
SAC0_F1_400_C1_MaxDTS_C 97.5                                                   
SAC0_F1_400_C1_Setter   IPH::SCN_HUB_HXX::ATSPEED_IPU_VMIN_K_F1XSN_X_VCCSA_F1_X
SAC0_F1_400_C1_Vmin     0.57                                                   



PS C:\Projects\NVL\.docs> $out="C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate"; .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_subset_20000.csv" -LotsOverride "Y6220110" -OutputDirectory $out
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_subset_20000.csv
Loaded 20000 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 7074 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
Units       : 2
Domain/Freq : 54
Detail rows : 7074
PS C:\Projects\NVL\.docs> $sum='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv'; $r=Import-Csv -LiteralPath $sum | Where-Object { $_.VisualID -eq 'U6XH126700474' }; $r.PSObject.Properties | Where-Object { $_.Name -like 'SAC0_F1_400*' } | Select-Object Name,Value | Sort-Object Name | Format-Table -AutoSize | Out-String

Name                    Value                                                  
----                    -----                                                  
SAC0_F1_400_C0_LP       0105049^0105049^0105049^0105049^0105049^0105049^0105...
SAC0_F1_400_C0_MaxDTS_C 97                                                     
SAC0_F1_400_C0_Setter   IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_...
SAC0_F1_400_C0_Vmin     0.57                                                   



PS C:\Projects\NVL\.docs> $out="C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate"; .\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1 -RawInputFile "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv" -LotsOverride "Y6220110" -OutputDirectory $out
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 172340 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
Units       : 47
Domain/Freq : 58
Detail rows : 172340

---

### Assistant

You are correct, and the final validation now confirms your point.

Implemented corrections are in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1):

1. Fixed integrity logic for pipe-delimited Vmin values  
- Old behavior: took max across pipe segments, which inflated values like 0.570 to 0.821.  
- New behavior: uses the first underscore-form segment as the effective per-core Vmin vector.

2. Fixed missing-unit collapse behavior  
- Old behavior dropped valid single numeric Vmin payloads.  
- New behavior accepts single numeric Vmin (for single-core form), so valid rows are no longer lost.

3. Fixed core identity and output shape  
- Output key now includes Domain + Freq + Core.  
- Core is derived from domain suffix when present (example SAC0 → core 0), fallback to slot only when needed.  
- Summary stays one row per VisualID, with columns in the format Domain_FFreq_CCore_Vmin, plus Setter, MaxDTS_C, LP.

4. Fixed tie behavior for equal Vmin  
- For equal Vmin, the selected setter now prefers rows with LP, then rows with DTS, to keep limiter context.

5. AQUA pull behavior
- Timeout default increased and polling relaxed.
- Data sampling is now optional (AquaMaxRows=0 means no sampling cap argument is sent).

Validation results:

- Full raw file run completed successfully from [Scripts/_ilas_probe_20260602_153216.csv](Scripts/_ilas_probe_20260602_153216.csv)
- Produced:
  - [Scripts/_tmp_ilas_validate/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv)
  - [Scripts/_tmp_ilas_validate/ILAS_Vmin_Summary_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate/ILAS_Vmin_Summary_Y6220110_WW23_2026.csv)
- Final stats from script:
  - Units: 47
  - Domain/Freq: 58
  - Detail rows: 172340

Specific integrity example now matches your expectation:
- For VisualID U6XH126700474, SAC 1.4:
  - SAC0_F1_400_C0_Vmin = 0.57
  - SAC0_F1_400_C0_Setter = ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X
  - LP is populated for that selected setter path

If you want, I can now add a strict audit export that prints, for each selected summary cell, all candidate setters seen before tie-break so you can trace every chosen winner.

---

## User — Message 24

supply the correct final CSV output so I can validate manually

---

### Assistant

I will verify the final full-run CSV exists and then place a clearly named copy under Scripts so you can open and validate it directly.

---

### Assistant

Final CSV for manual validation is ready here:

- [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION.csv)

Verification:
- Rows: 47 (matches 47 Visual_ID)
- Size: 296,179 bytes

If you also want the expanded per-test detail file for cross-checking setters/LP/DTS, use:
- [Scripts/_tmp_ilas_validate/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv)

---

## User — Message 25

results are incorrect. ecco back all of my request, describe step by step the analysis I required and how to acheive it. I see in the results that tests that does not have _VMIN_ in thier name are still included. like "IPP::CLK_ISCLK_PXH::ALLPLL_PXH_CTVDECODERSPM_E_STARTANA1PCD_X_X_VMIN_X_X_FILTER|RELOCK|RO_FCAL_PASS"

---

### Assistant

I’m going to re-open the ILAS script and quickly trace where test-name filtering is applied, then I’ll patch it so only true _VMIN_ test families are accepted and provide you a clear step-by-step analysis workflow matching your original request.I’ll locate the exact filter logic now and confirm why that test name passes today, then I’ll implement a stricter rule and regenerate outputs.

---

### Assistant

I confirmed the current rule is broad (`*_VMIN_*`), so that example will pass; next I’ll verify it appears in the produced detail CSV and then tighten the matcher to the exact VMIN test pattern you intended.

---

### Assistant

I found the root cause: those rows are being treated as Vmin because the filter only checks for `_VMIN_`, and numeric PASS payloads like `111` are parsed as Vmin. I’ll now harden the parser in two places: require true VMIN metadata (`_VMINFWCFG`) and enforce a valid Vmin voltage range so these diagnostic/pass counters are excluded.

---

### Assistant

I’ve patched the filter logic; next I’ll rerun the script on the same raw input and validate two checks: your example test is gone, and the known SAC 1.4GHz value still resolves correctly.

---

## User — Message 26

before retrying, lets make sure all of my requests are understood. describe my request- goal, steps to acheive it, final outcome and final table description. make sure to explain cleaning steps and nuances, like physical Core numbering.

---

### Assistant

Goal you asked for
1. Build a trustworthy ILAS Vmin final CSV from AQUA stacked data.
2. Keep all 47 Visual_ID units, one row per unit.
3. Put Vmin results into columns by Domain + Frequency + physical Core.
4. Preserve integrity: the selected setter/test for each cell must match the true maximum Vmin for that exact unit/domain/freq/core.
5. Exclude non-relevant tests, especially rows that are not true Vmin measurement rows even if the name contains VMIN text.

Step-by-step analysis you requested
1. Load source data
2. Detect stacked schema using Visual ID, TEST_NAME, TEST_RESULT.
3. Build companion-row groups per unit and base test:
   1. Base Vmin row
   2. _VMINFWCFG row for domain/frequency mapping
   3. _DTS row
   4. _LP row
   5. Ignore _IT metadata rows
4. Apply strict cleaning before producing detail records:
   1. Keep only tests in the Vmin family (not generic counters/status tests).
   2. Require _VMINFWCFG companion metadata to exist, otherwise drop.
   3. Parse Vmin payload correctly:
      1. Single numeric allowed when in valid voltage range.
      2. For pipe payloads, use first underscore vector as effective per-core Vmin.
      3. Do not use max across pipe segments (that caused integrity pollution).
   4. Enforce valid Vmin range to remove PASS/counter values masquerading as Vmin.
5. Derive physical core numbering nuance:
   1. Primary source: numeric suffix in mapped domain (example CR0, CR1).
   2. Fallback: vector slot index when domain suffix is missing.
   3. Keep this core index in both aggregation key and final columns.
6. Aggregate to final chosen value per exact key:
   1. Key = VisualID + Domain + Freq + CoreIndex
   2. Choose highest Vmin
   3. Tie-break on equal Vmin: prefer record with LP, then with DTS
7. Pivot to wide final table:
   1. One row per VisualID
   2. Columns per Domain_Freq_Core for Vmin, Setter, MaxDTS_C, LP
8. Validate integrity with spot checks:
   1. Unit count = 47
   2. Specific known case (SAC 1.4GHz) resolves to expected value/setter
   3. Confirm excluded unwanted test family no longer appears

Final outcome definition
1. A corrected detail CSV containing only cleaned, valid per-core Vmin records.
2. A corrected summary CSV with one row per VisualID and complete wide columns.
3. No false inclusion from non-measurement tests like status/filter/pass counter rows.
4. Preserved traceability through Setter, LP, and MaxDTS_C fields per cell.

Final table description (what each row/column means)
1. Row grain:
   1. One physical unit per row (VisualID).
2. Column families per measurement point:
   1. Domain_F{freq}_C{core}_Vmin: selected max Vmin for that exact unit/domain/freq/core.
   2. Domain_F{freq}_C{core}_Setter: test name that produced selected Vmin.
   3. Domain_F{freq}_C{core}_MaxDTS_C: max temperature context from DTS companion row.
   4. Domain_F{freq}_C{core}_LP: limiter pattern from LP companion row.
3. Physical core nuance:
   1. C value is intended to represent physical core identity, not just vector position.
   2. If domain names encode core (CR0/CR1 etc.), that number is used as authoritative.

Cleaning nuances explicitly acknowledged
1. Name-based filtering alone is insufficient.
2. Companion metadata presence (_VMINFWCFG) is required to classify true Vmin measurement records.
3. Pipe payload semantics must respect primary vector segment, not global max.
4. Voltage range validation is needed to reject numeric counters such as 111/136 that are not voltages.
5. Core identity must stay in keys to prevent cross-core mixing.

If this matches your intent exactly, next step is to rerun with the tightened cleaning and give you the new validation CSV paths plus a before/after exclusion proof for the specific test name you flagged.

---

## User — Message 27

for 4

---

### Assistant

4 = strict cleaning stage. Here is exactly what it means and how to do it.

1. Keep only true Vmin measurement families
1. Accept only rows that belong to a base test which has a matching _VMINFWCFG companion row.
2. Why: name-only matching (contains VMIN) lets in status/filter checks that are not voltage measurements.

2. Drop incomplete groups before value parsing
1. Group by VisualID + base test name.
2. Require:
3. Base value row present.
4. _VMINFWCFG present and parseable into domain/frequency entries.
5. If _VMINFWCFG is missing or invalid, discard the whole group.

3. Parse Vmin payload with correct semantics
1. Single numeric payload:
2. Keep only if it is in valid voltage range (example 0.2 to 2.0 V).
3. Pipe payload (a|b|c):
4. Use the first underscore-style vector segment as the effective per-core Vmin vector.
5. Do not take max across all segments.

4. Enforce physical plausibility filter
1. After parsing each per-core value, keep only values inside MinValidVmin..MaxValidVmin.
2. This removes numeric counters like 111, 136, etc. that come from non-Vmin logic.

5. Attach metadata only after value is valid
1. Map each kept per-core Vmin to its domain/frequency slot from _VMINFWCFG.
2. Attach optional _DTS and _LP context.
3. Derive physical core index:
4. Prefer numeric suffix from domain (CR0, CR1, etc.).
5. Fallback to slot index only if no domain suffix exists.

6. Output of step 4
1. A clean detail record set where every row is a valid Vmin measurement point:
2. Grain = VisualID + Domain + Freq + CoreIndex.
3. This clean set is then safe for max-selection and final pivot.

If you want, I can next write this as a compact acceptance checklist you can run against any future ILAS file before generating the final table.

---

## User — Message 28

for 4.3.3 parsing the Vmin data. the Vmin data parsing should sorrespond to the VminFwCfg definition for example Vmin data "IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X	0.580_0.580_0.580_0.580_0.580_0.580_0.580_0.580_0.580|0.520_0.520_0.520_0.520_0.520_0.520_0.520_0.520_0.520|0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800_0.800|7
" the first pipe field follows the VminFwCfg definition: "IPH::SCN_HUB_HXX::ATSPEED_NONR_VMIN_K_F1XSN_X_VCCSA_F1_X_vminFwCfg	SAQ0@F1:1:1.400_SAC0@F1:1:1.400_SAN0@F1:1:0.600_SACD0@F1:1:0.403_SAVPU0@F1:1:0.629_SAME0@F1:1:0.450_SAIOC0@F1:1:0.500_SAPS0@F1:1:0.500_SADPU0@F1:1:1.100
" 
the first Vmin value in the first pipe, "_" delimited, corresponds to SAQ@F1:1:1.400 AND SO ON

---

### Assistant

I understand this refinement: Vmin parsing must be aligned position-by-position to VminFwCfg using the first pipe segment only. I’ll patch the parser and record builder to enforce that exact mapping, then show the exact behavior for your example.

---

### Assistant

I’ve enforced strict first-pipe mapping and cfg-aligned indexing; next I’m checking for any syntax issues and then I’ll summarize the exact 4.3.3 parsing rule in your wording.

---

### Assistant

Perfect clarification, and yes, this is exactly the right nuance for 4.3.3.

I implemented this behavior in the parser so mapping is now strictly positional against VminFwCfg:

1. Use only the first pipe segment from TEST_RESULT as the effective Vmin vector.
2. Split that first segment by underscore.
3. Split VminFwCfg by underscore to get ordered domain/freq definitions.
4. Pair by index i to index i only.
5. Emit records only for min(count(VminFwCfg entries), count(first-pipe Vmin values)).
6. Ignore later pipe segments entirely for Vmin mapping.

What changed in code
- First-pipe-only rule is now explicit in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L125)
- Parser function entry is at [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L115)
- Record generation now requires VminFwCfg presence at [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L237)
- Vmin-to-FwCfg pairing count is enforced at [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L245)

How your example now maps
Given:
- Vmin first pipe: 0.580_0.580_0.580_0.580_0.580_0.580_0.580_0.580_0.580
- VminFwCfg: SAQ0@F1..._SAC0@F1..._SAN0@F1..._SACD0@F1..._SAVPU0@F1..._SAME0@F1..._SAIOC0@F1..._SAPS0@F1..._SADPU0@F1...

Mapping is:
1. value[0] 0.580 -> SAQ0@F1...
2. value[1] 0.580 -> SAC0@F1...
3. value[2] 0.580 -> SAN0@F1...
4. value[3] 0.580 -> SACD0@F1...
5. value[4] 0.580 -> SAVPU0@F1...
6. value[5] 0.580 -> SAME0@F1...
7. value[6] 0.580 -> SAIOC0@F1...
8. value[7] 0.580 -> SAPS0@F1...
9. value[8] 0.580 -> SADPU0@F1...

This is now deterministic and aligned to FwCfg order, exactly as you requested.

Next step
I can rerun the full extraction now and produce refreshed detail/summary validation CSVs with this exact 4.3.3 mapping rule applied.

---

## User — Message 29

OK with this definition make sure current script is per need, and recreate the final CSV file for me to manualy validate

---

### Assistant

I’ll now verify the script contains all agreed rules, run it on the full raw file, and regenerate a new final validation CSV you can manually review. After the run, I’ll report file paths and key checks (row count and exclusion sanity).

---

### Assistant

Script checks look good for your definition; I’ll now execute it on the full raw dataset, then copy the new summary to a fresh FINAL_VALIDATION filename and verify row count plus that the flagged FILTER/RO_FCAL_PASS test is excluded.

---

### Assistant

The run failed only because the old detail CSV is locked by another process, so I’ll rerun to a new output folder to avoid the lock and then publish a new final validation CSV from that successful output.

---

## User — Message 30

before continuing, do you understnd that the meanong of the VminFwCfG? for "SAQ0@F1:1:1.400" SAQ is the domain 0=physical core number F1 is the Frequency Corner, next is the flow 1, last 1.400 is the frequency. this data will be used later to merge with the UPSVF data.perserve it in the final file column names. so I understand you need to pharse the VminFwCfg and keep it.

---

### Assistant

Yes, I understand and agree with that VminFwCfg meaning; I’ll update the script now so column names preserve Domain, Core number, Frequency Corner, Flow, and Frequency from VminFwCfg, then regenerate the final CSV for your manual validation.

---

### Assistant

I’ve updated parsing and column naming to preserve VminFwCfg semantics; next I’ll run a quick syntax/error check, then execute full regeneration into a new output folder to avoid file-lock issues.

---

### Assistant

I’m now generating a fresh run in a new output folder (to avoid file locks) and will immediately validate row count plus confirm the unwanted FILTER test is excluded before I hand you the new final CSV path.

---

### Assistant

Fresh CSVs are generated successfully with 47 rows and new column naming that preserves corner/flow/frequency; I’m doing one final exclusion check with a safer exact-match command because the previous regex call had a PowerShell argument parsing issue.

---

### Assistant

Yes, understood exactly, and it is now implemented per your definition.

What I changed
1. VminFwCfg parsing now preserves:
1. Domain token (example SAQ0)
2. Frequency corner (example F1)
3. Flow (example 1)
4. Frequency (example 1.400)
2. Vmin parsing now uses only the first pipe segment and maps by index to VminFwCfg order.
3. Final pivot column names now preserve this metadata so later UPSVF merge can use it directly.

Script updated
- [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1)

New final CSV for your manual validation
- [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V2.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V2.csv)
- Source detail used to build it: [Scripts/_tmp_ilas_validate_v2/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate_v2/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv)

Validation checks
1. Rows in final summary: 47
2. Your flagged unwanted test is excluded:
1. Detail hits: 0
2. Summary hits: 0
3. Column naming now preserves VminFwCfg semantics, for example:
1. AT0_F1_Flow1_Freq1_200_C0_Vmin
2. AT0_F1_Flow1_Freq1_200_C0_Setter
3. AT0_F1_Flow1_Freq1_200_C0_MaxDTS_C
4. AT0_F1_Flow1_Freq1_200_C0_LP

If you want, next I can also create a second final file that keeps the old naming in parallel (for backward compatibility) while retaining this new one for UPSVF merge.

---

## User — Message 31

the data is problematic. first the frequency in the VminFwdCfg is a number 1.2 not 1_2   Second there is one artifact in cases where there is both _VMIN_ and 
like in : "IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED" frequency is 0.400 as noted in the test name. and this is not F1 but FMIN as noted in the test name. so ad the Fmin data in a seperate column with a corresponding column name, and the freq taken from the test instance devided by 1000.

---

### Assistant

I see the two concrete fixes: preserve real decimal frequency text in column names (for example 1.2/1.400, not 1_2), and add a separate FMIN-derived column family using frequency parsed from test name (`0400` -> `0.400`). I’ll patch the script for both and regenerate the validation CSV.

---

### Assistant

I’ve applied both logic changes in the script; next I’ll run it in a new output folder, create a V3 final validation CSV, and verify that FMIN columns exist with decimal frequency tokens like 0.400.

---

### Assistant

I’ve regenerated V3 successfully and validated the new schema; I’ll do one final targeted check that your exact ARR_ATOM_FMIN test is now present under FMIN columns, then I’ll hand you the final file path.

---

### Assistant

Implemented and regenerated per your latest requirement.

What is now fixed
1. Frequency formatting in column names is decimal, not underscore.
1. Example now: AT0_F1_Flow1_Freq1.200_C0_Vmin
2. FMIN cases are emitted in a separate column family.
1. Example now: AT0_FMIN_Freq0.400_C0_Vmin
3. FMIN frequency is parsed from test instance and divided by 1000.
1. Example: _FMIN_0400_ -> Freq0.400
4. VminFwCfg metadata is still preserved in the main columns.
1. Domain, Corner, Flow, Frequency, Core are all retained in naming.

Final CSV for manual validation
1. [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv)

Supporting regenerated files
1. [Scripts/_tmp_ilas_validate_v3/ILAS_Vmin_Summary_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate_v3/ILAS_Vmin_Summary_Y6220110_WW23_2026.csv)
2. [Scripts/_tmp_ilas_validate_v3/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv](Scripts/_tmp_ilas_validate_v3/ILAS_Vmin_Detail_Y6220110_WW23_2026.csv)

Quick validation results
1. Final rows: 47
2. FMIN columns exist:
1. AT0_FMIN_Freq0.400_C0_Vmin
2. AT1_FMIN_Freq0.400_C1_Vmin
3. Decimal FwCfg columns exist:
1. AT0_F1_Flow1_Freq1.200_C0_Vmin
4. Your ARR_ATOM FMIN test is mapped into FMIN setter columns:
1. TargetFminSetterHits = 39

If you want, I can also generate a compact dictionary CSV that maps each generated column name to its semantic fields (Domain, Core, Corner, Flow, FreqGHz, Source=FwCfg/FMIN) to make UPSVF merge rules explicit.

---

## User — Message 32

yes merge table is needed.

---

### Assistant

I’ll generate a dedicated merge dictionary CSV from the V3 final summary headers so each column is explicitly mapped to Domain/Core/Corner/Flow/Frequency and tagged as FwCfg or FMIN for UPSVF joining.

---

### Assistant

I’ve created the merge map with full parsing and zero unparsed columns; I’ll quickly pull a small preview so you can confirm it matches your UPSVF merge expectations.

---

### Assistant

Merge table is created and ready for UPSVF integration.

File:
- [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V3.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V3.csv)

What it contains per output column:
1. ColumnName
2. Source: `VMINFWCFG` or `FMIN_FROM_TESTNAME`
3. Domain
4. Core (physical core number)
5. Corner (for example `F1`, `FMIN`)
6. Flow (or `NA` for FMIN-derived columns)
7. FreqGHz (decimal, for example `1.200`, `0.400`)
8. Metric (`Vmin`, `Setter`, `MaxDTS_C`, `LP`)
9. JoinKeyNoMetric: `Domain|Corner|Flow|FreqGHz|Core`

Validation:
1. Total mapped columns: 304
2. Unparsed columns: 0

If you want, I can also generate a second map keyed for your exact UPSVF schema names (rename columns to your target key field names).

---

## User — Message 33

I still see testinstances that are FMIN related and are setting F1 vmin like in: 
VisualID	AT0_F1_Flow1_Freq1.200_C0_Vmin	AT0_F1_Flow1_Freq1.200_C0_Setter
U6CV323100001	0.47	IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED

only in the case of FMIN instances do not consider the VminFwCfg. and make sure that test instances of FMIN are not considered in the F1 Vmin max calculations. I would like the visability of F1 and FMIN seperatly to check when FMIN is actually setting F1 Vmin.

---

### Assistant

I see the issue clearly: FMIN test instances are still entering the main F1/F2/F3 max-Vmin aggregation path. I’ll isolate them completely so main `F*` columns exclude FMIN setters, while keeping a separate FMIN column family for side-by-side visibility.

---

### Assistant

I’m applying a focused fix now: FMIN instances will be excluded from the main `F*` max-Vmin aggregation path, while still being kept in separate `FMIN` columns; I’ll also ensure all VisualIDs remain in the final output even if they only have FMIN data.

---

### Assistant

I’ve made the isolation fix; next I’ll regenerate a V4 output and run a targeted proof that your FMIN setter no longer appears in `AT0_F1_Flow1_Freq1.200_C0_Setter` while still present under `FMIN` columns.

---

### Assistant

I verified the exact problematic VisualID is now separated correctly; I’ll generate a matching V4 merge-map file so your UPSVF join metadata stays in sync with this corrected final CSV.

---

### Assistant

Fixed. FMIN test instances are now isolated from the main `F*` aggregation path.

What changed
1. FMIN instances are excluded from main `VMINFWCFG` max calculations (`F1/F2/F3...` columns).
2. FMIN instances are still included in separate `*_FMIN_Freq...` columns.
3. VisualID coverage remains complete (47 units), even with separation.

New final CSV
- [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv)

Updated merge map (for this V4 file)
- [Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V4.csv](Scripts/ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V4.csv)

Proof on your exact example (VisualID `U6CV323100001`)
1. `AT0_F1_Flow1_Freq1.200_C0_Setter` is now:
1. `IPC::FUN_ATOM_CX48::SBFT_ATOM_VMIN_K_F1XAT_X_AT_F1_1200_L2_DRAGON`
2. `AT0_FMIN_Freq0.400_C0_Setter` is:
1. `IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED`
3. So the FMIN setter no longer drives the F1 column.

Run stats
1. Rows: 47
2. Detail records: 26,140
3. Merge map unparsed columns: 0

---

## User — Message 34

The final results seems good. please save the current code for the ILAS analysis as new skill/ agent what is more suitible with the name ILAS. now lets perform the merging step, I think the merging table is not needed. so its creation step in the code can be removed as it is memory consuming. because each Visual ID exists in both files, it is simple to make sure that both Visual ID as well as the Class lot (lotfroms) are matching between the tables and add the ILAS columns to the "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv". the general weekly final outcome is: 
1. C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1 automation runs every Sunday saving its output
2. this automation last step is to trigger the ILAS analysis.
3. the ILAS Aqua data pulling should be for the final Visual_IDs that exists in the UPSVF weekly data pull (remove the current lot filter of Y6220110)
4. only after completion of the ILAS report the data should be added to the final UPSVF weekly report. 
5. add steps that if the UPSVF data is missing/ defective- the second step of ILAS will not start. and if the second step of ILAS has any problem this will not effect the already existing table of UPSVF weekly. 
6. final step of data cleaning. if for example core domain of unit U6CV323100010
where the unit is missing UPSVF Vmin for 5.000 yet have ILAS data for tests with VminFwCfg of 5.000 than the ILAS data will be removed, empty cell, for all Ilas columns- DTS, Test instance, lp...

all these steps1-6  are irrelevant to the ILAS skill/Agent that I initialy asked. the merge step is related to the weekly automation. if you need to save the merge as a seperate skill/Agent- reflect it in the name

---

### Assistant

I’ll do this in two tracks: first I’ll package the ILAS logic into a dedicated ILAS skill/agent artifact, then I’ll modify weekly automation so ILAS runs only after valid UPSVF output and merges directly into the weekly report without the extra merge-map step. I’m starting by reading the two scripts to implement your step-by-step weekly flow exactly.

---

### Assistant

I’ve mapped the implementation plan and I’m now patching the ILAS script to support UPSVF-driven filtering by VisualID plus Class lot, so weekly automation can trigger ILAS safely without hardcoded lot overrides.

---

### Assistant

I’ve added merge helpers; I’m now wiring the weekly control flow so ILAS starts only when UPSVF output is valid, and any ILAS failure is isolated so the existing UPSVF weekly file remains untouched.

---

### Assistant

Code updates are in place for UPSVF-driven ILAS filtering and safe weekly merge logic; next I’ll verify runtime behavior with the current known files, then create the new ILAS skill and separate weekly-merge skill artifacts under the repo skills folder.

---

## User — Message 35

making sure before we continue to the runtime verification (ofer the same pwsh command after answering this question) in step 6, relating to the cleaning, I gave an exmple where a unit does not have UPSVF data for Core 5.000 yet have ILAS data for that freq, and asked to remove the ILAS data. the data removal refers only to the missing frequency of UPSVF. the 5.000 ILAS data should be removed. rest of the Domain-frequencies should remain.

---

### Assistant

Correct, and that is exactly how step 6 is implemented now.

The cleaning is frequency-scoped, not unit-global:
1. For each unit row, it groups ILAS columns by frequency token (for example 5.000, 3.200, 0.400).
2. It checks whether UPSVF has any non-empty data for that same frequency in non-ILAS columns.
3. If UPSVF is missing that frequency, only ILAS columns for that frequency are cleared.
4. All other ILAS domain-frequency columns for that unit remain unchanged.

So in your example, only ILAS columns at 5.000 are blanked; ILAS values for other frequencies stay.

Same PowerShell command for runtime verification:
$raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; $ups='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $raw)){ throw "Missing raw ILAS file: $raw" }; if(-not (Test-Path -LiteralPath $ups)){ throw "Missing UPSVF file: $ups" }; $out='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_weekly_flow_check'; if(-not (Test-Path -LiteralPath $out)){ New-Item -ItemType Directory -Path $out | Out-Null }; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $ups -OutputDirectory $out;

---

## User — Message 36

ok. what verification should we run now to make sure the final version of the UPSVF weekly -- Ilas automation is working?

---

### Assistant

Great question. To validate the final UPSVF weekly plus ILAS automation end to end, run verification in this order so you prove each requirement independently and safely.

1. Baseline UPSVF output only (ILAS skipped)
Pass goal:
1. Weekly pull succeeds
2. UPSVF CSV is valid and non-empty
3. ILAS step is skipped by design

Command:
PowerShell:
$weekly = "C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1"
& $weekly -SkipIlasStep

Check:
- Weekly output CSV exists in weekly folder
- Log includes ILAS status = SKIPPED

2. ILAS standalone with UPSVF reference filter
Pass goal:
1. ILAS accepts UPSVF reference CSV
2. ILAS filters by VisualID plus lot key
3. Summary includes VisualID and LotFromFs

Command:
PowerShell:
$raw = "C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv"
$ups = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv"
$out = "C:\Projects\NVL\.docs\Scripts\_tmp_ilas_weekly_flow_check"
if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out | Out-Null }
& "C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1" -RawInputFile $raw -UpsvfReferenceCsv $ups -OutputDirectory $out

Check:
- ILAS summary exists
- It has VisualID and LotFromFs columns
- FMIN setters do not appear in F1 columns (you already validated this pattern)

3. Full weekly flow in safe test mode (with ILAS merge)
Pass goal:
1. UPSVF generation runs
2. ILAS runs only after UPSVF validity check
3. Merge writes ILAS columns prefixed with ILAS_
4. Final file remains valid

Command:
PowerShell:
$weekly = "C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1"
& $weekly

Check:
- Final weekly CSV has ILAS_ columns
- Weekly log has ILAS status = SUCCESS and ILAS summary path

4. Failure isolation test: ILAS fails, UPSVF remains intact
Pass goal:
1. If ILAS fails, base UPSVF CSV is not corrupted or emptied
2. Weekly script reports ILAS FAILED but keeps existing weekly table

Method:
- Intentionally pass invalid ILAS path once:
PowerShell:
$weekly = "C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1"
& $weekly -IlasScriptPath "C:\bad\missing_ilas.ps1"

Check:
- Weekly CSV still exists and is non-empty
- Log shows ILAS status = FAILED
- UPSVF data remains present

5. Defective UPSVF guard test
Pass goal:
1. If UPSVF output is missing required VisualID or lot column, ILAS does not start

Method:
- Run against a temporary malformed UPSVF CSV in a controlled test harness (or temporarily remove those columns in a copy)
Check:
- ILAS status = SKIPPED
- Message indicates UPSVF missing required structure

6. Frequency-scoped cleaning validation (your step 6)
Pass goal:
1. Only ILAS columns for missing UPSVF frequency are blanked
2. Other ILAS frequencies remain

Check query example:
PowerShell:
$csv = "\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv"
$r = Import-Csv -LiteralPath $csv | Where-Object { $_.VisualID -eq "U6CV323100010" } | Select-Object -First 1
$r.PSObject.Properties | Where-Object { $_.Name -like "ILAS_*Freq5.000*" -or $_.Name -like "ILAS_*Freq3.200*" } | Select-Object Name,Value

Pass criteria:
- ILAS Freq5.000 columns are empty when UPSVF has no 5.000 for that unit
- ILAS Freq3.200 (or other existing frequencies) stay populated

7. Spot integrity checks (must-have)
Pass goal:
1. No non-VMIN noise tests in ILAS output
2. FMIN visible separately

Quick checks:
- Search for the flagged FILTER/RO_FCAL_PASS setter in ILAS columns: should be absent
- Confirm FMIN columns exist and are populated separately

If you want, I can execute this exact verification sequence now and return a pass/fail checklist with evidence paths and key row samples.

---

## User — Message 37

excute the verification for NVLH Classhot data from last 7 days, save output files for manualy verification, do not stop to ask me to allow any step, assume I allow, as I will not be by the computer. stop only if file sizes are to big and prevents you to go on. ask me now any question as I will leave the computer.

---

### Assistant

One quick question before I start: do you want this verification run to write into the production weekly folder, or into an isolated verification folder? I will proceed with an isolated folder by default to avoid impacting production outputs while you’re away.

---

### Assistant

The full weekly run has started successfully and is currently pulling AQUA data; I’ll keep monitoring until completion and then collect all output files and validation checks for you.

---

### Assistant

I’m reading the latest terminal output snapshot now to confirm whether the end-to-end weekly run finished, then I’ll either continue waiting or start collecting verification artifacts.

---

### Assistant

The run is still active; I’m checking the latest tail output now to confirm whether it has progressed past AQUA pull or is waiting, then I’ll continue automatically.

---

### Assistant

While AQUA pull continues, I’m creating the reusable skills now so your current ILAS analysis logic and the weekly UPSVF+ILAS merge automation are saved as separate skills with clear boundaries.

---

### Assistant

I’ve finished creating the two skill artifacts; I’m now extracting the latest weekly-run tail to see if the end-to-end verification completed and to capture exact output file paths.

---

### Assistant

The run is still in AQUA execution state (`Waiting for AQUA to prepare report results...`), so I’m continuing to wait and poll automatically until the weekly flow finishes and output files appear.

---

### Assistant

The live AQUA pull is still waiting on AQUA-side report preparation, so I’m running a full offline verification path now (using current 7-day UPSVF weekly CSV plus ILAS raw probe) to produce manual-validation artifacts immediately while the live run remains in progress.

---

## User — Message 38

why are there only 47 units? last 7 days have more than that. need to validate if the relevat ILAS report was run with all of the Visual ID that the weekly UPSVF report resulted with. make sure the automation Aqua query ILAS Visual_ID input is taken from the UPSVF report

---

### Assistant

I’ll verify this directly by measuring VisualID counts in the weekly UPSVF file and in ILAS outputs, then I’ll check whether the ILAS pull is actually constrained by UPSVF VisualIDs (not just lots) and patch automation if needed.

---

### Assistant

I confirmed coverage is complete for this weekly file (47 unique UPSVF VisualIDs, 47 in ILAS, no missing/extra); I’m now patching ILAS pull so AQUA gets explicit `-visualIds` from UPSVF input (with fallback if the list gets too long).

---

### Assistant

You are right to challenge it. I validated this directly.

Findings
1. The weekly UPSVF file currently has 55 rows but only 47 unique Visual IDs.
2. ILAS summary has 47 unique Visual IDs.
3. Visual ID set comparison is exact: missing in ILAS = 0, extra in ILAS = 0.

So 47 here is because of uniqueness, not dropped IDs.

What I changed now
1. I updated ILAS automation so AQUA query input explicitly includes Visual IDs taken from the UPSVF report.
2. It now passes `-visualIds <csv list>` when the list is safe for command-line length.
3. If the list is too long, it falls back to lot-based pull and still post-filters by VisualID+lot.

Code references
1. Visual IDs collected from UPSVF reference in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L44)
2. AQUA `-visualIds` argument injection in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L407)
3. Existing strict post-filter by VisualID+lot in [Scripts/aqua_nvlh_ilas_vmin_analysis.ps1](Scripts/aqua_nvlh_ilas_vmin_analysis.ps1#L467)

Status of live runtime verification
1. The live weekly run is still waiting on AQUA server-side preparation (`Waiting for AQUA to prepare report results...`).
2. No large-file blocker yet; it is an AQUA-side wait state.

Saved skills
1. ILAS skill: [.github/skills/ilas/SKILL.md](.github/skills/ilas/SKILL.md)
2. Weekly merge skill: [.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md](.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md)

If you want, I can keep the live run polling in the next turn and report the final generated file paths as soon as AQUA finishes.

---

## User — Message 39

keep a live polling as you sugest. 
is SKILL.md the name? why both ILAS and weekly have same SKILL.md name? is it important?
ILAS skill includes the 1-6 merging steps I specified? (specify what each skill does)

---

### Assistant

I’ll keep live polling active now and report only the real status changes, then I’ll clarify exactly what each skill covers versus your 1-6 weekly merge steps.

---

### Assistant

Live polling is active; weekly UPSVF pull finished and ILAS pull has started with UPSVF-derived lot scope. I’m polling again now to capture whether ILAS AQUA completed and to confirm VisualID argument usage in live run output.

---

### Assistant

I’m running a quick lightweight verification now to prove the updated ILAS script is reading VisualIDs from UPSVF reference (you’ll see the explicit VisualID log line).

---

### Assistant

Yes, live polling is continuing.

Current live status
1. Weekly UPSVF stage completed.
2. ILAS stage is running and currently waiting on AQUA report readiness in terminal id 76b73376-ce7d-4b58-be9c-866321565350.
3. I also ran a direct verification with the updated ILAS script, and it now explicitly logs:
1. Using 47 VisualID(s) from UPSVF reference for ILAS pull.
2. Using 1 lot(s) from UPSVF reference for ILAS pull.

So the Visual_ID input is now taken from UPSVF reference in automation logic.

About SKILL.md naming
1. Yes, SKILL.md is the expected filename for skills.
2. It is normal that multiple skills each have a file named SKILL.md.
3. The identity comes from folder path plus frontmatter name, not filename alone.
4. This is important for skill discovery/registration.

Your two skills and what each does

1. ILAS skill: [.github/skills/ilas/SKILL.md](.github/skills/ilas/SKILL.md)
1. Scope: ILAS extraction/parsing/transformation only.
2. Includes strict VMIN parsing, VMINFWCFG positional mapping, FMIN separation, FMIN exclusion from main F-corner aggregation.
3. Supports UPSVF reference filtering by VisualID+lot for ILAS data selection.
4. Does not perform weekly orchestration merge step 1-6.

2. Weekly UPSVF+ILAS merge skill: [.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md](.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md)
1. Scope: full weekly orchestration and merge behavior.
2. This is where your step 1-6 belongs.
3. Mapping to your 1-6:
1. Weekly UPSVF automation run: included.
2. Trigger ILAS after UPSVF: included.
3. ILAS scoped from UPSVF output (VisualID+lot): included.
4. Merge only after ILAS completes: included.
5. Failure isolation (UPSVF defective skips ILAS, ILAS failure does not break UPSVF): included.
6. Frequency-scoped cleanup (clear only ILAS columns for missing UPSVF frequency): included.

Important nuance on your question
1. The current weekly file you pointed to has 55 rows but 47 unique Visual_ID.
2. ILAS output also has 47 unique Visual_ID.
3. So coverage is complete for that weekly run (no missing Visual_ID in ILAS vs UPSVF unique set).

I will keep live polling and report as soon as the running ILAS AQUA stage completes with final output paths.

---

## User — Message 40

[Terminal 5fe16782-1808-48a5-893d-135612ed29e5 notification: command completed with exit code 0. The terminal has been cleaned up.]
Terminal output:


[... PREVIOUS OUTPUT TRUNCATED ...]

 AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     C:\Projects\NVL\.docs\Scripts\_verify_weekly_20260602_220612\_raw_20260602_220613.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).L
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Le
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Len
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Leng
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Lengt
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Length
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Length)
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Length)"
PS C:\Projects\NVL\.docs> $verify='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602'; New-Item -ItemType Directory -Path $verify -Force | Out-Null; $upsSrc='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $upsSrc)){ throw "Missing UPSVF source: $upsSrc" }; $upsLocal=Join-Path $verify 'UPSVF_base.csv'; Copy-Item -LiteralPath $upsSrc -Destination $upsLocal -Force; $ilasOut=Join-Path $verify 'ILAS'; New-Item -ItemType Directory -Path $ilasOut -Force | Out-Null; $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $upsLocal -OutputDirectory $ilasOut; $ilasSummary=(Get-ChildItem -LiteralPath $ilasOut -Filter 'ILAS_Vmin_Summary_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName; if(-not $ilasSummary){ throw 'No ILAS summary generated' }; $upsRows=@(Import-Csv -LiteralPath $upsLocal); $ilasRows=@(Import-Csv -LiteralPath $ilasSummary); $upsCols=$upsRows[0].PSObject.Properties.Name; $ilasCols=$ilasRows[0].PSObject.Properties.Name; $upsVid=($upsCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $upsLot=($upsCols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $ilasVid=($ilasCols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $ilasLot=($ilasCols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); if(-not $upsVid -or -not $upsLot -or -not $ilasVid -or -not $ilasLot){ throw 'Missing VisualID/Lot columns for merge' }; $ilasDataCols=@($ilasCols | Where-Object { $_ -ne $ilasVid -and $_ -ne $ilasLot }); $lookup=@{}; foreach($r in $ilasRows){ $v=[string]$r.$ilasVid; $l=[string]$r.$ilasLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $lookup["$($v.Trim())||$($l.Trim())"]=$r }; $ilasPrefixed=@($ilasDataCols | ForEach-Object { "ILAS_$_" }); foreach($row in $upsRows){ foreach($c in $ilasPrefixed){ $row | Add-Member -NotePropertyName $c -NotePropertyValue '' -Force }; $v=[string]$row.$upsVid; $l=[string]$row.$upsLot; if([string]::IsNullOrWhiteSpace($v)-or [string]::IsNullOrWhiteSpace($l)){ continue }; $k="$($v.Trim())||$($l.Trim())"; if(-not $lookup.ContainsKey($k)){ continue }; $ir=$lookup[$k]; foreach($src in $ilasDataCols){ $row.("ILAS_$src")=$ir.$src } }; foreach($row in $upsRows){ $freqMap=@{}; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -notlike 'ILAS_*'){ continue }; if($n -match '_Freq(?<F>[0-9]+(?:\.[0-9]+)?)_C\d+_(Vmin|Setter|MaxDTS_C|LP)$'){ $f=$Matches['F']; if(-not $freqMap.ContainsKey($f)){ $freqMap[$f]=New-Object System.Collections.Generic.List[string] }; $freqMap[$f].Add($n) } }; foreach($f in $freqMap.Keys){ $has=$false; $a1=$f; $a2=$f -replace '\.','_'; $a3=$f -replace '\.',''; foreach($p in $row.PSObject.Properties){ $n=[string]$p.Name; if($n -like 'ILAS_*'){ continue }; if($n -match [regex]::Escape($a1) -or $n -match [regex]::Escape($a2) -or $n -match [regex]::Escape($a3)){ $val=[string]$p.Value; if(-not [string]::IsNullOrWhiteSpace($val)){ $has=$true; break } } }; if(-not $has){ foreach($c in $freqMap[$f]){ $row.$c='' } } } }; $merged=Join-Path $verify 'UPSVF_with_ILAS_merged.csv'; $upsRows | Export-Csv -LiteralPath $merged -NoTypeInformation; "VerifyDir=$verify"; "ILASSummary=$ilasSummary"; "MergedCsv=$merged"; "Rows=$((Import-Csv -LiteralPath $merged).Count)"; "MergedSizeBytes=$((Get-Item -LiteralPath $merged).Length)";
Using 1 lot(s) from UPSVF reference for ILAS pull.
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Filtered ILAS rows by UPSVF VisualID+lot keys: 964810 -> 964810
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 26140 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602\ILAS\ILAS_Vmin_Detail_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602\ILAS\ILAS_Vmin_Summary_WW23_2026.csv
Units       : 47
Domain/Freq : 69
Detail rows : 26140
PS C:\Projects\NVL\.docs> $ups='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; if(-not (Test-Path -LiteralPath $ups)){ throw "Missing UPSVF file: $ups" }; $rows=Import-Csv -LiteralPath $ups; $cols=$rows[0].PSObject.Properties.Name; $vidCol=($cols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $lotCol=($cols | Where-Object { $_ -in @('LOTFROMFS','LotFromFs','LOT','Lot','SortLot','SORT_LOT','LATO_LOT') } | Select-Object -First 1); $uniqVid=@($rows | ForEach-Object { [string]$_.$vidCol } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique); "UPSVF_File=$ups"; "UPSVF_RowCount=$($rows.Count)"; "UPSVF_VisualIdColumn=$vidCol"; "UPSVF_LotColumn=$lotCol"; "UPSVF_UniqueVisualIDs=$($uniqVid.Count)";
UPSVF_File=\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv
UPSVF_RowCount=55
UPSVF_VisualIdColumn=VISUAL_ID
UPSVF_LotColumn=LOTFROMFS
UPSVF_UniqueVisualIDs=47
PS C:\Projects\NVL\.docs> $candidates=@('C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv','C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602\ILAS\ILAS_Vmin_Summary_WW23_2026.csv'); foreach($f in $candidates){ if(Test-Path -LiteralPath $f){ $rows=Import-Csv -LiteralPath $f; $cols=$rows[0].PSObject.Properties.Name; $vidCol=($cols | Where-Object { $_ -in @('Visual ID','VISUAL_ID','VisualId','VISUALID','VID','VisualID') } | Select-Object -First 1); $lotCol=($cols | Where-Object { $_ -in @('LotFromFs','LOTFROMFS','LOT','Lot') } | Select-Object -First 1); $uniq=@($rows | ForEach-Object { [string]$_.$vidCol } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique); "ILAS_File=$f"; "Rows=$($rows.Count)"; "VisualIDs=$($uniq.Count)"; "LotColumn=$lotCol"; '' } }
ILAS_File=C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv
Rows=47
VisualIDs=47
LotColumn=

ILAS_File=C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602\ILAS\ILAS_Vmin_Summary_WW23_2026.csv
Rows=47
VisualIDs=47
LotColumn=LotFromFs

PS C:\Projects\NVL\.docs> $ups='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; $ilas='C:\Projects\NVL\.docs\Scripts\_verify_weekly_offline_20260602\ILAS\ILAS_Vmin_Summary_WW23_2026.csv'; if(!(Test-Path -LiteralPath $ups) -or !(Test-Path -LiteralPath $ilas)){ throw 'Missing UPSVF or ILAS summary for comparison' }; $u=Import-Csv -LiteralPath $ups; $i=Import-Csv -LiteralPath $ilas; $uVid=@($u | ForEach-Object { [string]$_.VISUAL_ID } | Where-Object {$_} | Sort-Object -Unique); $iVidCol=((($i|Select-Object -First 1).PSObject.Properties.Name) | Where-Object {$_ -in @('VisualID','VISUAL_ID','VisualId','VISUALID','VID')} | Select-Object -First 1); $iVid=@($i | ForEach-Object { [string]$_.$iVidCol } | Where-Object {$_} | Sort-Object -Unique); $missingInIlas=@($uVid | Where-Object { $iVid -notcontains $_ }); $extraInIlas=@($iVid | Where-Object { $uVid -notcontains $_ }); "UPSVF_UniqueVID=$($uVid.Count)"; "ILAS_UniqueVID=$($iVid.Count)"; "MissingInILAS=$($missingInIlas.Count)"; if($missingInIlas.Count -gt 0){ $missingInIlas | Select-Object -First 20 }; "ExtraInILAS=$($extraInIlas.Count)"; if($extraInIlas.Count -gt 0){ $extraInIlas | Select-Object -First 20 }
UPSVF_UniqueVID=47
ILAS_UniqueVID=47
MissingInILAS=0
ExtraInILAS=0
PS C:\Projects\NVL\.docs> $p='C:\Users\hmarkovi\AppData\Roaming\Code\User\workspaceStorage\8a9e08333326ba8f94a1f7cbaa6292e8\GitHub.copilot-chat\chat-session-resources\01ead9ee-e890-417a-810b-d3155d7c5267\call_sTqGmUjKCXAX1pAKfLeUBxqg__vscode-1780385092398\content.txt'; Get-Content -LiteralPath $p -Tail 120
AT0_F2_Flow1_Freq2_800_C0_Vmin
AT0_F3_Flow1_Freq3_200_C0_LP
AT0_F3_Flow1_Freq3_200_C0_MaxDTS_C
AT0_F3_Flow1_Freq3_200_C0_Setter
AT0_F3_Flow1_Freq3_200_C0_Vmin
PS C:\Projects\NVL\.docs> $detail='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v2\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv'; $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V2.csv'; $bad='IPP::CLK_ISCLK_PXH::ALLPLL_PXH_CTVDECODERSPM_E_STARTANA1PCD_X_X_VMIN_X_X_FILTER|RELOCK|RO_FCAL_PASS'; $detailHits=(Import-Csv -LiteralPath $detail | Where-Object { $_.TestName -eq $bad }).Count; $summaryHits=(Select-String -Path $summary -SimpleMatch -Pattern $bad).Count; "BadTestDetailHits=$detailHits"; "BadTestSummaryHits=$summaryHits";
BadTestDetailHits=0
BadTestSummaryHits=0
PS C:\Projects\NVL\.docs> $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; $out='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v3'; if(-not (Test-Path -LiteralPath $out)){ New-Item -ItemType Directory -Path $out | Out-Null }; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -OutputDirectory $out -LotsOverride 'Y6220110';
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 26140 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v3\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v3\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
Units       : 47
Domain/Freq : 69
Detail rows : 26140
PS C:\Projects\NVL\.docs> $src='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v3\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv'; $dst='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv'; Copy-Item -LiteralPath $src -Destination $dst -Force; $rows=(Import-Csv -LiteralPath $dst).Count; "FinalCsv=$dst"; "Rows=$rows"; "SizeBytes=$((Get-Item -LiteralPath $dst).Length)";
FinalCsv=C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv
Rows=47
SizeBytes=374553
PS C:\Projects\NVL\.docs> $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv'; $cols=(Import-Csv -LiteralPath $summary | Select-Object -First 1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name); $fminCols=$cols | Where-Object { $_ -like '*_FMIN_Freq*' } | Select-Object -First 10; $decimalCols=$cols | Where-Object { $_ -like '*Freq*.*_C*' } | Select-Object -First 10; 'FMINColumnsSample='; $fminCols; 'DecimalFreqColumnsSample='; $decimalCols;
FMINColumnsSample=
AT0_FMIN_Freq0.400_C0_LP
AT0_FMIN_Freq0.400_C0_MaxDTS_C
AT0_FMIN_Freq0.400_C0_Setter
AT0_FMIN_Freq0.400_C0_Vmin
AT1_FMIN_Freq0.400_C1_LP
AT1_FMIN_Freq0.400_C1_MaxDTS_C
AT1_FMIN_Freq0.400_C1_Setter
AT1_FMIN_Freq0.400_C1_Vmin
CCF0_FMIN_Freq0.400_C0_LP
CCF0_FMIN_Freq0.400_C0_MaxDTS_C
DecimalFreqColumnsSample=
AT0_F1_Flow1_Freq1.200_C0_LP
AT0_F1_Flow1_Freq1.200_C0_MaxDTS_C
AT0_F1_Flow1_Freq1.200_C0_Setter
AT0_F1_Flow1_Freq1.200_C0_Vmin
AT0_F2_Flow1_Freq2.800_C0_LP
AT0_F2_Flow1_Freq2.800_C0_MaxDTS_C
AT0_F2_Flow1_Freq2.800_C0_Setter
AT0_F2_Flow1_Freq2.800_C0_Vmin
AT0_F3_Flow1_Freq3.200_C0_LP
AT0_F3_Flow1_Freq3.200_C0_MaxDTS_C
PS C:\Projects\NVL\.docs> $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv'; $target='IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED'; $rows=Import-Csv -LiteralPath $summary; $hits=0; foreach($r in $rows){ $props=$r.PSObject.Properties; foreach($p in $props){ if($p.Name -like '*_FMIN_Freq0.400_*_Setter' -and [string]$p.Value -eq $target){ $hits++; break } } }; "TargetFminSetterHits=$hits";
TargetFminSetterHits=39
PS C:\Projects\NVL\.docs> $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V3.csv'; if(-not (Test-Path -LiteralPath $summary)){ throw "Missing summary file: $summary" }; $first=Import-Csv -LiteralPath $summary | Select-Object -First 1; $cols=$first.PSObject.Properties.Name; $rows=New-Object System.Collections.Generic.List[object]; foreach($c in $cols){ if($c -eq 'VisualID'){ continue }; if($c -match '^(?<Domain>.+)_FMIN_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C(?<Core>\d+)_(?<Metric>Vmin|Setter|MaxDTS_C|LP)$'){ $domain=$Matches['Domain']; $freq=$Matches['Freq']; $core=[int]$Matches['Core']; $metric=$Matches['Metric']; $corner='FMIN'; $flow='NA'; $source='FMIN_FROM_TESTNAME'; $joinKey="$domain|$corner|$flow|$freq|$core"; $rows.Add([pscustomobject]@{ ColumnName=$c; Source=$source; Domain=$domain; Core=$core; Corner=$corner; Flow=$flow; FreqGHz=$freq; Metric=$metric; JoinKeyNoMetric=$joinKey }) | Out-Null; continue }; if($c -match '^(?<Domain>.+)_(?<Corner>F[^_]+)_Flow(?<Flow>[^_]+)_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C(?<Core>\d+)_(?<Metric>Vmin|Setter|MaxDTS_C|LP)$'){ $domain=$Matches['Domain']; $corner=$Matches['Corner']; $flow=$Matches['Flow']; $freq=$Matches['Freq']; $core=[int]$Matches['Core']; $metric=$Matches['Metric']; $source='VMINFWCFG'; $joinKey="$domain|$corner|$flow|$freq|$core"; $rows.Add([pscustomobject]@{ ColumnName=$c; Source=$source; Domain=$domain; Core=$core; Corner=$corner; Flow=$flow; FreqGHz=$freq; Metric=$metric; JoinKeyNoMetric=$joinKey }) | Out-Null; continue }; $rows.Add([pscustomobject]@{ ColumnName=$c; Source='UNPARSED'; Domain=''; Core=''; Corner=''; Flow=''; FreqGHz=''; Metric=''; JoinKeyNoMetric='' }) | Out-Null }; $map='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V3.csv'; $rows | Sort-Object Source,Domain,Corner,Flow,FreqGHz,Core,Metric | Export-Csv -LiteralPath $map -NoTypeInformation; $total=$rows.Count; $unparsed=($rows | Where-Object { $_.Source -eq 'UNPARSED' }).Count; "MergeMap=$map"; "TotalColumnsMapped=$total"; "UnparsedColumns=$unparsed";

MergeMap=C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V3.csv
TotalColumnsMapped=304
UnparsedColumns=0
PS C:\Projects\NVL\.docs> $map='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V3.csv'; Import-Csv -LiteralPath $map | Select-Object -First 12 | Format-Table ColumnName,Source,Domain,Core,Corner,Flow,FreqGHz,Metric -AutoSize | Out-String

ColumnName                      Source             Domain Core Corner Flow Freq
                                                                           GHz 
----------                      ------             ------ ---- ------ ---- ----
AT0_FMIN_Freq0.400_C0_LP        FMIN_FROM_TESTNAME AT0    0    FMIN   NA   0...
AT0_FMIN_Freq0.400_C0_MaxDTS_C  FMIN_FROM_TESTNAME AT0    0    FMIN   NA   0...
AT0_FMIN_Freq0.400_C0_Setter    FMIN_FROM_TESTNAME AT0    0    FMIN   NA   0...
AT0_FMIN_Freq0.400_C0_Vmin      FMIN_FROM_TESTNAME AT0    0    FMIN   NA   0...
AT1_FMIN_Freq0.400_C1_LP        FMIN_FROM_TESTNAME AT1    1    FMIN   NA   0...
AT1_FMIN_Freq0.400_C1_MaxDTS_C  FMIN_FROM_TESTNAME AT1    1    FMIN   NA   0...
AT1_FMIN_Freq0.400_C1_Setter    FMIN_FROM_TESTNAME AT1    1    FMIN   NA   0...
AT1_FMIN_Freq0.400_C1_Vmin      FMIN_FROM_TESTNAME AT1    1    FMIN   NA   0...
CCF0_FMIN_Freq0.400_C0_LP       FMIN_FROM_TESTNAME CCF0   0    FMIN   NA   0...
CCF0_FMIN_Freq0.400_C0_MaxDTS_C FMIN_FROM_TESTNAME CCF0   0    FMIN   NA   0...
CCF0_FMIN_Freq0.400_C0_Setter   FMIN_FROM_TESTNAME CCF0   0    FMIN   NA   0...
CCF0_FMIN_Freq0.400_C0_Vmin     FMIN_FROM_TESTNAME CCF0   0    FMIN   NA   0...



PS C:\Projects\NVL\.docs> $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; $out='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v4'; if(-not (Test-Path -LiteralPath $out)){ New-Item -ItemType Directory -Path $out | Out-Null }; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -OutputDirectory $out -LotsOverride 'Y6220110';
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 26140 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v4\ILAS_Vmin_Detail_Y6220110_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v4\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv
Units       : 47
Domain/Freq : 69
Detail rows : 26140
PS C:\Projects\NVL\.docs> $src='C:\Projects\NVL\.docs\Scripts\_tmp_ilas_validate_v4\ILAS_Vmin_Summary_Y6220110_WW23_2026.csv'; $dst='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv'; Copy-Item -LiteralPath $src -Destination $dst -Force; $rows=(Import-Csv -LiteralPath $dst).Count; "FinalCsv=$dst"; "Rows=$rows"; "SizeBytes=$((Get-Item -LiteralPath $dst).Length)";
FinalCsv=C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv
Rows=47
SizeBytes=374119
PS C:\Projects\NVL\.docs> $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv'; $targetVid='U6CV323100001'; $targetSetter='IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED'; $r=Import-Csv -LiteralPath $summary | Where-Object { $_.VisualID -eq $targetVid } | Select-Object -First 1; if($null -eq $r){ throw "VisualID not found: $targetVid" }; $f1Setter=[string]$r.'AT0_F1_Flow1_Freq1.200_C0_Setter'; $f1Vmin=[string]$r.'AT0_F1_Flow1_Freq1.200_C0_Vmin'; $fminSetter=[string]$r.'AT0_FMIN_Freq0.400_C0_Setter'; $fminVmin=[string]$r.'AT0_FMIN_Freq0.400_C0_Vmin'; "VisualID=$targetVid"; "F1Setter=$f1Setter"; "F1Vmin=$f1Vmin"; "FMINSetter=$fminSetter"; "FMINVmin=$fminVmin"; "F1SetterIsFmin=$([string]::Equals($f1Setter,$targetSetter,[System.StringComparison]::Ordinal))"; "FMINSetterIsTarget=$([string]::Equals($fminSetter,$targetSetter,[System.StringComparison]::Ordinal))";
VisualID=U6CV323100001
F1Setter=IPC::FUN_ATOM_CX48::SBFT_ATOM_VMIN_K_F1XAT_X_AT_F1_1200_L2_DRAGON
F1Vmin=0.46
FMINSetter=IPC::ARR_ATOM_CXX::ARR_ATOM_VMIN_K_FMINXAT_HITO_VCCIA_FMIN_0400_COMBINED
FMINVmin=0.47
F1SetterIsFmin=False
FMINSetterIsTarget=True
PS C:\Projects\NVL\.docs> $summary='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_FINAL_VALIDATION_V4.csv'; $first=Import-Csv -LiteralPath $summary | Select-Object -First 1; $cols=$first.PSObject.Properties.Name; $rows=New-Object System.Collections.Generic.List[object]; foreach($c in $cols){ if($c -eq 'VisualID'){ continue }; if($c -match '^(?<Domain>.+)_FMIN_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C(?<Core>\d+)_(?<Metric>Vmin|Setter|MaxDTS_C|LP)$'){ $rows.Add([pscustomobject]@{ ColumnName=$c; Source='FMIN_FROM_TESTNAME'; Domain=$Matches['Domain']; Core=[int]$Matches['Core']; Corner='FMIN'; Flow='NA'; FreqGHz=$Matches['Freq']; Metric=$Matches['Metric']; JoinKeyNoMetric=("{0}|FMIN|NA|{1}|{2}" -f $Matches['Domain'],$Matches['Freq'],$Matches['Core']) }) | Out-Null; continue }; if($c -match '^(?<Domain>.+)_(?<Corner>F[^_]+)_Flow(?<Flow>[^_]+)_Freq(?<Freq>[0-9]+(?:\.[0-9]+)?)_C(?<Core>\d+)_(?<Metric>Vmin|Setter|MaxDTS_C|LP)$'){ $rows.Add([pscustomobject]@{ ColumnName=$c; Source='VMINFWCFG'; Domain=$Matches['Domain']; Core=[int]$Matches['Core']; Corner=$Matches['Corner']; Flow=$Matches['Flow']; FreqGHz=$Matches['Freq']; Metric=$Matches['Metric']; JoinKeyNoMetric=("{0}|{1}|{2}|{3}|{4}" -f $Matches['Domain'],$Matches['Corner'],$Matches['Flow'],$Matches['Freq'],$Matches['Core']) }) | Out-Null; continue }; $rows.Add([pscustomobject]@{ ColumnName=$c; Source='UNPARSED'; Domain=''; Core=''; Corner=''; Flow=''; FreqGHz=''; Metric=''; JoinKeyNoMetric='' }) | Out-Null }; $map='C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V4.csv'; $rows | Sort-Object Source,Domain,Corner,Flow,FreqGHz,Core,Metric | Export-Csv -LiteralPath $map -NoTypeInformation; "MergeMap=$map"; "UnparsedColumns=$(($rows | Where-Object { $_.Source -eq 'UNPARSED' }).Count)";
MergeMap=C:\Projects\NVL\.docs\Scripts\ILAS_Vmin_Summary_Y6220110_WW23_2026_MERGE_MAP_V4.csv
UnparsedColumns=0
PS C:\Projects\NVL\.docs> $ts=Get-Date -Format 'yyyyMMdd_HHmmss'; $out="C:\Projects\NVL\.docs\Scripts\_verify_weekly_${ts}"; New-Item -ItemType Directory -Path $out -Force | Out-Null; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_weekly_pull.ps1' -OutputDirectory $out -LastNDaysTestEnd 7 -ProgramPattern 'NVLHM66*'
Running AQUA pull...
AQUA command line tool
Report to run:   hmarkovi\BSAT_UPS2_POR_PTL_NVL WW12
Output file:     C:\Projects\NVL\.docs\Scripts\_verify_weekly_20260602_220612\_raw_20260602_220613.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
Ready. Writing results to C:\Projects\NVL\.docs\Scripts\_verify_weekly_20260602_220612\_raw_20260602_220613.csv
Done.

Waiting for AQUA output file to be created and stabilized...
Dropping 81 DS-IN-NA-GSDS_D_S::UPSVFPASSFLOW* column(s) immediately after pull...
Finalizing CSV output...
Running ILAS analysis for final UPSVF VisualID+lot pairs...
Using 42 lot(s) from UPSVF reference for ILAS pull.
Pulling ILAS VMIN_DTS from AQUA...
AQUA command line tool
Report to run:   sbelyy\ILAS\ILAS_VMIN_DTS
Output file:     C:\Projects\NVL\.docs\Scripts\_verify_weekly_20260602_220612\_ilas_weekly_20260602_220613\_ilas_raw_20260602_222025.csv
AQUA server:     HASAPP3301.ger.corp.intel.com
Waiting for AQUA to prepare report results...
PS C:\Projects\NVL\.docs> $raw='C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv'; $ups='\\ger\ec\proj\ha\mmgbd\MMGBD_PSA\Products\NVL\NVL-H\Weekly Runs\Vmin_NVLHM66A0H30M00S622_WW23_2026.csv'; $out='C:\Projects\NVL\.docs\Scripts\_verify_visualid_input_20260602'; New-Item -ItemType Directory -Path $out -Force | Out-Null; & 'C:\Projects\NVL\.docs\Scripts\aqua_nvlh_ilas_vmin_analysis.ps1' -RawInputFile $raw -UpsvfReferenceCsv $ups -OutputDirectory $out
Using 47 VisualID(s) from UPSVF reference for ILAS pull.
Using 1 lot(s) from UPSVF reference for ILAS pull.
Using existing ILAS raw file: C:\Projects\NVL\.docs\Scripts\_ilas_probe_20260602_153216.csv
Loaded 964810 rows from ILAS file.
Filtered ILAS rows by UPSVF VisualID+lot keys: 964810 -> 964810
Detected stacked ILAS format (TEST_NAME/TEST_RESULT).
Built 26140 detail records.

Detail CSV  : C:\Projects\NVL\.docs\Scripts\_verify_visualid_input_20260602\ILAS_Vmin_Detail_WW23_2026.csv
Summary CSV : C:\Projects\NVL\.docs\Scripts\_verify_visualid_input_20260602\ILAS_Vmin_Summary_WW23_2026.csv
Units       : 47
Domain/Freq : 69
Detail rows : 26140

---

### Assistant

Perfect timing, this confirms all three points you asked.

Live polling status
1. Still active for weekly run in terminal 76b73376-ce7d-4b58-be9c-866321565350.
2. Current stage: ILAS AQUA pull is running and waiting on AQUA report readiness.
3. Offline verification terminal 5fe16782-1808-48a5-893d-135612ed29e5 completed successfully.

About SKILL.md naming
1. Yes, `SKILL.md` is the standard filename for each skill.
2. It is normal that both skills use the same filename.
3. Uniqueness comes from folder path plus `name` in frontmatter, not from filename.
4. So this is correct and important for discoverability.

What each skill does

1. ILAS skill
File: [.github/skills/ilas/SKILL.md](.github/skills/ilas/SKILL.md)
Purpose:
1. ILAS data extraction/parsing only.
2. Stacked `TEST_NAME/TEST_RESULT` handling.
3. Strict VMIN parsing with VMINFWCFG positional mapping.
4. FMIN separation and exclusion from main F-corner max path.
5. Optional UPSVF reference filtering (VisualID+lot).

Does ILAS skill include your weekly merge steps 1-6?
1. No, not as orchestration logic.
2. It supports prerequisite filtering needed by weekly flow, but not the full weekly automation/merge control loop.

2. Weekly UPSVF-ILAS merge skill
File: [.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md](.github/skills/nvlh-weekly-upsvf-ilas-merge/SKILL.md)
Purpose:
1. Weekly UPSVF automation.
2. Trigger ILAS after UPSVF success.
3. Pass UPSVF reference to ILAS.
4. Merge ILAS columns into weekly UPSVF CSV.
5. Failure isolation.
6. Frequency-scoped cleanup.

This one is the skill that covers your 1-6 workflow.

Your key concern: “Is ILAS AQUA query using UPSVF Visual_ID input?”
Confirmed yes, with runtime evidence from your latest run:

1. `Using 47 VisualID(s) from UPSVF reference for ILAS pull.`
2. `Using 1 lot(s) from UPSVF reference for ILAS pull.`

That proves the automation now takes Visual_ID input from UPSVF reference for ILAS pull construction.

Current coverage check (from your own weekly file)
1. UPSVF rows: 55
2. UPSVF unique Visual_ID: 47
3. ILAS unique Visual_ID: 47
4. Missing in ILAS: 0
5. Extra in ILAS: 0

Why 47 then:
1. Because uniqueness is 47 for this weekly file, not because ILAS dropped units.

I will continue live polling and report as soon as the in-flight weekly ILAS AQUA stage exits with final output files.

---

## User — Message 41

ok continue as planned. do not ask for perrmission I will not be by the computer. in the final response give a link to the validation folder for me to manually validate

---

### Assistant

Continuing exactly as planned without prompts; I’m polling the live weekly run to completion and will provide a direct validation-folder link in the final response.

---

### Assistant

The live run has advanced through ILAS AQUA write; I’m now collecting the generated verification artifacts and status files so I can give you the final validation folder link and key outputs.

---

### Assistant

I’m checking the latest run tail now; if it failed before merge, I’ll immediately rerun only the ILAS+merge part in the same validation folder so you still get a complete manual-validation package.

---

### Assistant

I’m still tracking completion; I’ll now check for ILAS completion markers (`Detail CSV`, `Summary CSV`, `ILAS merge completed`) in the live terminal stream and only then finalize the validation package link.

---

### Assistant

Proceeding without prompts, and I’ve already prepared a full manual-validation package now while live AQUA polling continues.

Manual validation folder (ready now):
- [Scripts/_verify_weekly_offline_20260602](Scripts/_verify_weekly_offline_20260602)

Key files in that folder:
- [Scripts/_verify_weekly_offline_20260602/UPSVF_base.csv](Scripts/_verify_weekly_offline_20260602/UPSVF_base.csv)
- [Scripts/_verify_weekly_offline_20260602/UPSVF_with_ILAS_merged.csv](Scripts/_verify_weekly_offline_20260602/UPSVF_with_ILAS_merged.csv)
- [Scripts/_verify_weekly_offline_20260602/ILAS/ILAS_Vmin_Detail_WW23_2026.csv](Scripts/_verify_weekly_offline_20260602/ILAS/ILAS_Vmin_Detail_WW23_2026.csv)
- [Scripts/_verify_weekly_offline_20260602/ILAS/ILAS_Vmin_Summary_WW23_2026.csv](Scripts/_verify_weekly_offline_20260602/ILAS/ILAS_Vmin_Summary_WW23_2026.csv)

Current live run folder (still in progress on AQUA/ILAS stage):
- [Scripts/_verify_weekly_20260602_220612](Scripts/_verify_weekly_20260602_220612)

Confirmed in logs from updated ILAS flow:
- VisualID input is taken from UPSVF reference (`Using 47 VisualID(s) from UPSVF reference for ILAS pull.`).

---

## User — Message 42

to close this thread, I would like to make sure that this file construction will automatically excuted every Sunday? with the next specification:
1. UPS data will be pulled every Sunday, I want to change the timing to 5AM israeli time. instead of 8AM
2. UPS complition triggers the ILAS data extraction, for the Visual ID units that exists in the UPS final file
3. if the Ilas reports fails- UPS weekly pull and the saved file will still be viable without merge
4. a log file with every WW status will be updated for all runs, if there are no problems only one merge file UPS+ILAS will be saved. 
all file formats logs and outputare .csv

---

### Assistant

I’ll verify and update the Sunday scheduler now so it runs at 5:00 AM Israel time, then I’ll confirm the weekly UPS→ILAS trigger/failure behavior and adjust logging/output so it matches your final 4-point closure requirements.

---

### Assistant

I’m now applying the closure updates: scheduler to Sunday 05:00 Israel time, CSV-only run logging, and single final output behavior (no extra clean artifact unless explicitly requested). Then I’ll register the updated task.

---

### Assistant

I’ve identified the exact blocks to change in the weekly script and scheduler script. I’m now patching them to remove markdown logs, keep CSV-only logging, and default to a single final merged CSV artifact.

---

### Assistant

The two scripts are patched. I’ll run a quick syntax/error check and then register the scheduled task with the new 05:00 Sunday trigger.

---

### Assistant

I’ll quickly verify the current script and task-registration state so I can confirm exactly what was completed before the drop and what, if anything, is still pending.

---

### Assistant

I verified the script changes are present; I’ll do one final scheduler check (`TaskName`, next run time, weekly Sunday 05:00) and then confirm exactly what was finished before the drop.

---

### Assistant

I found one important issue from the task XML: the scheduled action was registered with broken arguments (`-File \`) and wrong working directory, so I’m fixing the registration script now and re-registering the task correctly.

---
