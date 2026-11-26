# Save this file in your repo as: deploy/deploy.ps1
# It runs ON the Windows VM (the GitHub workflow copies it there and runs it over SSH).
#
# What it does:
#   1. Stops the running app
#   2. Backs up the old JAR and swaps in the new one
#   3. Starts the app through Windows Task Scheduler, so it keeps running after
#      the SSH session ends and also starts automatically when the VM reboots

param(
    [string]$AppDir   = "C:\app",
    [string]$JarName  = "app.jar",
    [string]$TaskName = "MyJavaApp"
)

$ErrorActionPreference = "Stop"
Set-Location $AppDir

$jarPath = Join-Path $AppDir $JarName
$newJar  = "$jarPath.new"
$logPath = Join-Path $AppDir "app.log"

if (-not (Test-Path $newJar)) { throw "New JAR not found: $newJar" }

# ---- 1. Stop the old app ----
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Stopping scheduled task $TaskName"
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
# make sure no java process is still holding the JAR
Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
    Where-Object { $_.CommandLine -like "*$JarName*" } |
    ForEach-Object {
        Write-Host "Killing leftover java process $($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force
    }
Start-Sleep -Seconds 3

# ---- 2. Swap JARs, keeping a backup ----
if (Test-Path $jarPath) { Move-Item $jarPath "$jarPath.bak" -Force }
Move-Item $newJar $jarPath -Force
Write-Host "New JAR in place: $jarPath"

# ---- 3. Register the task once, then start it ----
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    $java = (Get-Command java.exe).Source
    Write-Host "Registering scheduled task $TaskName using $java"

    $action   = New-ScheduledTaskAction -Execute "cmd.exe" `
                  -Argument "/c `"`"$java`" -jar `"$jarPath`" > `"$logPath`" 2>&1`"" `
                  -WorkingDirectory $AppDir
    $trigger  = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
                  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal | Out-Null
}

Start-ScheduledTask -TaskName $TaskName
Write-Host "Started $TaskName, waiting for it to come up..."
Start-Sleep -Seconds 10

$running = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
           Where-Object { $_.CommandLine -like "*$JarName*" }
if ($running) {
    Write-Host "App is running (PID $($running.ProcessId))"
} else {
    Write-Host "App failed to start. Last log lines:"
    if (Test-Path $logPath) { Get-Content $logPath -Tail 50 }
    exit 1
}
