Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# 스크립트 위치 기준 (yt-dlp.exe 탐색용)
$scriptDir = Split-Path -Parent ([Environment]::GetCommandLineArgs()[0])

# yt-dlp 경로 (같은 폴더에 있으면 우선 사용)
$ytDlpPath = Join-Path $scriptDir "yt-dlp.exe"
if (-not (Test-Path $ytDlpPath)) {
    # PATH에 있는 yt-dlp 탐색
    $cmd = Get-Command yt-dlp -ErrorAction SilentlyContinue
    if ($cmd) {
        $ytDlpPath = $cmd.Source
    }
}

if (-not (Test-Path $ytDlpPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "yt-dlp.exe를 찾을 수 없습니다.`nYTLoader.exe와 같은 폴더에 두거나 PATH에 추가해 주세요.",
        "오류"
    )
    return
}

# ffmpeg 경로 (같은 폴더에 있으면 yt-dlp에 직접 지정, 없으면 PATH 사용)
$ffmpegPath = Join-Path $scriptDir "ffmpeg.exe"
if (-not (Test-Path $ffmpegPath)) {
    $ffmpegPath = $null
}

# 로그인 데이터 (쿠키 파일 / 로그인 전용 브라우저 프로필)
$dataDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'YTLoader'
$cookieFile = Join-Path $dataDir 'cookies.txt'
$loginProfileDir = Join-Path $dataDir 'login-profile'
$loginUrl = 'https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Dko%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F'

# ---------------------------------
# 포맷 / 품질 목록 (값, 표시 이름)
# ---------------------------------
$audioFormats = @(
    @('mp3',      'MP3 (범용)'),
    @('m4a',      'M4A (AAC)'),
    @('opus',     'OPUS (고효율)'),
    @('flac',     'FLAC (무손실)'),
    @('wav',      'WAV (무손실)'),
    @('original', '원본 (변환 없음)')
)
$audioQualities = @(
    @('0',    '최고 (VBR)'),
    @('320K', '320 kbps'),
    @('256K', '256 kbps'),
    @('192K', '192 kbps'),
    @('128K', '128 kbps')
)
$videoFormats = @(
    @('mp4',      'MP4 (호환성 높음)'),
    @('mkv',      'MKV'),
    @('webm',     'WEBM'),
    @('original', '원본 (변환 없음)')
)
$videoResolutions = @(
    @('',     '최고 화질'),
    @('2160', '2160p (4K)'),
    @('1440', '1440p'),
    @('1080', '1080p'),
    @('720',  '720p'),
    @('480',  '480p'),
    @('360',  '360p')
)

# 썸네일 삽입을 지원하는 출력 포맷 (yt-dlp 기준)
$thumbnailFormats = @('mp3', 'm4a', 'opus', 'flac', 'mp4', 'mkv')
# 비트레이트 지정이 의미 있는 오디오 포맷 (손실 압축)
$lossyAudioFormats = @('mp3', 'm4a', 'opus')

# ---------------------------------
# 기본 다운로드 폴더 (사용자 Downloads)
# ---------------------------------
$userProfile = [Environment]::GetFolderPath('UserProfile')
$outputDir = Join-Path $userProfile 'Downloads'

# 실행 중인 yt-dlp 프로세스 / 취소 여부
$script:proc = $null
$script:cancelled = $false
$script:loginCancelled = $false

# ---------------------------------
# 폼 기본 설정
# ---------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "YTLoader"
$form.Size = New-Object System.Drawing.Size(530, 465)  # 크기
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.FormBorderStyle = "FixedDialog"

$toolTip = New-Object System.Windows.Forms.ToolTip

# ---------------------------------
# URL 입력
# ---------------------------------
$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text = "YouTube URL"
$lblUrl.Location = New-Object System.Drawing.Point(10, 15)
$lblUrl.AutoSize = $true
$form.Controls.Add($lblUrl)

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(10, 35)
$txtUrl.Size = New-Object System.Drawing.Size(495, 20)
$form.Controls.Add($txtUrl)

# ---------------------------------
# 모드 선택 (오디오 / 영상+오디오)
# ---------------------------------
$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = "모드 선택"
$grpMode.Location = New-Object System.Drawing.Point(10, 65)
$grpMode.Size = New-Object System.Drawing.Size(150, 80)
$form.Controls.Add($grpMode)

$rbAudio = New-Object System.Windows.Forms.RadioButton
$rbAudio.Text = "오디오만"
$rbAudio.Location = New-Object System.Drawing.Point(10, 22)
$rbAudio.AutoSize = $true
$rbAudio.Checked = $true
$grpMode.Controls.Add($rbAudio)

$rbVideo = New-Object System.Windows.Forms.RadioButton
$rbVideo.Text = "영상+오디오"
$rbVideo.Location = New-Object System.Drawing.Point(10, 47)
$rbVideo.AutoSize = $true
$grpMode.Controls.Add($rbVideo)

# ---------------------------------
# 포맷 / 품질 선택
# ---------------------------------
$grpFormat = New-Object System.Windows.Forms.GroupBox
$grpFormat.Text = "포맷 / 품질"
$grpFormat.Location = New-Object System.Drawing.Point(170, 65)
$grpFormat.Size = New-Object System.Drawing.Size(335, 80)
$form.Controls.Add($grpFormat)

$lblFormat = New-Object System.Windows.Forms.Label
$lblFormat.Text = "포맷"
$lblFormat.Location = New-Object System.Drawing.Point(10, 23)
$lblFormat.AutoSize = $true
$grpFormat.Controls.Add($lblFormat)

$cboFormat = New-Object System.Windows.Forms.ComboBox
$cboFormat.DropDownStyle = "DropDownList"
$cboFormat.Location = New-Object System.Drawing.Point(80, 20)
$cboFormat.Size = New-Object System.Drawing.Size(240, 20)
$grpFormat.Controls.Add($cboFormat)

$lblQuality = New-Object System.Windows.Forms.Label
$lblQuality.Text = "음질"
$lblQuality.Location = New-Object System.Drawing.Point(10, 51)
$lblQuality.AutoSize = $true
$grpFormat.Controls.Add($lblQuality)

$cboQuality = New-Object System.Windows.Forms.ComboBox
$cboQuality.DropDownStyle = "DropDownList"
$cboQuality.Location = New-Object System.Drawing.Point(80, 48)
$cboQuality.Size = New-Object System.Drawing.Size(240, 20)
$grpFormat.Controls.Add($cboQuality)

# ---------------------------------
# 추가 옵션
# ---------------------------------
$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Text = "옵션"
$grpOptions.Location = New-Object System.Drawing.Point(10, 150)
$grpOptions.Size = New-Object System.Drawing.Size(495, 50)
$form.Controls.Add($grpOptions)

$chkThumbnail = New-Object System.Windows.Forms.CheckBox
$chkThumbnail.Text = "썸네일 삽입"
$chkThumbnail.Location = New-Object System.Drawing.Point(10, 20)
$chkThumbnail.AutoSize = $true
$chkThumbnail.Checked = $true
$grpOptions.Controls.Add($chkThumbnail)
$toolTip.SetToolTip($chkThumbnail, "MP3 / M4A / OPUS / FLAC / MP4 / MKV에서만 지원됩니다.")

$chkMetadata = New-Object System.Windows.Forms.CheckBox
$chkMetadata.Text = "메타데이터 삽입"
$chkMetadata.Location = New-Object System.Drawing.Point(140, 20)
$chkMetadata.AutoSize = $true
$chkMetadata.Checked = $true
$grpOptions.Controls.Add($chkMetadata)
$toolTip.SetToolTip($chkMetadata, "제목, 업로더, 날짜 등을 파일 태그에 기록합니다.")

$chkPlaylist = New-Object System.Windows.Forms.CheckBox
$chkPlaylist.Text = "재생목록 전체"
$chkPlaylist.Location = New-Object System.Drawing.Point(290, 20)
$chkPlaylist.AutoSize = $true
$grpOptions.Controls.Add($chkPlaylist)
$toolTip.SetToolTip($chkPlaylist, "URL에 재생목록이 포함된 경우 전체를 '재생목록 이름' 하위 폴더에 받습니다.`n해제 시 해당 영상 하나만 받습니다.")

# ---------------------------------
# 모드 / 포맷에 따라 목록 및 옵션 갱신
# ---------------------------------
function Set-ComboItems($combo, $items) {
    $combo.Items.Clear()
    foreach ($item in $items) {
        [void]$combo.Items.Add($item[1])
    }
    $combo.SelectedIndex = 0
}

function Get-SelectedFormat {
    if ($rbAudio.Checked) { return $audioFormats[$cboFormat.SelectedIndex][0] }
    return $videoFormats[$cboFormat.SelectedIndex][0]
}

function Update-OptionState {
    if ($cboFormat.SelectedIndex -lt 0) { return }
    $fmt = Get-SelectedFormat

    if ($rbAudio.Checked) {
        # 무손실 / 원본은 비트레이트 지정 불가
        $cboQuality.Enabled = $lossyAudioFormats -contains $fmt
    } else {
        $cboQuality.Enabled = $true
    }

    $chkThumbnail.Enabled = $thumbnailFormats -contains $fmt
}

function Update-ModeState {
    if ($rbAudio.Checked) {
        $lblQuality.Text = "음질"
        Set-ComboItems $cboFormat $audioFormats
        Set-ComboItems $cboQuality $audioQualities
    } else {
        $lblQuality.Text = "해상도"
        Set-ComboItems $cboFormat $videoFormats
        Set-ComboItems $cboQuality $videoResolutions
    }
    Update-OptionState
}

$rbAudio.Add_CheckedChanged({ if ($rbAudio.Checked) { Update-ModeState } })
$rbVideo.Add_CheckedChanged({ if ($rbVideo.Checked) { Update-ModeState } })
$cboFormat.Add_SelectedIndexChanged({ Update-OptionState })

Update-ModeState

# ---------------------------------
# 로그인 (비공개 / 연령 제한 / 멤버십 영상용 쿠키)
# ---------------------------------
$grpLogin = New-Object System.Windows.Forms.GroupBox
$grpLogin.Text = "YouTube 로그인 (비공개 · 연령 제한 · 멤버십 영상)"
$grpLogin.Location = New-Object System.Drawing.Point(10, 205)
$grpLogin.Size = New-Object System.Drawing.Size(495, 50)
$form.Controls.Add($grpLogin)

$lblLoginStatus = New-Object System.Windows.Forms.Label
$lblLoginStatus.Location = New-Object System.Drawing.Point(10, 22)
$lblLoginStatus.Size = New-Object System.Drawing.Size(200, 20)
$lblLoginStatus.AutoEllipsis = $true
$grpLogin.Controls.Add($lblLoginStatus)

$chkUseCookies = New-Object System.Windows.Forms.CheckBox
$chkUseCookies.Text = "로그인 쿠키 사용"
$chkUseCookies.Location = New-Object System.Drawing.Point(215, 20)
$chkUseCookies.AutoSize = $true
$chkUseCookies.Checked = $true
$grpLogin.Controls.Add($chkUseCookies)
$toolTip.SetToolTip($chkUseCookies, "다운로드 시 로그인 쿠키를 함께 전달합니다.`n공개 영상만 받을 때는 해제해도 됩니다. (계정 보호를 위해 보조 계정 사용 권장)")

$btnLogin = New-Object System.Windows.Forms.Button
$btnLogin.Text = "로그인"
$btnLogin.Location = New-Object System.Drawing.Point(335, 16)
$btnLogin.Size = New-Object System.Drawing.Size(75, 25)
$grpLogin.Controls.Add($btnLogin)
$toolTip.SetToolTip($btnLogin, "로그인 전용 브라우저 창을 열어 YouTube에 로그인합니다.`n로그인이 확인되면 쿠키를 저장하고 창을 자동으로 닫습니다.")

$btnLogout = New-Object System.Windows.Forms.Button
$btnLogout.Text = "로그아웃"
$btnLogout.Location = New-Object System.Drawing.Point(415, 16)
$btnLogout.Size = New-Object System.Drawing.Size(70, 25)
$grpLogin.Controls.Add($btnLogout)

# 쿠키 파일 유무로 로그인 상태 표시
function Update-LoginState {
    if (Test-Path $cookieFile) {
        $savedAt = (Get-Item $cookieFile).LastWriteTime.ToString('yyyy-MM-dd')
        $lblLoginStatus.Text = "● 로그인됨 ($savedAt)"
        $lblLoginStatus.ForeColor = [System.Drawing.Color]::Green
        $chkUseCookies.Enabled = $true
        $btnLogout.Enabled = $true
    } else {
        $lblLoginStatus.Text = "○ 로그인 안 됨"
        $lblLoginStatus.ForeColor = [System.Drawing.SystemColors]::GrayText
        $chkUseCookies.Enabled = $false
        $btnLogout.Enabled = $false
    }
}

Update-LoginState

# ---------------------------------
# 다운로드 폴더 선택
# ---------------------------------
$lblOutputDir = New-Object System.Windows.Forms.Label
$lblOutputDir.Text = "저장 폴더"
$lblOutputDir.Location = New-Object System.Drawing.Point(10, 265)
$lblOutputDir.AutoSize = $true
$form.Controls.Add($lblOutputDir)

$txtOutputDir = New-Object System.Windows.Forms.TextBox
$txtOutputDir.Location = New-Object System.Drawing.Point(10, 285)
$txtOutputDir.Size = New-Object System.Drawing.Size(305, 20)
$txtOutputDir.Text = $outputDir
$form.Controls.Add($txtOutputDir)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "폴더 선택"
$btnBrowse.Location = New-Object System.Drawing.Point(320, 283)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 25)
$form.Controls.Add($btnBrowse)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "폴더 열기"
$btnOpenFolder.Location = New-Object System.Drawing.Point(415, 283)
$btnOpenFolder.Size = New-Object System.Drawing.Size(90, 25)
$form.Controls.Add($btnOpenFolder)

# 폴더 선택 버튼 이벤트
$btnBrowse.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if (Test-Path $txtOutputDir.Text) {
        $folderDialog.SelectedPath = $txtOutputDir.Text
    } else {
        $folderDialog.SelectedPath = $outputDir
    }

    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:outputDir = $folderDialog.SelectedPath
        $txtOutputDir.Text = $global:outputDir
    }
})

# 폴더 열기 버튼 이벤트
$btnOpenFolder.Add_Click({
    $currentDir = $txtOutputDir.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($currentDir)) {
        [System.Windows.Forms.MessageBox]::Show("저장 폴더가 설정되어 있지 않습니다.","알림")
        return
    }

    if (-not (Test-Path $currentDir)) {
        [System.Windows.Forms.MessageBox]::Show("해당 폴더가 존재하지 않습니다.`n먼저 다운로드를 진행하거나 폴더를 생성해 주세요.","알림")
        return
    }

    Start-Process explorer.exe $currentDir
})

# ---------------------------------
# 진행률 / 상태 표시
# ---------------------------------
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 325)
$progressBar.Size = New-Object System.Drawing.Size(495, 18)
$progressBar.Minimum = 0
$progressBar.Maximum = 1000
$form.Controls.Add($progressBar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(10, 350)
$lblStatus.Size = New-Object System.Drawing.Size(495, 20)
$lblStatus.AutoEllipsis = $true
$form.Controls.Add($lblStatus)

# ---------------------------------
# 다운로드 / 취소 버튼
# ---------------------------------
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "yt-dlp 업데이트"
$btnUpdate.Location = New-Object System.Drawing.Point(10, 380)
$btnUpdate.Size = New-Object System.Drawing.Size(110, 25)
$form.Controls.Add($btnUpdate)
$toolTip.SetToolTip($btnUpdate, "YouTube 변경으로 다운로드가 실패할 때 yt-dlp를 최신 버전으로 업데이트합니다.")

$lblVersion = New-Object System.Windows.Forms.Label
$lblVersion.Location = New-Object System.Drawing.Point(125, 385)
$lblVersion.AutoSize = $true
$lblVersion.ForeColor = [System.Drawing.SystemColors]::GrayText
$form.Controls.Add($lblVersion)

# yt-dlp.exe 파일 버전 정보로 현재 버전 표시 (프로세스 실행 없이)
function Update-VersionLabel {
    $ver = (Get-Item $ytDlpPath).VersionInfo.FileVersion
    if (-not $ver) { $ver = "알 수 없음" }
    $lblVersion.Text = "v$ver"
}

Update-VersionLabel

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "취소"
$btnCancel.Location = New-Object System.Drawing.Point(300, 380)
$btnCancel.Size = New-Object System.Drawing.Size(100, 25)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "다운로드"
$btnDownload.Location = New-Object System.Drawing.Point(405, 380)
$btnDownload.Size = New-Object System.Drawing.Size(100, 25)
$form.Controls.Add($btnDownload)
$form.AcceptButton = $btnDownload

# 작업(다운로드 / 업데이트 / 로그인) 중 입력 잠금
function Set-Busy($busy) {
    foreach ($c in @($btnDownload, $btnUpdate, $grpMode, $grpFormat, $grpOptions, $grpLogin)) {
        $c.Enabled = -not $busy
    }
}

# yt-dlp와 하위 ffmpeg 프로세스까지 종료
function Stop-Download {
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:cancelled = $true
        & taskkill.exe /T /F /PID $script:proc.Id | Out-Null
    }
}

$btnCancel.Add_Click({ Stop-Download })
$form.Add_FormClosing({
    Stop-Download
    $script:loginCancelled = $true
})

# ---------------------------------
# yt-dlp 인자 구성
# ---------------------------------
function Build-YtDlpArgs($url, $dir) {
    $fmt = Get-SelectedFormat
    $ytArgs = New-Object System.Collections.Generic.List[string]

    if ($ffmpegPath) {
        $ytArgs.AddRange([string[]]@("--ffmpeg-location", $ffmpegPath))
    }

    if ($rbAudio.Checked) {
        $ytArgs.AddRange([string[]]@("-f", "bestaudio/best"))
        if ($fmt -ne 'original') {
            # yt-dlp -x --audio-format <fmt> [--audio-quality <q>]
            $ytArgs.AddRange([string[]]@("-x", "--audio-format", $fmt))
            if ($lossyAudioFormats -contains $fmt) {
                $ytArgs.AddRange([string[]]@("--audio-quality", $audioQualities[$cboQuality.SelectedIndex][0]))
            }
        }
    } else {
        # 해상도 상한 + (선택 시) 컨테이너에 맞는 스트림 우선
        $height = $videoResolutions[$cboQuality.SelectedIndex][0]
        $sort = @()
        if ($height) { $sort += "res:$height" }
        if ($fmt -eq 'mp4')  { $sort += "ext:mp4:m4a" }
        if ($fmt -eq 'webm') { $sort += "ext:webm:webm" }

        $ytArgs.AddRange([string[]]@("-f", "bv*+ba/b"))
        if ($sort.Count -gt 0) {
            $ytArgs.AddRange([string[]]@("-S", ($sort -join ',')))
        }
        if ($fmt -ne 'original') {
            $ytArgs.AddRange([string[]]@("--merge-output-format", $fmt, "--remux-video", $fmt))
        }
    }

    if ($chkThumbnail.Enabled -and $chkThumbnail.Checked) { $ytArgs.Add("--embed-thumbnail") }
    if ($chkMetadata.Checked) { $ytArgs.Add("--embed-metadata") }
    if ($chkUseCookies.Enabled -and $chkUseCookies.Checked) {
        $ytArgs.AddRange([string[]]@("--cookies", $cookieFile))
    }

    if ($chkPlaylist.Checked) {
        $ytArgs.Add("--yes-playlist")
        $outputTemplate = Join-Path $dir "%(playlist_title|Playlist)s\%(playlist_index|0)03d - %(title)s.%(ext)s"
    } else {
        $ytArgs.Add("--no-playlist")
        $outputTemplate = Join-Path $dir "%(title)s.%(ext)s"
    }

    $ytArgs.AddRange([string[]]@("--newline", "--progress", "-o", $outputTemplate, $url))
    return ,$ytArgs
}

# Windows 명령줄 규칙에 맞게 인자 인용
function Join-CommandLine($list) {
    $quoted = foreach ($a in $list) {
        '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }
    return $quoted -join ' '
}

# yt-dlp 출력 한 줄 → 진행률 / 상태 반영
function Update-ProgressFromLine($line) {
    if ($line -match '^\[download\]\s+([\d\.]+)%(.*)$') {
        $pct = [double]$Matches[1]
        $progressBar.Value = [Math]::Min(1000, [int]($pct * 10))
        $lblStatus.Text = "다운로드 중... $($Matches[1])%$($Matches[2] -replace '\s+', ' ')"
    } elseif ($line -match '^\[download\] Downloading item (\d+) of (\d+)') {
        $lblStatus.Text = "재생목록 $($Matches[1]) / $($Matches[2]) 항목 처리 중..."
    } elseif ($line -match '^\[(ExtractAudio|Merger|VideoRemuxer|VideoConvertor|EmbedThumbnail|Metadata|FixupM4a|FixupM3u8)\]') {
        $progressBar.Value = 1000
        $lblStatus.Text = "변환 / 후처리 중... [$($Matches[1])]"
    }
}

# yt-dlp 실행: 출력(stdout / stderr)을 한 줄씩 $onLine에 전달, 종료 코드 반환
function Invoke-YtDlp($argList, [scriptblock]$onLine) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ytDlpPath
    $psi.Arguments = Join-CommandLine $argList
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"

    $script:proc = [System.Diagnostics.Process]::Start($psi)

    # 출력을 비동기로 읽으면서 UI 응답 유지
    $outTask = $script:proc.StandardOutput.ReadLineAsync()
    $errTask = $script:proc.StandardError.ReadLineAsync()
    while ($outTask -or $errTask) {
        $handled = $false

        if ($outTask -and $outTask.IsCompleted) {
            $line = $outTask.Result
            if ($null -eq $line) {
                $outTask = $null
            } else {
                $null = & $onLine $line
                $outTask = $script:proc.StandardOutput.ReadLineAsync()
            }
            $handled = $true
        }

        if ($errTask -and $errTask.IsCompleted) {
            $line = $errTask.Result
            if ($null -eq $line) {
                $errTask = $null
            } else {
                $null = & $onLine $line
                $errTask = $script:proc.StandardError.ReadLineAsync()
            }
            $handled = $true
        }

        [System.Windows.Forms.Application]::DoEvents()
        if (-not $handled) { Start-Sleep -Milliseconds 30 }
    }
    $script:proc.WaitForExit()
    return $script:proc.ExitCode
}

# ---------------------------------
# 다운로드 클릭 이벤트
# ---------------------------------
$btnDownload.Add_Click({
    $url = $txtUrl.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($url)) {
        [System.Windows.Forms.MessageBox]::Show("URL을 입력해 주세요.","알림")
        return
    }

    # 현재 텍스트박스 값을 기준으로 출력 폴더 갱신
    $currentOutputDir = $txtOutputDir.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($currentOutputDir)) {
        [System.Windows.Forms.MessageBox]::Show("저장 폴더를 입력해 주세요.","알림")
        return
    }

    # 폴더 없으면 생성 시도
    if (-not (Test-Path $currentOutputDir)) {
        try {
            New-Item -ItemType Directory -Path $currentOutputDir -Force | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "저장 폴더를 생성할 수 없습니다.`n$($_.Exception.Message)",
                "오류"
            )
            return
        }
    }

    # 컨트롤의 Enabled 값을 참조하므로 입력 잠금(Set-Busy) 전에 인자 구성
    $ytArgs = Build-YtDlpArgs $url $currentOutputDir

    Set-Busy $true
    $btnCancel.Enabled = $true
    $progressBar.Value = 0
    $lblStatus.Text = "다운로드 준비 중..."
    $script:cancelled = $false
    $script:lastError = ""

    try {
        $exitCode = Invoke-YtDlp $ytArgs {
            param($line)
            Update-ProgressFromLine $line
            if ($line -match '^ERROR:') { $script:lastError = $line }
        }

        if ($script:cancelled) {
            $lblStatus.Text = "다운로드가 취소되었습니다."
        } elseif ($exitCode -eq 0) {
            $progressBar.Value = 1000
            $lblStatus.Text = "다운로드 완료 (출력 폴더: $currentOutputDir)"
            [System.Windows.Forms.MessageBox]::Show("다운로드가 완료되었습니다.","완료")
        } else {
            $lblStatus.Text = "다운로드 중 오류 발생 (ExitCode: $exitCode)"
            [System.Windows.Forms.MessageBox]::Show(
                "다운로드 중 오류가 발생했습니다.`nExitCode: $exitCode`n`n$($script:lastError)`n`n" +
                "※ 'yt-dlp 업데이트' 후 다시 시도해 보세요.`n   비공개 · 연령 제한 영상이라면 먼저 로그인이 필요합니다.",
                "오류"
            )
        }
    } catch {
        $lblStatus.Text = "오류: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("오류: $($_.Exception.Message)","오류")
    } finally {
        $script:proc = $null
        Set-Busy $false
        $btnCancel.Enabled = $false
        Update-LoginState
    }
})

# ---------------------------------
# yt-dlp 업데이트 (yt-dlp -U)
# ---------------------------------
$btnUpdate.Add_Click({
    Set-Busy $true
    $btnCancel.Enabled = $true
    $progressBar.Value = 0
    $lblStatus.Text = "yt-dlp 업데이트 확인 중..."
    $script:cancelled = $false
    $script:updateLog = New-Object System.Collections.Generic.List[string]

    try {
        $exitCode = Invoke-YtDlp @("-U") {
            param($line)
            if ($line.Trim()) {
                $script:updateLog.Add($line)
                $lblStatus.Text = $line
            }
        }
        $summary = $script:updateLog -join "`n"

        if ($script:cancelled) {
            $lblStatus.Text = "업데이트가 취소되었습니다."
        } elseif ($exitCode -eq 0) {
            $progressBar.Value = 1000
            Update-VersionLabel
            $lblStatus.Text = "yt-dlp $($lblVersion.Text) 사용 중"
            [System.Windows.Forms.MessageBox]::Show($summary, "yt-dlp 업데이트")
        } else {
            $lblStatus.Text = "업데이트 실패 (ExitCode: $exitCode)"
            [System.Windows.Forms.MessageBox]::Show(
                "yt-dlp 업데이트에 실패했습니다.`n`n$summary`n`n" +
                "※ 설치 폴더에 쓰기 권한이 있는지, 다른 곳에서 yt-dlp가 실행 중인지 확인해 주세요.",
                "오류"
            )
        }
    } catch {
        $lblStatus.Text = "오류: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("오류: $($_.Exception.Message)","오류")
    } finally {
        $script:proc = $null
        Set-Busy $false
        $btnCancel.Enabled = $false
    }
})

# ---------------------------------
# YouTube 로그인
#   로그인 전용 프로필로 Chrome(없으면 Edge)을 원격 디버깅 포트와 함께 띄우고,
#   DevTools 프로토콜로 쿠키를 읽어 로그인되면 cookies.txt(Netscape 형식)로 저장
#   (브라우저 쿠키 DB를 직접 읽지 않으므로 Chrome 쿠키 암호화 / 파일 잠금 영향 없음)
# ---------------------------------
function Find-LoginBrowser {
    foreach ($exe in @('chrome.exe', 'msedge.exe')) {
        foreach ($root in @('HKCU:', 'HKLM:')) {
            $path = (Get-ItemProperty "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue).'(default)'
            if ($path -and (Test-Path $path)) { return $path }
        }
    }
    return $null
}

function Get-FreePort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

# DevTools 프로토콜 명령 1회 실행 → result 반환 (브라우저가 없으면 예외)
function Invoke-Cdp($port, $method) {
    $wsUrl = (Invoke-RestMethod "http://127.0.0.1:$port/json/version" -TimeoutSec 2).webSocketDebuggerUrl
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $none = [System.Threading.CancellationToken]::None
    try {
        $ws.ConnectAsync([Uri]$wsUrl, $none).Wait()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = $method } | ConvertTo-Json -Compress))
        $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, $none).Wait()

        $ms = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 65536
        do {
            $r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $none).Result
            $ms.Write($buf, 0, $r.Count)
        } while (-not $r.EndOfMessage)
        return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json).result
    } finally {
        $ws.Dispose()
    }
}

# yt-dlp가 인증에 사용하는 YouTube 계정 쿠키 존재 여부
function Test-YouTubeLogin($cookies) {
    return [bool]($cookies | Where-Object {
        $_.domain -match '(^|\.)youtube\.com$' -and $_.name -in @('SAPISID', '__Secure-3PAPISID')
    })
}

# YouTube / Google 쿠키만 Netscape cookies.txt 형식으로 저장
function Save-NetscapeCookies($cookies, $path) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Netscape HTTP Cookie File")
    foreach ($c in $cookies) {
        if ($c.domain -notmatch '(^|\.)(youtube|google)\.com$') { continue }
        $subdomains = if ($c.domain.StartsWith('.')) { 'TRUE' } else { 'FALSE' }
        $secure = if ($c.secure) { 'TRUE' } else { 'FALSE' }
        $expires = if ($c.session) { 0 } else { [long]$c.expires }
        $lines.Add((@($c.domain, $subdomains, $c.path, $secure, $expires, $c.name, $c.value) -join "`t"))
    }
    [System.IO.File]::WriteAllLines($path, $lines)
}

# UI 응답을 유지하며 대기 (로그인 취소 시 즉시 반환)
function Wait-UI($ms) {
    $until = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $until -and -not $script:loginCancelled) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 30
    }
}

$btnLogin.Add_Click({
    $browser = Find-LoginBrowser
    if (-not $browser) {
        [System.Windows.Forms.MessageBox]::Show("로그인에 사용할 Chrome 또는 Edge를 찾을 수 없습니다.","오류")
        return
    }

    Set-Busy $true
    $script:loginCancelled = $false
    $port = Get-FreePort
    $connected = $false
    $loggedIn = $false

    try {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        Start-Process $browser -ArgumentList @(
            "--user-data-dir=`"$loginProfileDir`"",
            "--remote-debugging-port=$port",
            "--no-first-run",
            "--no-default-browser-check",
            $loginUrl
        )
        $lblStatus.Text = "브라우저 창에서 YouTube에 로그인해 주세요. (취소하려면 브라우저 창을 닫으세요)"
        $startedAt = [DateTime]::Now

        while (-not $script:loginCancelled) {
            Wait-UI 1500
            try {
                $cookies = (Invoke-Cdp $port 'Storage.getCookies').cookies
                $connected = $true
            } catch {
                # 연결된 적이 있으면 사용자가 브라우저를 닫은 것, 아니면 아직 시작 중
                if ($connected) { break }
                if (([DateTime]::Now - $startedAt).TotalSeconds -gt 20) {
                    throw "브라우저와 연결할 수 없습니다. 이전 로그인 창이 열려 있다면 닫고 다시 시도해 주세요."
                }
                continue
            }

            if (Test-YouTubeLogin $cookies) {
                # YouTube로 돌아오는 리다이렉트가 끝나 쿠키가 모두 설정될 때까지 잠시 대기
                $lblStatus.Text = "로그인 확인됨. 쿠키 저장 중..."
                Wait-UI 3000
                $cookies = (Invoke-Cdp $port 'Storage.getCookies').cookies
                Save-NetscapeCookies $cookies $cookieFile
                $loggedIn = $true
                break
            }
        }

        if ($loggedIn) {
            $chkUseCookies.Checked = $true
            $lblStatus.Text = "로그인 완료. 비공개 · 연령 제한 영상도 다운로드할 수 있습니다."
        } else {
            $lblStatus.Text = "로그인이 취소되었습니다."
        }
    } catch {
        $lblStatus.Text = "로그인 오류: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("로그인 중 오류가 발생했습니다.`n$($_.Exception.Message)","오류")
    } finally {
        if ($connected) {
            try { Invoke-Cdp $port 'Browser.close' | Out-Null } catch { }
        }
        Set-Busy $false
        Update-LoginState
    }
})

$btnLogout.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "저장된 로그인 쿠키와 로그인 전용 브라우저 프로필을 삭제합니다.`n계속하시겠습니까?",
        "로그아웃",
        [System.Windows.Forms.MessageBoxButtons]::YesNo
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Remove-Item -Path $cookieFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $loginProfileDir) {
            Remove-Item -Path $loginProfileDir -Recurse -Force -ErrorAction Stop
        }
        $lblStatus.Text = "로그아웃되었습니다."
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "로그인 프로필 일부를 삭제하지 못했습니다. 로그인 브라우저 창이 열려 있다면 닫고 다시 시도해 주세요.`n$($_.Exception.Message)",
            "오류"
        )
    }
    Update-LoginState
})

# ---------------------------------
# 폼 실행
# ---------------------------------
[System.Windows.Forms.Application]::Run($form)
