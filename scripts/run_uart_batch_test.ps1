param(
    [ValidateSet("mnist10","mnist100","mnist1000","mnist_random1000","mnist10000","mnist_debug_7450")][string]$Dataset = "mnist10",
    [string]$PortName = "COM4",
    [int]$BaudRate = 115200,
    [int]$ReadTimeoutMs = 120000
)
$ErrorActionPreference = "Stop"
$project = "D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn"
$folder = Join-Path $project "validation\$Dataset"
$manifestPath = Join-Path $folder "manifest.csv"
$outDir = Join-Path $project "validation\results"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
if (!(Test-Path $manifestPath)) { throw "Missing $manifestPath. Run the exporter first." }
$manifest = @(Import-Csv $manifestPath)
if (!$manifest.Count) { throw "Manifest is empty." }

$serial = [System.IO.Ports.SerialPort]::new($PortName,$BaudRate,'None',8,'One')
$serial.ReadTimeout = $ReadTimeoutMs
$serial.WriteTimeout = 15000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$results = [System.Collections.Generic.List[object]]::new()
$correct = 0
$commErrors = 0
$serial.Open()
try {
    Start-Sleep -Milliseconds 300
    for ($i=0; $i -lt $manifest.Count; $i++) {
        $row = $manifest[$i]
        $path = Join-Path $folder $row.image_file
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $pred = $null; $status = "ERROR"; $err = ""
        try {
            $lines = @(Get-Content -LiteralPath $path)
            if ($lines.Count -ne 784) { throw "Expected 784 pixels; got $($lines.Count)" }
            [byte[]]$pixels = foreach ($line in $lines) {
                $v = $line.Trim()
                if ($v -notmatch '^[0-9A-Fa-f]{2}$') { throw "Invalid pixel '$v'" }
                [Convert]::ToByte($v,16)
            }
            [byte[]]$packet = @(0xA5,0x5A) + $pixels
            $serial.DiscardInBuffer()
            $serial.Write($packet,0,$packet.Length)
            $pred = $serial.ReadByte()
            $trueLabel = [int]$row.true_label
            if ($pred -eq $trueLabel) {
                $status = "PASS"; $correct++
                Write-Host ("[{0}/{1}] true={2}, predicted={3}: PASS" -f ($i+1),$manifest.Count,$trueLabel,$pred) -ForegroundColor Green
            } else {
                $status = "MISCLASSIFIED"
                Write-Host ("[{0}/{1}] true={2}, predicted={3}: MISMATCH" -f ($i+1),$manifest.Count,$trueLabel,$pred) -ForegroundColor Yellow
            }
        } catch {
            $err = $_.Exception.Message; $commErrors++
            Write-Host ("[{0}/{1}] ERROR: {2}" -f ($i+1),$manifest.Count,$err) -ForegroundColor Red
        }
        $timer.Stop()
        $results.Add([PSCustomObject]@{
            SampleId=$row.sample_id; MnistIndex=$row.mnist_index; TrueLabel=[int]$row.true_label
            PredictedLabel=$(if ($null -eq $pred) { "" } else { $pred })
            Status=$status; Correct=($status -eq "PASS")
            HostRoundTripSeconds=[math]::Round($timer.Elapsed.TotalSeconds,4)
            Error=$err; ImageFile=$row.image_file
        })
        Start-Sleep -Milliseconds 300
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
$total = $manifest.Count
$responses = @($results | Where-Object { $_.Status -in @("PASS","MISCLASSIFIED") }).Count
$mis = @($results | Where-Object Status -eq "MISCLASSIFIED").Count
$acc = if ($responses) { 100.0*$correct/$responses } else { 0.0 }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csv = Join-Path $outDir "${Dataset}_results_${stamp}.csv"
$json = Join-Path $outDir "${Dataset}_summary_${stamp}.json"
$results | Export-Csv $csv -NoTypeInformation
$summary = [PSCustomObject]@{
    Dataset=$Dataset; Timestamp=(Get-Date).ToString("o"); Port=$PortName; BaudRate=$BaudRate
    TotalImages=$total; ResponsesReceived=$responses; CorrectPredictions=$correct
    Misclassifications=$mis; CommunicationErrors=$commErrors
    AccuracyAmongResponsesPercent=[math]::Round($acc,2)
    AccuracyOverAllAttemptsPercent=[math]::Round(100.0*$correct/$total,2)
    Note="Host round-trip includes serial transfer and response, not pure FPGA compute latency."
    ResultsCsv=$csv
}
$summary | ConvertTo-Json -Depth 4 | Set-Content $json -Encoding UTF8
Write-Host "`n===== FPGA BATCH VALIDATION SUMMARY =====" -ForegroundColor Cyan
$summary | Format-List
Write-Host "Per-image CSV: $csv"
Write-Host "Summary JSON: $json"
