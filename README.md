# YTLoader

yt-dlp 기반 개인용 YouTube 다운로더 (Windows, WPF · Fluent 디자인)

Android판: [ytloader/android](https://github.com/ytloader/android)

- 링크를 넣으면 썸네일 · 제목 · 길이 · 해상도 · 음질 미리보기 (불러오는 중에도 다운로드 가능)
- 오디오(MP3 / M4A / OPUS / FLAC / WAV) 또는 영상(MP4 / MKV / WEBM) 다운로드
- 썸네일 · 메타데이터 삽입, 재생목록 전체 다운로드
- YouTube 로그인으로 비공개 · 연령 제한 · 멤버십 영상 다운로드
- 앱에서 yt-dlp 업데이트
- 시스템 다크 / 라이트 테마 자동 적용
- 앱 자동 업데이트 (GitHub Releases, [Velopack](https://velopack.io))

## 설치

[Releases](https://github.com/ytloader/windows/releases/latest)에서 `YTLoader-win-Setup.exe` 를 받아 실행합니다.

- `%LOCALAPPDATA%\YTLoader` 에 설치되고 바탕화면 · 시작 메뉴 바로가기가 생성됩니다. (관리자 권한 불필요)
- 앱을 시작할 때 새 버전을 확인하고, 동의하면 받아서 적용한 뒤 다시 시작합니다. (변경분만 받는 델타 업데이트)
- 제거: Windows 설정 → 앱 → 설치된 앱 → YTLoader
- 설치 없이 쓰려면 `YTLoader-win-Portable.zip` 을 받아 압축을 풉니다.

## 폴더 구조

```
├─ src/YTLoader/        앱 소스 (C# / .NET 10 WPF + WPF-UI)
├─ assets/
│  ├─ icon.png          아이콘 원본 (1254px)
│  └─ YTLoader.ico      앱 아이콘 (icon.png 에서 생성)
├─ .github/workflows/   릴리스 자동화 (태그 push → 빌드 → GitHub Release)
├─ bin/                 외부 실행 파일 (git 제외, fetch-deps.ps1 로 받음)
├─ dist/                빌드 결과 (git 제외)
├─ build.ps1            빌드 / 패키징
├─ fetch-deps.ps1       외부 실행 파일 다운로드
└─ dotnet-tools.json    빌드 도구 (vpk: Velopack CLI)
```

## 외부 실행 파일

| 파일 | 용도 | 배포처 |
|---|---|---|
| `yt-dlp.exe` | 다운로드 엔진 | [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp/releases) |
| `ffmpeg.exe` | 변환 · 병합 · 썸네일 삽입 | [yt-dlp/FFmpeg-Builds](https://github.com/yt-dlp/FFmpeg-Builds/releases) |
| `deno.exe` | YouTube 추출용 JS 런타임 | [denoland/deno](https://github.com/denoland/deno/releases) |

`fetch-deps.ps1` 이 최신 버전을 `bin\` 으로 받아 SHA-256 체크섬을 검증합니다.
이미 있는 파일은 건너뛰며, 모두 다시 받으려면 `-Force` 를 지정합니다.
`bin\*.exe` 는 빌드 시 `YTLoader.exe` 옆에 복사됩니다.

```
powershell -ExecutionPolicy Bypass -File fetch-deps.ps1 -Force
```

## 개발

[.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) 가 필요합니다.

```
dotnet run --project src\YTLoader        실행 (업데이트 확인은 설치된 앱에서만 동작)
.\build.ps1                              → dist\publish\  (실행 가능한 앱 폴더)
.\build.ps1 -Pack -Version 1.2.0         → + dist\releases\ (Setup.exe / 업데이트 패키지)
```

- `bin\` 에 외부 실행 파일이 없으면 `fetch-deps.ps1` 을 자동 실행합니다.
- .NET 런타임을 포함(self-contained)해서 빌드하므로 사용자 PC에 .NET이 없어도 됩니다.

## 릴리스

버전 태그를 push 하면 GitHub Actions가 빌드 · 패키징 후 GitHub Release를 만듭니다.

```
git tag v1.2.0
git push origin v1.2.0
```

- 이전 릴리스를 받아 델타 패키지를 함께 만듭니다.
- 빌드할 때마다 yt-dlp / ffmpeg / deno 최신 버전을 받아 포함합니다.
- 설치된 앱은 다음 실행 때 새 버전을 감지합니다.
