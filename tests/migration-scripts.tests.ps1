# Run with: pwsh -NoProfile -File tests/migration-scripts.tests.ps1
# gh is mocked for every command; these tests never contact GitHub.
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("lightning-tracker-tests-" + [guid]::NewGuid())
$global:trackerTestGhCalls = [Collections.Generic.List[object]]::new()
$global:trackerTestCreateNumber = 100
$global:trackerTestFailComment = $false
$global:trackerTestFailCreate = $false
$global:trackerTestIssues = @(
    [PSCustomObject]@{
        number = 7; title = 'Open issue'; state = 'OPEN'; body = 'Original body'
        author = @{ login = 'reporter' }; assignees = @(@{ login = 'assignee' })
        labels = @(@{ name = 'Bug' }); milestone = @{ title = 'First' }
        createdAt = '2026-01-01'; updatedAt = '2026-01-02'
        comments = @(@{ author = @{ login = 'commenter' }; body = "First line`nSecond line"; createdAt = '2026-01-02' })
    },
    [PSCustomObject]@{
        number = 8; title = 'Closed issue'; state = 'CLOSED'; body = ''
        author = $null; assignees = @(); labels = @(); milestone = @{ title = 'Second' }
        createdAt = '2026-01-01'; updatedAt = '2026-01-02'; comments = @()
    }
)

function Assert-True($condition, [string]$message) {
    if (-not $condition) { throw "Assertion failed: $message" }
}

function gh {
    $callArgs = @($args)
    $global:trackerTestGhCalls.Add($callArgs)
    $global:LASTEXITCODE = 0
    if ($callArgs[0] -eq 'issue' -and $callArgs[1] -eq 'list') {
        Assert-True ($callArgs[-1] -like '*author*') 'source export must request the original author'
        return ConvertTo-Json -InputObject $global:trackerTestIssues -Depth 10 -Compress
    }
    if ($callArgs[0] -eq 'api' -and $callArgs[1] -like '*/milestones') {
        Assert-True ($callArgs -contains '--paginate' -and $callArgs -contains '--slurp') 'milestones must retain JSON arrays across pages'
        Assert-True ($callArgs -contains 'state=all') 'closed milestones must be available for mapping'
        return '[[{"title":"First","number":11}],[{"title":"Second","number":22}]]'
    }
    if ($callArgs[0] -eq 'issue' -and $callArgs[1] -eq 'create') {
        $global:trackerTestCreateNumber++
        if ($global:trackerTestFailCreate -and $callArgs -contains 'Closed issue') { $global:LASTEXITCODE = 1 }
        return "https://github.com/Test/Target/issues/$global:trackerTestCreateNumber"
    }
    if ($callArgs[0] -eq 'api' -and $callArgs -contains 'PATCH') {
        Assert-True ($callArgs -contains '-F') 'milestone must be sent as a typed integer'
        return
    }
    if ($callArgs[0] -eq 'issue' -and $callArgs[1] -in @('comment', 'close')) {
        if ($global:trackerTestFailComment -and $callArgs[1] -eq 'comment') { $global:LASTEXITCODE = 1 }
        return
    }
    throw "Unexpected mocked gh command: $($callArgs -join ' ')"
}

function Assert-SourceClosure {
    $comments = @($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'issue' -and $_[1] -eq 'comment' })
    Assert-True ($comments.Count -eq 2) 'both source issues must receive their own migration link'
    Assert-True ($comments[0] -contains 'This issue has been migrated to Test/Target#101. Please continue discussion there.') 'first target number must survive script generation'
    Assert-True ($comments[1] -contains 'This issue has been migrated to Test/Target#102. Please continue discussion there.') 'second target number must survive script generation'
    $closures = @($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'issue' -and $_[1] -eq 'close' })
    Assert-True ($closures.Count -eq 1 -and $closures[0][2] -eq '7') 'only the originally open source issue must be closed'
}

try {
    $fixtureScripts = Join-Path $testRoot 'scripts'
    New-Item -ItemType Directory -Path $fixtureScripts -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/migrate-issues.ps1') -Destination $fixtureScripts
    $migrationScript = Join-Path $fixtureScripts 'migrate-issues.ps1'
    & $migrationScript -SourceRepo 'Test/Source' -TargetRepo 'Test/Target' -DelayMs 0

    $creates = @($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'issue' -and $_[1] -eq 'create' })
    Assert-True ($creates.Count -eq 2) 'both issues must be created'
    $firstBody = $creates[0][[array]::IndexOf($creates[0], '--body') + 1]
    Assert-True ($firstBody -like '*Original author:** @reporter*' -and $firstBody -notlike '*@assignee*') 'reporter must not be replaced by the assignee'
    Assert-True ($firstBody -like '*@commenter*Second line*') 'original comment authors and text must be retained'
    $closed = @($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'issue' -and $_[1] -eq 'close' })
    Assert-True ($closed[0] -contains 'Automatically closed — was CLOSED in Test/Source#8') 'closure comment must reference its source issue'
    $patches = @($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'api' -and $_ -contains 'PATCH' })
    Assert-True ($patches.Count -eq 2 -and $patches[1] -contains 'milestone=22') 'milestones from later pages must be applied'
    $mapping = @(Import-Csv (Join-Path $testRoot '_migration_map.csv'))
    Assert-True ($mapping[0].State -eq 'OPEN' -and $mapping[1].State -eq 'CLOSED') 'mapping must retain the original states'

    $generatedScript = Join-Path $fixtureScripts 'close-source-issues.ps1'
    $global:trackerTestGhCalls.Clear()
    & $generatedScript
    Assert-SourceClosure

    # The checked-in companion must still accept historical Source/Target CSVs.
    $companion = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/close-source-issues.ps1') -Raw
    $companion = $companion.Replace('FsLightning/LightningCADTracker', 'Test/Target').Replace('FsLightning/LightningCAD', 'Test/Source')
    Set-Content -LiteralPath $generatedScript -Value $companion -Encoding utf8
    @(@{ Source = 7; Target = 101 }, @{ Source = 8; Target = 102 }) | Export-Csv (Join-Path $testRoot '_migration_map.csv') -NoTypeInformation
    $global:trackerTestGhCalls.Clear()
    & $generatedScript
    Assert-SourceClosure

    $global:trackerTestFailComment = $true
    $global:trackerTestGhCalls.Clear()
    & $generatedScript
    Assert-True (@($global:trackerTestGhCalls | Where-Object { $_[0] -eq 'issue' -and $_[1] -eq 'close' }).Count -eq 0) 'a failed migration comment must not close the source issue'
    $global:trackerTestFailComment = $false

    Copy-Item -LiteralPath (Join-Path $repositoryRoot '_migrate_now.ps1') -Destination $testRoot
    $global:trackerTestFailCreate = $true
    $global:trackerTestGhCalls.Clear()
    & (Join-Path $testRoot '_migrate_now.ps1')
    $mapping = @(Import-Csv (Join-Path $testRoot '_migration_map.csv'))
    Assert-True ($mapping.Count -eq 1 -and $mapping[0].SourceNumber -eq '7' -and $mapping[0].State -eq 'OPEN') 'failed issue creation must not enter the canonical mapping'
    Write-Host 'PASS: migration metadata, milestone types/pages, generated/legacy closure, failed commands, portable paths.'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
        if ($resolvedTestRoot -ne $testRoot -or -not $resolvedTestRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected test cleanup path: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
