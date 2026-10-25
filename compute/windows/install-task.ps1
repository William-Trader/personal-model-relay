<#
  注册计划任务：开机 + 登录即启动隧道，隐藏窗口，失败自动重启。
  用法（管理员 PowerShell 或普通用户均可，按需）：
    powershell -ExecutionPolicy Bypass -File install-task.ps1 `
      -ServerHost relay.example.com -SshUser relay -LocalPort 8091
  卸载：
    schtasks /Delete /TN "ModelRelayTunnel" /F
#>
param(
  [Parameter(Mandatory = $true)][string]$ServerHost,
  [string]$SshUser = "relay",
  [string]$KeyPath = "$HOME\.ssh\relay_ed25519",
  [int]$RemotePort = 18092,
  [int]$LocalPort = 8091,
  [string]$TaskName = "ModelRelayTunnel"
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "relay-tunnel.ps1"
if (-not (Test-Path $script)) { throw "relay-tunnel.ps1 not found next to this script" }

$argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -ServerHost {1} -SshUser {2} -KeyPath "{3}" -RemotePort {4} -LocalPort {5}' -f `
  $script, $ServerHost, $SshUser, $KeyPath, $RemotePort, $LocalPort

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argLine
$triggers = @(
  (New-ScheduledTaskTrigger -AtStartup),
  (New-ScheduledTaskTrigger -AtLogOn)
)
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings `
  -Description "Personal model relay reverse SSH tunnel" -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed scheduled task '$TaskName' and started it."
Write-Host "Log: $HOME\relay-tunnel.log"
