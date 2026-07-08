<#
  LightningCAD → LightningCADTracker Migration
  Usage: pwsh -File _migrate_now.ps1
#>
$targetRepo = "FsLightning/LightningCADTracker"
$jsonFile = "D:\MakeX\Envelop\Lightning\LightningCADTracker\_migration_issues.json"

Write-Host "Loading $jsonFile..." -ForegroundColor Cyan
$issues = Get-Content $jsonFile -Encoding UTF8 -Raw | ConvertFrom-Json
$total = $issues.Count
Write-Host "Found $total issues" -ForegroundColor Green

$issues = $issues | Sort-Object { [int]$_.number }
$map = @{}
$i = 0

foreach ($issue in $issues) {
    $i++; $oldNum = $issue.number
    $body = if ($issue.body) { $issue.body } else { "*(No description)*" }
    $footer = "`n---`n> **Migrated from FsLightning/LightningCAD#$oldNum** | **Created:** $($issue.createdAt)"
    if ($issue.comments -and $issue.comments.Count -gt 0) {
        $footer += "`n`n### Original Comments`n"
        foreach ($c in $issue.comments) {
            $cb = $c.body -replace "`n", "`n> "
            $footer += "`n---`n**@$($c.author.login)** on $($c.createdAt):`n> $cb`n"
        }
    }
    $fullBody = $body + $footer
    $labels = if ($issue.labels -and $issue.labels.Count -gt 0) { ($issue.labels.name -join ",") } else { $null }

    Write-Host "[$i/$total] #$oldNum -> $($issue.title)" -ForegroundColor Yellow
    if ($labels) {
        $url = gh issue create -R $targetRepo --title $issue.title --body $fullBody --label $labels 2>&1
    } else {
        $url = gh issue create -R $targetRepo --title $issue.title --body $fullBody 2>&1
    }
    if ($url -match "/(\d+)$") {
        $newNum = $Matches[1]; $map[$oldNum] = $newNum
        Write-Host "  -> #$newNum" -ForegroundColor Green
        if ($issue.state -eq "CLOSED") {
            gh issue close $newNum -R $targetRepo --comment "Closed - was CLOSED in source" 2>&1 | Out-Null
        }
    } else {
        Write-Host "  FAILED: $url" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 100
}

$map.GetEnumerator() | ForEach-Object { [PSCustomObject]@{Source=$_.Key;Target=$_.Value} } | Export-Csv "D:\MakeX\Envelop\Lightning\LightningCADTracker\_migration_map.csv" -NoTypeInformation
Write-Host "`nDone! $i/$total migrated." -ForegroundColor Green