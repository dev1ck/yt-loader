 @echo off
chcp 65001 >nul
setlocal

:: ====================================
:: 기본 정보
:: ====================================
set "APP_NAME=YTLoader"
set "APP_VERSION=1.0.0"
set "ZIP_NAME=%APP_NAME%_%APP_VERSION%.zip"

:: 옵션 처리: 첫 번째 인자가 package이면 ZIP 패키지까지 생성
set "DO_PACKAGE=0"
if /i "%~1"=="package" set "DO_PACKAGE=1"

echo =====================================
echo   YTLoader.ps1 → YTLoader.exe 패키징
echo =====================================

REM PowerShell ps2exe 모듈 설치 여부 확인
echo [1] ps2exe 모듈 확인 중...
powershell -NoProfile -Command ^
    "if (-not (Get-Module -ListAvailable -Name ps2exe)) {Install-Module ps2exe -Scope CurrentUser -Force} else {Write-Output 'ps2exe 모듈 이미 설치됨'}"

if %errorlevel% neq 0 (
    echo ps2exe 설치 실패. 관리자 권한으로 다시 실행하세요.
    pause
    exit /b
)

REM YTLoader.ps1 파일 확인
if not exist "YTLoader.ps1" (
    echo 오류: 현재 폴더에 YTLoader.ps1 파일이 없습니다.
    pause
    exit /b
)

echo [2] 패키징 실행 중...
powershell -NoProfile -Command ^
    "Invoke-ps2exe -InputFile 'YTLoader.ps1' -OutputFile 'YTLoader.exe' -NoConsole -IconFile 'YTLoader.ico' -Title '%APP_NAME%' -Product '%APP_NAME%' -Description 'Personal YouTube Downloader GUI' -Version '%APP_VERSION%'"

if %errorlevel% neq 0 (
    echo 패키징 실패!
    pause
    exit /b
)

echo =====================================
echo   패키징 완료!
echo   생성된 파일: YTLoader.exe
echo =====================================

:: ====================================
:: (옵션) ZIP 배포 패키지 생성
:: ====================================
if "%DO_PACKAGE%"=="1" goto :MAKE_ZIP_PACKAGE

echo.
echo (참고) ZIP 배포 패키지는 생성하지 않았습니다. ^(옵션 미사용^)
echo   → ZIP까지 만들려면: %~n0 package
goto :END_ZIP_PACKAGE


:MAKE_ZIP_PACKAGE
echo.
echo [3] 배포용 ZIP 패키지 생성 중...
echo   포함 파일: YTLoader.exe, YTLoader.ico, yt-dlp.exe, ffmpeg.exe, install.bat, uninstall.bat

powershell -NoProfile -Command ^
  "$zipName = '%ZIP_NAME%';" ^
  "$files = @('YTLoader.exe','YTLoader.ico','yt-dlp.exe','ffmpeg.exe','install.bat','uninstall.bat');" ^
  "$existing = $files | Where-Object { Test-Path $_ };" ^
  "if (-not $existing -or $existing.Count -eq 0) { Write-Error '압축할 대상 파일이 없습니다.'; exit 1 }" ^
  "if (Test-Path $zipName) { Remove-Item $zipName -Force }" ^
  "Compress-Archive -Path $existing -DestinationPath $zipName -Force"

if %errorlevel% neq 0 (
    echo ZIP 패키지 생성 실패!
    pause
    exit /b
)

echo =====================================
echo   ZIP 패키지 생성 완료!
echo   생성된 파일: %ZIP_NAME%
echo =====================================

:END_ZIP_PACKAGE

pause
endlocal