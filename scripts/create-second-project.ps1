$baseUrl = 'http://localhost:5203/api/components'
$systemName = 'Performance Test System'
$projectName = 'Second Project'
$severities = @('ok', 'warning', 'error', 'info')

Write-Host 'Creating 500 components in Second Project...'

for ($i = 1; $i -le 500; $i++) {
    $severity = $severities[$i % $severities.Count]
    $body = @{
        systemName = $systemName
        projectName = $projectName
        payload = @{
            Id = "second-$i"
            Name = "Second Project Component $i"
            Severity = $severity
            Value = [math]::Round((Get-Random -Minimum 0 -Maximum 100), 2)
            Metric = 'Performance %'
            Description = "Component $i in second project"
        }
    } | ConvertTo-Json -Depth 3

    $null = Invoke-RestMethod -Uri $baseUrl -Method Post -Body $body -ContentType 'application/json'

    if ($i % 100 -eq 0) { Write-Host "Progress: $i / 500" }
}
Write-Host 'Done!'
