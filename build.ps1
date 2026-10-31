# YTLoader 빌드 / 패키징
#   .\build.ps1                        → dist\publish\  (실행 가능한 앱 폴더)
#   .\build.ps1 -Pack -Version 1.2.0   → + dist\releases\ (Velopack 설치 파일 / 업데이트 패키지)
# 배포는 git 태그(v1.2.0)를 push 하면 GitHub Actions(.github\workflows\release.yml)가 수행합니다.
param(
    [string]$Version = '1.0.0',
    [switch]$Pack
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$publishDir = 'dist\publish'
$releasesDir = 'dist\releases'

# 외부 실행 파일(bin\) 확인, 없으면 공식 배포처에서 다운로드
Write-Output '[1] 외부 실행 파일 확인 중... (bin\yt-dlp.exe, ffmpeg.exe, deno.exe)'
if ('yt-dlp.exe', 'ffmpeg.exe', 'deno.exe' | Where-Object { -not (Test-Path "bin\$_") }) {
    & .\fetch-deps.ps1
}

# .NET 런타임 포함(self-contained) 빌드 → 사용자 PC에 .NET 설치 불필요
Write-Output "[2] 앱 빌드 중... (v$Version)"
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
dotnet publish src\YTLoader -c Release -r win-x64 --self-contained -o $publishDir -p:Version=$Version
if ($LASTEXITCODE) { throw '빌드 실패' }

if (-not $Pack) { return }

# Setup.exe(설치 파일) / 전체·델타 업데이트 패키지 생성
# $releasesDir 에 이전 버전 패키지가 있으면 델타 패키지도 만듦 (CI는 vpk download github 로 받아 둠)
Write-Output '[3] Velopack 패키지 생성 중...'
dotnet tool restore
dotnet vpk pack -u YTLoader --packTitle YTLoader --packAuthors dev1ck -v $Version -p $publishDir -e YTLoader.exe -i assets\YTLoader.ico -o $releasesDir
if ($LASTEXITCODE) { throw '패키지 생성 실패' }

Write-Output "완료: $releasesDir"
