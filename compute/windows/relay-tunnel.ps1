<#
  模型远程使用个人中转 · 反向隧道（Windows）
  作用：把本机 127.0.0.1:<LocalPort> 暴露到服务器的 127.0.0.1:<RemotePort>。
  特性：断线自动重连；显式绑定 loopback（公网不可见）；日志落盘。
  用法：
    powershell -ExecutionPolicy Bypass -File relay-tunnel.ps1 `
      -ServerHost relay.example.com -SshUser relay -LocalPort 8091
#>
param(
  [Parameter(Mandatory = $true)][string]$ServerHost,
  [string]$SshUser = "relay",
  [string]$KeyPath = "$HOME\.ssh\relay_ed25519",
  [int]$RemotePort = 18092,
  [int]$LocalPort = 8091,
  [int]$RetrySeconds = 5,
  [string]$LogPath = "$HOME\relay-tunnel.log"
)

$ErrorActionPreference = "Stop"

function Write-Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), $msg
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

if (-not (Test-Path $KeyPath)) {
  Write-Log "ERROR key not found: $KeyPath"
  throw "SSH key not found: $KeyPath"
}

Write-Log "supervisor start: $SshUser@$ServerHost  127.0.0.1:$RemotePort -> 127.0.0.1:$LocalPort"

while ($true) {
  Write-Log "connecting..."
  & ssh -N -T `
      -o BatchMode=yes `
      -o ExitOnForwardFailure=yes `
      -o ServerAliveInterval=30 `
      -o ServerAliveCountMax=3 `
      -o StrictHostKeyChecking=accept-new `
      -i $KeyPath `
      -R "127.0.0.1:${RemotePort}:127.0.0.1:${LocalPort}" `
      "${SshUser}@${ServerHost}" 2>&1 | ForEach-Object { Write-Log "ssh: $_" }

  Write-Log "disconnected (exit=$LASTEXITCODE), retry in ${RetrySeconds}s"
  Start-Sleep -Seconds $RetrySeconds
}
