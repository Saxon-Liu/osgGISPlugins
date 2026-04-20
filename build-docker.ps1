# Docker 镜像打包脚本
# 功能：打包 Docker 镜像，输出日志到 logs 目录，并打印打包时间

param(
    [string]$ImageTag = "osg-gis-plugins-mod:latest",
    [switch]$NoCache = $false,
    [string]$LogDir,
    [string]$Target,
    [switch]$BuildGui = $false
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 设置日志目录
if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $ScriptDir "logs"
}

# 创建日志目录（如果不存在）
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
    Write-Host "已创建日志目录：$LogDir" -ForegroundColor Green
}

# 生成日志文件名（包含时间戳）
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "docker_build_$Timestamp.log"

# 记录开始时间
$StartTime = Get-Date
$StartTimeStr = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")

function Write-LogLine {
    param(
        [string]$Message
    )

    Add-Content -Path $LogFile -Value $Message -Encoding UTF8
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Docker 镜像打包开始" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "开始时间：$StartTimeStr" -ForegroundColor Yellow
Write-Host "镜像标签：$ImageTag" -ForegroundColor Yellow
Write-Host "日志文件：$LogFile" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan

if (Test-Path $LogFile) {
    Remove-Item -Path $LogFile -Force
}

Write-LogLine "============================================"
Write-LogLine "Docker 镜像打包开始"
Write-LogLine "============================================"
Write-LogLine "开始时间：$StartTimeStr"
Write-LogLine "镜像标签：$ImageTag"
Write-LogLine "日志文件：$LogFile"

$env:DOCKER_BUILDKIT = "1"
$env:BUILDKIT_PROGRESS = "plain"

# 构建 Docker 命令
$BuildArgs = @("build", "--progress=plain", "-t", $ImageTag)
$BuildArgs += @("--build-arg", "BUILD_GUI=$(if ($BuildGui) { 'ON' } else { 'OFF' })")

if ($NoCache) {
    $BuildArgs += "--no-cache"
    Write-Host "模式：不使用缓存" -ForegroundColor Yellow
} else {
    Write-Host "模式：使用缓存" -ForegroundColor Yellow
}

if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $BuildArgs += @("--target", $Target)
    Write-Host "目标阶段：$Target" -ForegroundColor Yellow
}

Write-Host "GUI 构建：$(if ($BuildGui) { '启用' } else { '关闭' })" -ForegroundColor Yellow

$BuildArgs += @("-f", (Join-Path $ScriptDir "Dockerfile"), $ScriptDir)

Write-Host "============================================" -ForegroundColor Cyan
Write-LogLine "模式：$(if ($NoCache) { '不使用缓存' } else { '使用缓存' })"
Write-LogLine "GUI 构建：$(if ($BuildGui) { '启用' } else { '关闭' })"
if (-not [string]::IsNullOrWhiteSpace($Target)) { Write-LogLine "目标阶段：$Target" }
Write-LogLine "============================================"

# 执行 Docker 构建命令，同时输出到控制台和日志文件
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    # 实时输出并清理 PowerShell 对 stderr 的包装噪音
    & docker @BuildArgs 2>&1 | ForEach-Object {
        $text = $null
        $isErr = $false

        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $text = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = $_.ToString()
            }
        } else {
            $text = [string]$_
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            return
        }

        # 过滤 PowerShell 对原生命令 stderr 的类型噪音
        if ($text -eq "System.Management.Automation.RemoteException") {
            return
        }

        # BuildKit 进度常走 stderr，不能直接按 ErrorRecord 染红；仅命中错误关键字时染红
        if ($text -match '(?i)\berror\b|\bfailed\b|\bexception\b|\bpanic\b|\bdenied\b|\bunauthorized\b|\bforbidden\b|\bno such\b|\bcannot\b') {
            $isErr = $true
        }

        if ($isErr) {
            Write-Host $text -ForegroundColor Red
        } else {
            Write-Host $text
        }

        Write-LogLine $text
    }
    
    $Stopwatch.Stop()
    $EndTime = Get-Date
    $EndTimeStr = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $Duration = $Stopwatch.Elapsed
    
    # 计算耗时
    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f $Duration.Hours, $Duration.Minutes, $Duration.Seconds
    
    # 获取退出码
    $ExitCode = $LASTEXITCODE
    
    # 检查构建是否成功
    if ($ExitCode -eq 0) {
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "Docker 镜像打包成功!" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "结束时间：$EndTimeStr" -ForegroundColor Yellow
        Write-Host "总耗时：$DurationStr" -ForegroundColor Yellow
        Write-Host "日志已保存至：$LogFile" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Green

        Write-LogLine "============================================"
        Write-LogLine "Docker 镜像打包成功!"
        Write-LogLine "============================================"
        Write-LogLine "结束时间：$EndTimeStr"
        Write-LogLine "总耗时：$DurationStr"
        Write-LogLine "日志已保存至：$LogFile"
        Write-LogLine "============================================"
    } else {
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "Docker 镜像打包失败!" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "结束时间：$EndTimeStr" -ForegroundColor Yellow
        Write-Host "总耗时：$DurationStr" -ForegroundColor Yellow
        Write-Host "退出代码：$ExitCode" -ForegroundColor Red
        Write-Host "日志已保存至：$LogFile" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Red

        Write-LogLine "============================================"
        Write-LogLine "Docker 镜像打包失败!"
        Write-LogLine "============================================"
        Write-LogLine "结束时间：$EndTimeStr"
        Write-LogLine "总耗时：$DurationStr"
        Write-LogLine "退出代码：$ExitCode"
        Write-LogLine "日志已保存至：$LogFile"
        Write-LogLine "============================================"

        exit $ExitCode
    }
} catch {
    $Stopwatch.Stop()
    $EndTime = Get-Date
    $EndTimeStr = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $Duration = $Stopwatch.Elapsed
    $DurationStr = "{0:d2}:{1:d2}:{2:d2}" -f $Duration.Hours, $Duration.Minutes, $Duration.Seconds
    
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "Docker 镜像打包失败!" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "结束时间：$EndTimeStr" -ForegroundColor Yellow
    Write-Host "总耗时：$DurationStr" -ForegroundColor Yellow
    Write-Host "错误信息：$_" -ForegroundColor Red
    Write-Host "日志已保存至：$LogFile" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Red

    Write-LogLine "============================================"
    Write-LogLine "Docker 镜像打包失败!"
    Write-LogLine "============================================"
    Write-LogLine "结束时间：$EndTimeStr"
    Write-LogLine "总耗时：$DurationStr"
    Write-LogLine "错误信息：$_"
    Write-LogLine "日志已保存至：$LogFile"
    Write-LogLine "============================================"
    
    exit 1
}
