# 외부 실행 파일(yt-dlp / ffmpeg / deno)을 공식 배포처에서 bin\ 으로 내려받습니다.
# 각 파일은 배포처의 SHA-256 체크섬으로 검증합니다.
# 이미 있는 파일은 건너뛰며, 다시 받으려면 -Force 를 지정합니다.
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Windows PowerShell 5.1에서 진행률 표시가 다운로드를 크게 느리게 함
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$binDir = Join-Path $PSScriptRoot 'bin'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) 'YTLoader-deps'

# Name: bin\ 에 둘 파일 / Url: 받을 파일 (zip이면 압축 해제 후 Name을 찾음)
# SumsUrl: 체크섬 파일 / SumsKey: 체크섬 파일에서 찾을 파일명 (없으면 첫 해시)
$deps = @(
    @{
        Name    = 'yt-dlp.exe'
        Url     = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        SumsUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS'
        SumsKey = 'yt-dlp.exe'
    },
    @{
        Name    = 'ffmpeg.exe'
        Url     = 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
        SumsUrl = 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/checksums.sha256'
        SumsKey = 'ffmpeg-master-latest-win64-gpl.zip'
    },
    @{
        Name    = 'deno.exe'
        Url     = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
        SumsUrl = 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip.sha256sum'
        SumsKey = $null
    }
)

function Get-ExpectedHash($sumsUrl, $key) {
    $text = (New-Object System.Net.WebClient).DownloadString($sumsUrl)
    foreach ($line in $text -split "`n") {
        if ($key) {
            if ($line -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($key))\s*$") { return $Matches[1] }
        } elseif ($line -match '\b([0-9a-fA-F]{64})\b') {
            return $Matches[1]
        }
    }
    throw "체크섬을 찾을 수 없습니다: $sumsUrl"
}

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

foreach ($dep in $deps) {
    $target = Join-Path $binDir $dep.Name
    if ((Test-Path $target) -and -not $Force) {
        Write-Output "[건너뜀] $($dep.Name) (이미 있음)"
        continue
    }

    Write-Output "[다운로드] $($dep.Name) <- $($dep.Url)"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $download = Join-Path $tempDir ([IO.Path]::GetFileName($dep.Url))
        Invoke-WebRequest -Uri $dep.Url -OutFile $download -UseBasicParsing

        $expected = Get-ExpectedHash $dep.SumsUrl $dep.SumsKey
        $actual = (Get-FileHash $download -Algorithm SHA256).Hash
        if ($actual -ne $expected.ToUpper()) {
            throw "체크섬 불일치: $($dep.Name) (예상 $expected / 실제 $actual)"
        }

        if ($download -like '*.zip') {
            $extractDir = Join-Path $tempDir 'x'
            Expand-Archive -Path $download -DestinationPath $extractDir -Force
            $found = Get-ChildItem $extractDir -Recurse -Filter $dep.Name | Select-Object -First 1
            if (-not $found) { throw "압축 파일 안에 $($dep.Name)이 없습니다." }
            $download = $found.FullName
        }

        Copy-Item $download $target -Force
        Write-Output "[완료] $target"
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
