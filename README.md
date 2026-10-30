# YTLoader

yt-dlp 기반 개인용 YouTube 다운로더 (Windows, PowerShell WinForms GUI)

- 오디오(MP3 / M4A / OPUS / FLAC / WAV) 또는 영상(MP4 / MKV / WEBM) 다운로드
- 썸네일 · 메타데이터 삽입, 재생목록 전체 다운로드
- YouTube 로그인으로 비공개 · 연령 제한 · 멤버십 영상 다운로드
- 앱에서 yt-dlp 업데이트

## 폴더 구조

```
├─ src/
│  ├─ YTLoader.ps1      앱 소스
│  └─ YTLoader.ico      아이콘
├─ installer/
│  ├─ install.bat       %LOCALAPPDATA%\YTLoader 에 설치 + 바탕화면 바로가기
│  └─ uninstall.bat     제거
├─ bin/                 외부 실행 파일 (git 제외, fetch-deps.ps1 로 받음)
├─ dist/                빌드 결과 (git 제외)
├─ build.bat            빌드 / 패키징
└─ fetch-deps.ps1       외부 실행 파일 다운로드
```

## 외부 실행 파일

| 파일 | 용도 | 배포처 |
|---|---|---|
| `yt-dlp.exe` | 다운로드 엔진 | [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp/releases) |
| `ffmpeg.exe` | 변환 · 병합 · 썸네일 삽입 | [yt-dlp/FFmpeg-Builds](https://github.com/yt-dlp/FFmpeg-Builds/releases) |
| `deno.exe` | YouTube 추출용 JS 런타임 | [denoland/deno](https://github.com/denoland/deno/releases) |

`fetch-deps.ps1` 이 최신 버전을 `bin\` 으로 받아 SHA-256 체크섬을 검증합니다.
이미 있는 파일은 건너뛰며, 모두 다시 받으려면 `-Force` 를 지정합니다.

```
powershell -ExecutionPolicy Bypass -File fetch-deps.ps1 -Force
```

## 빌드

```
build.bat            → dist\YTLoader\ (실행 가능한 앱 폴더)
build.bat package    → + dist\YTLoader_<버전>.zip (배포용)
```

- [ps2exe](https://github.com/MScholtes/PS2EXE) 모듈이 없으면 자동 설치합니다.
- `bin\` 에 외부 실행 파일이 없으면 `fetch-deps.ps1` 을 자동 실행합니다.

## 설치 / 업데이트

`dist\YTLoader\` (또는 배포 ZIP을 푼 폴더)에서 `install.bat` 을 실행합니다.
이미 설치된 경우 YTLoader를 종료한 뒤 다시 실행하면 덮어씁니다. (로그인 정보는 유지)
