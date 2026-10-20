
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$imageDir = Join-Path $root "validation\mnist_random1000"
$portName = "COM4"
$baudRate = 115200

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = Join-Path $root "validation\results\live_results_$timestamp.csv"
New-Item -ItemType Directory -Force `
    -Path (Split-Path $csvPath) | Out-Null

$files = @(Get-ChildItem $imageDir -Filter "sample_*.mem" -File)
if ($files.Count -eq 0) {
    throw "No sample_*.mem files found in $imageDir"
}

$tested = 0
$correct = 0
$wrong = 0
$errors = 0
$csvInitialized = $false
$random = [System.Random]::new()

function Save-LiveResult($row) {
    if (!$script:csvInitialized) {
        $row | Export-Csv -Path $script:csvPath -NoTypeInformation
        $script:csvInitialized = $true
    } else {
        $row | Export-Csv -Path $script:csvPath -NoTypeInformation -Append
    }
}

function Show-LiveSummary {
    $responses = $script:correct + $script:wrong
    $accuracy = if ($responses -gt 0) {
        [Math]::Round(100.0 * $script:correct / $responses, 2)
    } else { 0 }

    Write-Host ""
    Write-Host "========== LIVE MNIST SUMMARY ==========" -ForegroundColor Cyan
    Write-Host "Images attempted:       $script:tested"
    Write-Host "Correct predictions:    $script:correct" -ForegroundColor Green
    Write-Host "Misclassifications:     $script:wrong" -ForegroundColor Yellow
    Write-Host "UART/image errors:      $script:errors" -ForegroundColor Red
    Write-Host "Valid responses:        $responses"
    Write-Host "Accuracy among responses: $accuracy%"
    Write-Host "CSV log: $script:csvPath"
    Write-Host "========================================"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Basys3 Live MNIST UART Viewer"
$form.ClientSize = New-Object System.Drawing.Size(500, 470)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(110, 15)
$picture.Size = New-Object System.Drawing.Size(280, 280)
$picture.SizeMode = "Zoom"
$picture.BorderStyle = "FixedSingle"
$form.Controls.Add($picture)

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(15, 305)
$status.Size = New-Object System.Drawing.Size(470, 35)
$status.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$status.TextAlign = "MiddleCenter"
$status.Text = "Connecting..."
$form.Controls.Add($status)

$details = New-Object System.Windows.Forms.Label
$details.Location = New-Object System.Drawing.Point(10, 345)
$details.Size = New-Object System.Drawing.Size(480, 45)
$details.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$details.TextAlign = "MiddleCenter"
$form.Controls.Add($details)

$stats = New-Object System.Windows.Forms.Label
$stats.Location = New-Object System.Drawing.Point(10, 395)
$stats.Size = New-Object System.Drawing.Size(480, 45)
$stats.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$stats.TextAlign = "MiddleCenter"
$stats.Text = "Images: 0 | Correct: 0 | Wrong: 0 | Errors: 0"
$form.Controls.Add($stats)

$serial = $null
$bitmap = $null

try {
    $serial = [System.IO.Ports.SerialPort]::new(
        $portName, $baudRate,
        [System.IO.Ports.Parity]::None, 8,
        [System.IO.Ports.StopBits]::One
    )
    $serial.ReadTimeout = 5000
    $serial.WriteTimeout = 3000
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.Open()

    Write-Host "Live MNIST test started." -ForegroundColor Cyan
    Write-Host "Serial port: $portName at $baudRate baud"
    Write-Host "CSV log: $csvPath"
    Write-Host "Close the viewer window to stop."
    Write-Host ""

    $form.Show()
    $form.Refresh()

    while ($form.Visible) {
        $ordered = @($files | Sort-Object { $random.Next() })

        foreach ($file in $ordered) {
            if (!$form.Visible) { break }

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $tested++
            $trueLabel = -1
            $prediction = $null
            $resultStatus = "IMAGE_ERROR"
            $message = ""

            try {
                $match = [regex]::Match($file.Name, 'label_(\d+)')
                if (!$match.Success) {
                    throw "Cannot determine true label from filename"
                }
                $trueLabel = [int]$match.Groups[1].Value

                $pixels = @(
                    Get-Content $file.FullName |
                    Where-Object { $_.Trim() -ne '' } |
                    ForEach-Object { [Convert]::ToInt32($_.Trim(), 16) }
                )

                if ($pixels.Count -ne 784) {
                    throw "Expected 784 pixels; found $($pixels.Count)"
                }

                $bitmap = New-Object System.Drawing.Bitmap(28, 28)
                for ($y = 0; $y -lt 28; $y++) {
                    for ($x = 0; $x -lt 28; $x++) {
                        $v = [Math]::Max(
                            0, [Math]::Min(255, $pixels[$y * 28 + $x])
                        )
                        $c = [System.Drawing.Color]::FromArgb($v, $v, $v)
                        $bitmap.SetPixel($x, $y, $c)
                    }
                }

                $oldImage = $picture.Image
                $picture.Image = $bitmap
                $bitmap = $null
                if ($oldImage) { $oldImage.Dispose() }

                $status.Text = "Sending image $tested to FPGA..."
                $details.Text = "$($file.Name) | True label: $trueLabel"
                $form.Refresh()
                [System.Windows.Forms.Application]::DoEvents()

                [byte[]]$packet = New-Object byte[] 786
                $packet[0] = 0xA5
                $packet[1] = 0x5A

                for ($i = 0; $i -lt 784; $i++) {
                    $packet[$i + 2] = [byte]$pixels[$i]
                }

                $serial.DiscardInBuffer()
                $serial.Write($packet, 0, $packet.Length)

                try {
                    $prediction = $serial.ReadByte()

                    if ($prediction -lt 0 -or $prediction -gt 9) {
                        throw "Invalid prediction byte: $prediction"
                    }

                    if ($prediction -eq $trueLabel) {
                        $correct++
                        $resultStatus = "PASS"
                    } else {
                        $wrong++
                        $resultStatus = "MISMATCH"
                    }

                    $message = ""
                }
                catch {
                    $errors++
                    $resultStatus = "UART_ERROR"
                    $message = $_.Exception.Message
                }
            }
            catch {
                $errors++
                $resultStatus = "IMAGE_ERROR"
                $message = $_.Exception.Message
            }

            $timer.Stop()
            $responses = $correct + $wrong
            $accuracy = if ($responses -gt 0) {
                [Math]::Round(100.0 * $correct / $responses, 2)
            } else { 0 }

            $row = [PSCustomObject]@{
                Timestamp        = (Get-Date).ToString("o")
                Attempt          = $tested
                ImageFile        = $file.Name
                TrueLabel        = $trueLabel
                PredictedLabel   = $prediction
                Status           = $resultStatus
                CorrectCount     = $correct
                WrongCount       = $wrong
                ErrorCount       = $errors
                Responses        = $responses
                AccuracyPercent  = $accuracy
                ElapsedSeconds   = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
                ErrorMessage     = $message
            }

            Save-LiveResult $row

            $color = switch ($resultStatus) {
                "PASS"        { "Green" }
                "MISMATCH"    { "Yellow" }
                default       { "Red" }
            }

            if ($null -ne $prediction) {
                Write-Host (
                    "[$tested] {0} | True={1} FPGA={2} | {3} | Accuracy={4}% ({5}/{6})" -f
                    $file.Name, $trueLabel, $prediction,
                    $resultStatus, $accuracy, $correct, $responses
                ) -ForegroundColor $color
            } else {
                Write-Host (
                    "[$tested] {0} | True={1} | {2} | {3}" -f
                    $file.Name, $trueLabel, $resultStatus, $message
                ) -ForegroundColor Red
            }

            $status.Text = $resultStatus
            $details.Text = "True: $trueLabel | FPGA: $prediction | $($file.Name)"
            $stats.Text = (
                "Images: {0} | Correct: {1} | Wrong: {2} | Errors: {3} | Accuracy: {4}%" -f
                $tested, $correct, $wrong, $errors, $accuracy
            )
            $form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()

            Start-Sleep -Milliseconds 500
        }
    }
}
finally {
    if ($serial) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }

    if ($picture.Image) {
        $picture.Image.Dispose()
        $picture.Image = $null
    }
    if ($bitmap) { $bitmap.Dispose() }
    if ($form) { $form.Dispose() }

    Show-LiveSummary
}
