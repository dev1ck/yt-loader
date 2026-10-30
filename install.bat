@echo off
chcp 65001 >nul

set "APP_NAME=YTLoader"
set "INSTALL_DIR=%LOCALAPPDATA%\%APP_NAME%"

echo =====================================
echo   %APP_NAME% 설치
echo =====================================

REM 설치 폴더 생성
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
)

echo [1] 파일 복사 중...
copy /Y "YTLoader.exe" "%INSTALL_DIR%" >nul
copy /Y "yt-dlp.exe"  "%INSTALL_DIR%" >nul
copy /Y "ffmpeg.exe"  "%INSTALL_DIR%" >nul

REM 아이콘 별도 배포했으면 같이 복사
if exist "YTLoader.ico" (
    copy /Y "YTLoader.ico" "%INSTALL_DIR%" >nul
)

if errorlevel 1 (
    echo 파일 복사 중 오류가 발생했습니다.
    pause
    exit /b 1
)

echo [2] 바탕화면 바로가기 생성 중...

set "VBS_FILE=%TEMP%\make_shortcut_%APP_NAME%.vbs"
set "TARGET=%INSTALL_DIR%\YTLoader.exe"
set "SHORTCUT=%USERPROFILE%\Desktop\YTLoader.lnk"
set "ICON=%INSTALL_DIR%\YTLoader.ico"

> "%VBS_FILE%" echo Set oWS = WScript.CreateObject("WScript.Shell")
>>"%VBS_FILE%" echo sLinkFile = "%SHORTCUT%"
>>"%VBS_FILE%" echo Set oLink = oWS.CreateShortcut(sLinkFile)
>>"%VBS_FILE%" echo oLink.TargetPath = "%TARGET%"
>>"%VBS_FILE%" echo oLink.WorkingDirectory = "%INSTALL_DIR%"
>>"%VBS_FILE%" echo oLink.WindowStyle = 1
>>"%VBS_FILE%" echo oLink.IconLocation = "%ICON%"
>>"%VBS_FILE%" echo oLink.Save

cscript //nologo "%VBS_FILE%" >nul
del "%VBS_FILE%" >nul 2>&1

echo [3] 설치 완료!
echo   설치 위치: %INSTALL_DIR%
echo   바탕화면에 바로가기가 생성되었습니다.

pause
