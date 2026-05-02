# =============================
# Network Health Monitor Script
# =============================

# -------- CONFIGURATION --------
$config = [ordered]@{
    Targets = @(
        @{ Name = "Google"; Host = "8.8.8.8"; Ports = @(53,443) }
        @{ Name = "Cloudflare"; Host = "1.1.1.1"; Ports = @(53) }
        @{ Name = "LocalGateway"; Host = "192.168.1.1"; Ports = @(80,443) }
    )
    Count        = 2
    Timeout      = 2000
    OutputFolder = "C:\Temp\NetMonitor"
    LogFile      = "NetworkResults.csv"
}

# -------- SETUP --------
if (-not (Test-Path $config.OutputFolder)) {
    New-Item -Path $config.OutputFolder -ItemType Directory | Out-Null
}

$results = @()

# -------- FUNCTIONS --------
function Test-NetworkTarget {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Target
    )

    $pingParams = [ordered]@{
        ComputerName = $Target.Host
        Count        = $config.Count
        ErrorAction  = "SilentlyContinue"
    }

    $pingResult = Test-Connection @pingParams

    $latency = if ($pingResult) {
        ($pingResult | Measure-Object -Property ResponseTime -Average).Average
    } else {
        $null
    }

    $dnsParams = [ordered]@{
        Name = $Target.Host
        ErrorAction = "SilentlyContinue"
    }

    $dnsResult = Resolve-DnsName @dnsParams

    $portResults = @()

    foreach ($port in $Target.Ports) {
        $tcpParams = [ordered]@{
            ComputerName = $Target.Host
            Port         = $port
            WarningAction = "SilentlyContinue"
        }

        $tcpTest = Test-NetConnection @tcpParams

       $portResults += "${port}:$($tcpTest.TcpTestSucceeded)"
    }

    return [PSCustomObject]@{
        Name        = $Target.Name
        Host        = $Target.Host
        PingSuccess = [bool]$pingResult
        AvgLatency  = [math]::Round($latency,2)
        DNSResolved = [bool]$dnsResult
        Ports       = ($portResults -join ", ")
        Timestamp   = (Get-Date)
    }
}

# -------- MAIN EXECUTION --------
foreach ($target in $config.Targets) {
    $results += Test-NetworkTarget -Target $target
}

# -------- EXPORT --------
$csvPath = Join-Path $config.OutputFolder $config.LogFile
$results | Export-Csv -Path $csvPath -NoTypeInformation -Append

# -------- HTML REPORT --------
$htmlParams = [ordered]@{
    Title = "Network Health Report"
    PreContent = "<h1>Network Monitoring Dashboard</h1>"
}

$html = $results | ConvertTo-Html @htmlParams

$htmlPath = Join-Path $config.OutputFolder "NetworkReport.html"
$html | Out-File $htmlPath

Write-Host "Report generated: $htmlPath"

$taskParams = [ordered]@{
    Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Scripts\NetworkMonitor.ps1"
    Trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date)
    TaskName = "NetworkMonitor"
    Description = "Runs network monitoring script every 5 minutes"
}

Register-ScheduledTask @taskParams