 @echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

:: ====================================
:: 기본 정보
:: ====================================
set "APP_NAME=YTLoader"
set "APP_VERSION=1.0.0"
set "DIST_DIR=dist\%APP_NAME%"
set "ZIP_NAME=dist\%APP_NAME%_%APP_VERSION%.zip"

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

REM 외부 실행 파일(bin\) 확인, 없으면 공식 배포처에서 다운로드
echo [2] 외부 실행 파일 확인 중... (bin\yt-dlp.exe, ffmpeg.exe, deno.exe)
set "NEED_FETCH=0"
for %%F in (yt-dlp.exe ffmpeg.exe deno.exe) do if not exist "bin\%%F" set "NEED_FETCH=1"
if "%NEED_FETCH%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "fetch-deps.ps1"
    if errorlevel 1 (
        echo 외부 실행 파일 다운로드 실패!
        pause
        exit /b
    )
)

REM YTLoader.ps1 파일 확인
if not exist "src\YTLoader.ps1" (
    echo 오류: src\YTLoader.ps1 파일이 없습니다.
    pause
    exit /b
)

echo [3] 패키징 실행 중...
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
powershell -NoProfile -Command ^
    "Invoke-ps2exe -InputFile 'src\YTLoader.ps1' -OutputFile '%DIST_DIR%\YTLoader.exe' -NoConsole -IconFile 'src\YTLoader.ico' -Title '%APP_NAME%' -Product '%APP_NAME%' -Description 'Personal YouTube Downloader GUI' -Version '%APP_VERSION%'"

if %errorlevel% neq 0 (
    echo 패키징 실패!
    pause
    exit /b
)

REM 실행 / 설치에 필요한 파일을 앱 폴더에 모음
echo [4] 앱 폴더 구성 중... (%DIST_DIR%)
copy /Y "bin\yt-dlp.exe" "%DIST_DIR%" >nul
copy /Y "bin\ffmpeg.exe" "%DIST_DIR%" >nul
copy /Y "bin\deno.exe"   "%DIST_DIR%" >nul
copy /Y "src\YTLoader.ico" "%DIST_DIR%" >nul
copy /Y "installer\install.bat"   "%DIST_DIR%" >nul
copy /Y "installer\uninstall.bat" "%DIST_DIR%" >nul

if errorlevel 1 (
    echo 앱 폴더 구성 실패!
    pause
    exit /b
)

echo =====================================
echo   패키징 완료!
echo   앱 폴더: %DIST_DIR%  (install.bat으로 설치)
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
echo [5] 배포용 ZIP 패키지 생성 중...
echo   포함 파일: %DIST_DIR% 폴더 전체

powershell -NoProfile -Command ^
  "$zipName = '%ZIP_NAME%';" ^
  "if (Test-Path $zipName) { Remove-Item $zipName -Force }" ^
  "Compress-Archive -Path '%DIST_DIR%\*' -DestinationPath $zipName -Force"

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