@echo off
chcp 65001 >nul
setlocal

set "APP_NAME=YTLoader"
set "INSTALL_DIR=%LOCALAPPDATA%\%APP_NAME%"
set "SHORTCUT=%USERPROFILE%\Desktop\YTLoader.lnk"

echo =====================================
echo   %APP_NAME% 제거 프로그램
echo =====================================
echo.

:: 실행 중인 YTLoader 종료
echo [1] 실행 중인 YTLoader.exe 종료 중...
taskkill /IM YTLoader.exe /F >nul 2>&1

:: 설치 폴더 확인
if not exist "%INSTALL_DIR%" (
    echo [오류] 설치된 %APP_NAME% 폴더를 찾을 수 없습니다.
    echo 확인된 경로: %INSTALL_DIR%
    pause
    exit /b
)

echo [2] 프로그램 파일 삭제 중...
rmdir /S /Q "%INSTALL_DIR%"

if exist "%INSTALL_DIR%" (
    echo [오류] 설치 폴더 삭제에 실패했습니다.
    echo 관리자 권한이 필요하거나 파일이 잠겨 있을 수 있습니다.
    pause
    exit /b
)

:: 바탕화면 바로가기 삭제
echo [3] 바탕화면 바로가기 삭제 중...
if exist "%SHORTCUT%" (
    del "%SHORTCUT%" >nul 2>&1
)

echo.
echo =====================================
echo   %APP_NAME% 완전 제거 완료!
echo =====================================

pause
exit /b
