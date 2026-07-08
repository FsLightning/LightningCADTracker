<#====================================================================
  FsHolu Issue Migration Tool
  ====================================================================
  DESCRIPTION:
    Batch-migrate all issues from one GitHub repo to another.
    Preserves title, body, labels, milestone, state (open/closed),
    and appends original comments as timeline in the issue body.

  USAGE:
    .\scripts\migrate-issues.ps1 -SourceRepo "Owner/SourceRepo" `
                                 -TargetRepo "Owner/TargetRepo" `
                                 [-ExportFile "issues.json"] `
                                 [-DelayMs 200]

  PREREQUISITES:
    - gh CLI installed and authenticated
    - PowerShell 7+
    - Target repo already has the same labels & milestones created

  WHAT IT DOES:
    1. Exports all issues (with comments) from SourceRepo to JSON
    2. Reads milestones from TargetRepo for mapping
    3. For each issue (sorted by number ascending):
       a. Creates a new issue with original body + migration footer
       b. Applies labels and milestone
       c. Closes if source issue was closed
    4. Saves a CSV mapping of old# -> new#
    5. Generates a companion script to mark+close source issues

  NOTES:
    - Issue numbers WILL change (GitHub doesn't allow preserving them)
    - Author attribution is preserved in the body footer
    - Cross-references like #123 need manual replacement
    - The migration is NOT reversible — backup source data first

  EXAMPLE:
    .\scripts\migrate-issues.ps1 -SourceRepo "Org/ProjectA" `
                                 -TargetRepo "Org/ProjectA-Tracker"
#===================================================================#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRepo,

    [Parameter(Mandatory = $true)]
    [string]$TargetRepo,

    [Parameter(Mandatory = $false)]
    [string]$ExportFile = "_migration_issues.json",

    [Parameter(Mandatory = $false)]
    [int]$DelayMs = 250
)

# Resolve paths
$scriptDir = Split-Path -Parent $PSScriptRoot
$exportPath = Join-Path $scriptDir $ExportFile
$mapPath = Join-Path $scriptDir "_migration_map.csv"

# ---- Step 1: Export all issues from source ----
Write-Host "=== Step 1: Exporting issues from $SourceRepo ===" -ForegroundColor Cyan
$jsonRaw = gh issue list -R $SourceRepo --state all --limit 1000 `
    --json number,title,state,labels,milestone,assignees,body,createdAt,updatedAt,comments 2>&1
$jsonRaw | Set-Content $exportPath -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to export issues from $SourceRepo" -ForegroundColor Red
    exit 1
}

$issues = Get-Content $exportPath -Raw | ConvertFrom-Json
$total = $issues.Count
Write-Host "Exported $total issues ($($issues | Group-Object state | ForEach-Object { "$($_.Name)=$($_.Count)" }))" -ForegroundColor Green

# ---- Step 2: Load milestones from target ----
Write-Host "`n=== Step 2: Loading milestones from $TargetRepo ===" -ForegroundColor Cyan
$milestones = gh api repos/$TargetRepo/milestones --jq '.[] | {title, number}' | ConvertFrom-Json
$milestoneMap = @{}
$milestones | ForEach-Object { $milestoneMap[$_.title] = $_.number }

# ---- Helper: Format issue body with migration footer ----
function Format-Body($issue) {
    $body = $issue.body
    if ([string]::IsNullOrEmpty($body)) { $body = "*(No description provided)*" }

    # Build author string
    $author = if ($issue.assignees.Count -gt 0) {
        "@" + ($issue.assignees.login -join ", @")
    } else {
        "*(Unassigned)*"
    }

    $oldRef = "$SourceRepo#$($issue.number)"

    $footer = @"
---
> **Migrated from ${oldRef}**
> **Original author:** $author
> **Created:** $($issue.createdAt)
> **Updated:** $($issue.updatedAt)
"@

    # Append comments in chronological order
    if ($issue.comments -and $issue.comments.Count -gt 0) {
        $footer += "`n`n### Original Comments`n"
        foreach ($c in $issue.comments) {
            $commentBody = $c.body -replace "`n", "`n> "
            $footer += "`n---`n**@$($c.author.login)** on $($c.createdAt):`n> $commentBody`n"
        }
    }

    return $body + "`n`n" + $footer
}

# ---- Step 3: Migrate ----
Write-Host "`n=== Step 3: Migrating $total issues ===" -ForegroundColor Cyan
Write-Host ("=" * 55)

# Sort numerically by issue number
$issues = $issues | Sort-Object { [int]$_.number }

$createdCount = 0
$migrationMap = @{}

foreach ($issue in $issues) {
    $oldNum = $issue.number
    $title = $issue.title
    $body = Format-Body $issue
    $labels = if ($issue.labels -and $issue.labels.Count -gt 0) { $issue.labels.name -join "," } else { $null }
    $milestoneNum = if ($issue.milestone -and $milestoneMap.ContainsKey($issue.milestone.title)) { $milestoneMap[$issue.milestone.title] } else { $null }
    $state = $issue.state

    Write-Host "[#$oldNum → ?] $title" -ForegroundColor Yellow

    # Build args
    $args = @("issue", "create", "-R", $TargetRepo, "--title", $title, "--body", $body)
    if ($labels) { $args += "--label"; $args += $labels }

    $newUrl = & gh @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED: $newUrl" -ForegroundColor Red
        continue
    }

    $newNum = ($newUrl -split "/")[-1]
    $migrationMap[$oldNum] = $newNum
    Write-Host "  -> #${newNum}" -ForegroundColor Green

    # Set milestone via API
    if ($milestoneNum) {
        gh api repos/$TargetRepo/issues/$newNum -X PATCH -f milestone=$milestoneNum --silent 2>&1 | Out-Null
    }

    # Close if source was closed
    if ($state -eq "CLOSED") {
        gh issue close $newNum -R $TargetRepo `
            --comment "Automatically closed — was CLOSED in $oldRef" 2>&1 | Out-Null
    }

    $createdCount++

    # Throttle to avoid rate limits
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host "Migration complete! $createdCount / $total issues created." -ForegroundColor Green

# ---- Step 4: Save mapping ----
$migrationMap.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{ SourceNumber = $_.Key; TargetNumber = $_.Value }
} | Export-Csv $mapPath -NoTypeInformation
Write-Host "Mapping saved to: $mapPath" -ForegroundColor Cyan

# ---- Step 5: Generate close-source script ----
$closeScript = @"
# Close-SourceIssues.ps1
# Generated by migrate-issues.ps1
# Run this to add a migration link comment and close all open source issues

`$sourceRepo = "$SourceRepo"
`$map = Import-Csv "$mapPath"
`$closedCount = 0

foreach (`$row in `$map) {
    `$oldNum = `$row.SourceNumber
    `$newNum = `$row.TargetNumber
    `$comment = "This issue has been migrated to $TargetRepo#$newNum. Please continue discussion there."

    Write-Host "[#$oldNum] Adding comment and closing..."
    gh issue comment `$oldNum -R `$sourceRepo --body "`$comment" 2>&1 | Out-Null
    if (`$row.State -eq "OPEN") {
        gh issue close `$oldNum -R `$sourceRepo --comment "Migrated to $TargetRepo" 2>&1 | Out-Null
    }
    `$closedCount++
    Start-Sleep -Milliseconds 200
}
Write-Host "Done! Processed `$closedCount source issues." -ForegroundColor Green
"@

$closeScriptPath = Join-Path $scriptDir "scripts\close-source-issues.ps1"
$closeScript | Set-Content $closeScriptPath -Encoding UTF8
Write-Host "Close-source script generated: $closeScriptPath" -ForegroundColor Cyan

Write-Host "`n=== Done! ===" -ForegroundColor Green
