using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media.Imaging;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Win32;
using Velopack;
using Velopack.Sources;
using Wpf.Ui.Appearance;
using WpfUi = Wpf.Ui.Controls;

namespace YTLoader;

public partial class MainWindow : WpfUi.FluentWindow
{
    // 앱 업데이트를 받을 GitHub 저장소 (Releases)
    const string RepoUrl = "https://github.com/dev1ck/yt-loader";

    // ---------------------------------
    // 포맷 / 품질 목록 (값, 표시 이름)
    // ---------------------------------
    static readonly (string Value, string Label)[] AudioFormats =
    [
        ("mp3",      "MP3 (범용)"),
        ("m4a",      "M4A (AAC)"),
        ("opus",     "OPUS (고효율)"),
        ("flac",     "FLAC (무손실)"),
        ("wav",      "WAV (무손실)"),
        ("original", "원본 (변환 없음)"),
    ];
    static readonly (string Value, string Label)[] AudioQualities =
    [
        ("0",    "최고 (VBR)"),
        ("320K", "320 kbps"),
        ("256K", "256 kbps"),
        ("192K", "192 kbps"),
        ("128K", "128 kbps"),
    ];
    static readonly (string Value, string Label)[] VideoFormats =
    [
        ("mp4",      "MP4 (호환성 높음)"),
        ("mkv",      "MKV"),
        ("webm",     "WEBM"),
        ("original", "원본 (변환 없음)"),
    ];
    static readonly (string Value, string Label)[] VideoResolutions =
    [
        ("",     "최고 화질"),
        ("2160", "2160p (4K)"),
        ("1440", "1440p"),
        ("1080", "1080p"),
        ("720",  "720p"),
        ("480",  "480p"),
        ("360",  "360p"),
    ];

    // 썸네일 삽입을 지원하는 출력 포맷 (yt-dlp 기준)
    static readonly string[] ThumbnailFormats = ["mp3", "m4a", "opus", "flac", "mp4", "mkv"];
    // 비트레이트 지정이 의미 있는 오디오 포맷 (손실 압축)
    static readonly string[] LossyAudioFormats = ["mp3", "m4a", "opus"];

    // 로그인 데이터 (쿠키 파일 / 로그인 전용 브라우저 프로필)
    static readonly string DataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "YTLoader");
    static readonly string CookieFile = Path.Combine(DataDir, "cookies.txt");
    static readonly string LoginProfileDir = Path.Combine(DataDir, "login-profile");

    static readonly HttpClient Http = new();

    readonly YtDlp _ytDlp;
    // 저장 폴더 (기본: 사용자 Downloads)
    string _outputDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

    // 실행 중인 작업(다운로드 / yt-dlp 업데이트) 취소용, 작업 중 여부
    CancellationTokenSource? _runCts;
    bool _busy;
    // 진행 중인 로그인 (브라우저 원격 디버깅 포트, 취소용)
    int? _loginPort;
    CancellationTokenSource? _loginCts;

    // 영상 정보 미리보기: 입력이 잠시 멈추면 조회, 새 입력이 오면 이전 조회 취소
    readonly DispatcherTimer _infoTimer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    CancellationTokenSource? _infoCts;
    readonly Dictionary<(string Url, bool Playlist), VideoInfo> _infoCache = [];
    VideoInfo? _shownInfo;

    internal MainWindow(YtDlp ytDlp)
    {
        _ytDlp = ytDlp;
        InitializeComponent();

        TxtOutputDir.Text = _outputDir;
        MenuAppVersion.Header = $"YTLoader v{AppVersion}";

        RbAudio.Checked += (_, _) => UpdateModeState();
        RbVideo.Checked += (_, _) => UpdateModeState();
        _infoTimer.Tick += (_, _) => { _infoTimer.Stop(); RequestInfo(); };
        Loaded += (_, _) => SystemThemeWatcher.Watch(this, WpfUi.WindowBackdropType.Mica, updateAccents: false);
        Closing += MainWindow_Closing;
        ContentRendered += async (_, _) => await CheckAppUpdateAsync();

        UpdateModeState();
        UpdateLoginState();
        UpdateVersionLabel();
    }

    static string AppVersion =>
        Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "?";

    // ---------------------------------
    // 모드 / 포맷에 따라 목록 및 옵션 갱신
    // ---------------------------------
    static void SetComboItems(ComboBox combo, (string Value, string Label)[] items)
    {
        combo.ItemsSource = items.Select(i => i.Label).ToArray();
        combo.SelectedIndex = 0;
    }

    string GetSelectedFormat() =>
        RbAudio.IsChecked == true ? AudioFormats[CboFormat.SelectedIndex].Value : VideoFormats[CboFormat.SelectedIndex].Value;

    void UpdateOptionState()
    {
        if (CboFormat.SelectedIndex < 0) return;
        var fmt = GetSelectedFormat();

        // 무손실 / 원본은 비트레이트 지정 불가
        CboQuality.IsEnabled = RbAudio.IsChecked != true || LossyAudioFormats.Contains(fmt);
        ChkThumbnail.IsEnabled = ThumbnailFormats.Contains(fmt);
    }

    void UpdateModeState()
    {
        if (RbAudio.IsChecked == true)
        {
            LblQuality.Text = "음질";
            SetComboItems(CboFormat, AudioFormats);
            SetComboItems(CboQuality, AudioQualities);
        }
        else
        {
            LblQuality.Text = "해상도";
            SetComboItems(CboFormat, VideoFormats);
            SetComboItems(CboQuality, VideoResolutions);
        }
        UpdateOptionState();
    }

    void CboFormat_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateOptionState();

    // 쿠키 파일 유무로 로그인 상태 표시
    void UpdateLoginState()
    {
        var loggedIn = File.Exists(CookieFile);
        TxtAccount.Text = loggedIn ? "로그인됨" : "로그인";
        MenuLoginStatus.Header = loggedIn
            ? $"● 로그인됨 ({File.GetLastWriteTime(CookieFile):yyyy-MM-dd})"
            : "○ 로그인 안 됨";
        MenuUseCookies.IsEnabled = loggedIn;
        MenuLogin.Header = loggedIn ? "다시 로그인…" : "로그인…";
        MenuLogout.IsEnabled = loggedIn;
    }

    // 다운로드 / 정보 조회에 넘길 쿠키 파일 (로그인 안 됨 또는 사용 안 함이면 null)
    string? CookieFileIfUsed => File.Exists(CookieFile) && MenuUseCookies.IsChecked ? CookieFile : null;

    // yt-dlp.exe 파일 버전 정보로 현재 버전 표시 (프로세스 실행 없이)
    void UpdateVersionLabel()
    {
        var ver = FileVersionInfo.GetVersionInfo(_ytDlp.Path).FileVersion;
        MenuYtDlpVersion.Header = $"yt-dlp v{(string.IsNullOrEmpty(ver) ? "알 수 없음" : ver)}";
    }

    static void OpenMenu(FrameworkElement button)
    {
        button.ContextMenu.PlacementTarget = button;
        button.ContextMenu.Placement = PlacementMode.Bottom;
        button.ContextMenu.IsOpen = true;
    }

    void BtnAccount_Click(object sender, RoutedEventArgs e) => OpenMenu(BtnAccount);
    void BtnMore_Click(object sender, RoutedEventArgs e) => OpenMenu(BtnMore);

    void ShowNotice(WpfUi.InfoBarSeverity severity, string title, string message)
    {
        Notice.Severity = severity;
        Notice.Title = title;
        Notice.Message = message;
        Notice.IsOpen = true;
    }

    // ---------------------------------
    // 영상 정보 미리보기
    // ---------------------------------
    void TxtUrl_TextChanged(object sender, TextChangedEventArgs e)
    {
        _infoTimer.Stop();
        _infoTimer.Start();
    }

    void BtnPaste_Click(object sender, RoutedEventArgs e)
    {
        if (!Clipboard.ContainsText()) return;
        TxtUrl.Text = Clipboard.GetText().Trim();
        TxtUrl.CaretIndex = TxtUrl.Text.Length;
        _infoTimer.Stop();
        RequestInfo();
    }

    // 재생목록 여부에 따라 보여줄 정보가 달라짐
    void ChkPlaylist_Click(object sender, RoutedEventArgs e) => RequestInfo();

    void RequestInfo()
    {
        _infoCts?.Cancel();
        _infoCts = null;

        var url = TxtUrl.Text.Trim();
        if (url == "")
        {
            ShowPreview(PreviewEmpty);
            return;
        }
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
        {
            TxtPreviewError.Text = "http:// 또는 https:// 로 시작하는 링크를 입력해 주세요.";
            ShowPreview(PreviewError);
            return;
        }

        var playlist = ChkPlaylist.IsChecked == true && url.Contains("list=");
        if (_infoCache.TryGetValue((url, playlist), out var cached))
        {
            ShowInfo(cached);
            return;
        }
        _ = LoadInfoAsync(url, playlist);
    }

    async Task LoadInfoAsync(string url, bool playlist)
    {
        var cts = _infoCts = new CancellationTokenSource();
        ShowPreview(PreviewLoading);
        try
        {
            var info = await _ytDlp.FetchInfoAsync(url, playlist, CookieFileIfUsed, cts.Token);
            _infoCache[(url, playlist)] = info;
            if (!cts.IsCancellationRequested) ShowInfo(info);
        }
        catch (Exception ex)
        {
            if (cts.IsCancellationRequested) return;  // 새 입력으로 대체됨
            TxtPreviewError.Text = ex.Message;
            ShowPreview(PreviewError);
        }
    }

    void ShowPreview(FrameworkElement state)
    {
        foreach (var s in new FrameworkElement[] { PreviewEmpty, PreviewLoading, PreviewInfo, PreviewError })
        {
            s.Visibility = s == state ? Visibility.Visible : Visibility.Collapsed;
        }
        if (state != PreviewInfo) _shownInfo = null;
    }

    void ShowInfo(VideoInfo info)
    {
        var meta = new List<string>();
        if (info.Channel is not null) meta.Add(info.Channel);
        if (info.ViewCount is long views) meta.Add($"조회수 {FormatCount(views)}회");
        if (info.UploadDate is DateTime date) meta.Add(date.ToString("yyyy. M. d."));

        TxtTitle.Text = info.Title;
        TxtMeta.Text = string.Join(" · ", meta);
        TxtDuration.Text = info.PlaylistCount is int count ? $"재생목록 · {count}개"
            : info.Duration is TimeSpan d ? FormatDuration(d) : "";
        BadgeDuration.Visibility = TxtDuration.Text == "" ? Visibility.Collapsed : Visibility.Visible;
        VideoChips.ItemsSource = info.VideoQualities;
        AudioChips.ItemsSource = info.AudioQualities;
        IconVideoChips.Visibility = info.VideoQualities.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        IconAudioChips.Visibility = info.AudioQualities.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        ImgThumb.Source = null;

        ShowPreview(PreviewInfo);
        _shownInfo = info;
        _ = LoadThumbnailAsync(info);
    }

    async Task LoadThumbnailAsync(VideoInfo info)
    {
        if (info.ThumbnailUrl is null) return;
        // WebP 대신 같은 이름의 JPEG 사용 (WPF 기본 디코더는 WebP를 지원하지 않을 수 있음)
        var url = info.ThumbnailUrl.Replace("/vi_webp/", "/vi/").Replace(".webp", ".jpg");
        try
        {
            var bytes = await Http.GetByteArrayAsync(url);
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.DecodePixelWidth = 512;
            bmp.StreamSource = new MemoryStream(bytes);
            bmp.EndInit();
            bmp.Freeze();
            if (_shownInfo == info) ImgThumb.Source = bmp;
        }
        catch
        {
            // 썸네일 없이 표시
        }
    }

    static string FormatDuration(TimeSpan t) => t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss");

    static string FormatCount(long n) => n switch
    {
        >= 100_000_000 => $"{n / 100_000_000d:0.#}억",
        >= 10_000 => $"{n / 10_000d:0.#}만",
        _ => n.ToString("N0"),
    };

    // ---------------------------------
    // 저장 폴더 선택 / 열기
    // ---------------------------------
    void BtnBrowse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog();
        if (Directory.Exists(_outputDir)) dialog.InitialDirectory = _outputDir;

        if (dialog.ShowDialog(this) == true)
        {
            _outputDir = dialog.FolderName;
            TxtOutputDir.Text = _outputDir;
        }
    }

    void BtnOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (!Directory.Exists(_outputDir))
        {
            ShowNotice(WpfUi.InfoBarSeverity.Warning, "폴더가 없습니다", "먼저 다운로드를 진행하거나 폴더를 생성해 주세요.");
            return;
        }
        Process.Start("explorer.exe", _outputDir)?.Dispose();
    }

    // ---------------------------------
    // 작업 상태
    // ---------------------------------
    // 작업(다운로드 / 업데이트 / 로그인) 중 입력 잠금
    void SetBusy(bool busy)
    {
        _busy = busy;
        foreach (var c in new UIElement[] { BtnDownload, OptionsInputs, BtnBrowse, BtnAccount, MenuYtDlpUpdate })
        {
            c.IsEnabled = !busy;
        }
    }

    // 취소 가능한 작업(다운로드 / yt-dlp 업데이트) 시작 / 종료
    void SetRunning(bool running)
    {
        SetBusy(running);
        BtnCancel.Visibility = running ? Visibility.Visible : Visibility.Collapsed;
        Taskbar.ProgressState = running ? TaskbarItemProgressState.Normal : TaskbarItemProgressState.None;
        if (running)
        {
            _runCts = new CancellationTokenSource();
            Notice.IsOpen = false;
            SetProgress(0);
        }
    }

    void SetProgress(double fraction)
    {
        Progress.Value = fraction * 1000;
        Taskbar.ProgressValue = fraction;
    }

    void BtnCancel_Click(object sender, RoutedEventArgs e) => _runCts?.Cancel();

    void MainWindow_Closing(object? sender, CancelEventArgs e)
    {
        _runCts?.Cancel();
        _infoCts?.Cancel();
        _loginCts?.Cancel();
        if (_loginPort is int port)
        {
            try { YouTubeLogin.CloseBrowserAsync(port).Wait(3000); } catch { }
        }
    }

    // ---------------------------------
    // yt-dlp 인자 구성
    // ---------------------------------
    List<string> BuildYtDlpArgs(string url, string dir)
    {
        var fmt = GetSelectedFormat();
        var ytArgs = _ytDlp.CreateArgs();

        if (RbAudio.IsChecked == true)
        {
            ytArgs.AddRange(["-f", "bestaudio/best"]);
            if (fmt != "original")
            {
                // yt-dlp -x --audio-format <fmt> [--audio-quality <q>]
                ytArgs.AddRange(["-x", "--audio-format", fmt]);
                if (LossyAudioFormats.Contains(fmt))
                {
                    ytArgs.AddRange(["--audio-quality", AudioQualities[CboQuality.SelectedIndex].Value]);
                }
            }
        }
        else
        {
            // 해상도 상한 + (선택 시) 컨테이너에 맞는 스트림 우선
            var height = VideoResolutions[CboQuality.SelectedIndex].Value;
            var sort = new List<string>();
            if (height != "") sort.Add($"res:{height}");
            if (fmt == "mp4") sort.Add("ext:mp4:m4a");
            if (fmt == "webm") sort.Add("ext:webm:webm");

            ytArgs.AddRange(["-f", "bv*+ba/b"]);
            if (sort.Count > 0) ytArgs.AddRange(["-S", string.Join(',', sort)]);
            if (fmt != "original") ytArgs.AddRange(["--merge-output-format", fmt, "--remux-video", fmt]);
        }

        if (ChkThumbnail.IsEnabled && ChkThumbnail.IsChecked == true) ytArgs.Add("--embed-thumbnail");
        if (ChkMetadata.IsChecked == true) ytArgs.Add("--embed-metadata");
        if (CookieFileIfUsed is { } cookieFile) ytArgs.AddRange(["--cookies", cookieFile]);

        string outputTemplate;
        if (ChkPlaylist.IsChecked == true)
        {
            ytArgs.Add("--yes-playlist");
            outputTemplate = Path.Combine(dir, "%(playlist_title|Playlist)s", "%(playlist_index|0)03d - %(title)s.%(ext)s");
        }
        else
        {
            ytArgs.Add("--no-playlist");
            outputTemplate = Path.Combine(dir, "%(title)s.%(ext)s");
        }

        ytArgs.AddRange(["--newline", "--progress", "-o", outputTemplate, url]);
        return ytArgs;
    }

    // yt-dlp 출력 한 줄 → 진행률 / 상태 반영
    void UpdateProgressFromLine(string line)
    {
        Match m;
        if ((m = Regex.Match(line, @"^\[download\]\s+([\d\.]+)%(.*)$")).Success)
        {
            SetProgress(Math.Min(1, double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) / 100));
            TxtStatus.Text = $"다운로드 중... {m.Groups[1].Value}%{Regex.Replace(m.Groups[2].Value, @"\s+", " ")}";
        }
        else if ((m = Regex.Match(line, @"^\[download\] Downloading item (\d+) of (\d+)")).Success)
        {
            TxtStatus.Text = $"재생목록 {m.Groups[1].Value} / {m.Groups[2].Value} 항목 처리 중...";
        }
        else if ((m = Regex.Match(line, @"^\[(ExtractAudio|Merger|VideoRemuxer|VideoConvertor|EmbedThumbnail|Metadata|FixupM4a|FixupM3u8)\]")).Success)
        {
            SetProgress(1);
            TxtStatus.Text = $"변환 / 후처리 중... [{m.Groups[1].Value}]";
        }
    }

    // ---------------------------------
    // 다운로드 (정보 미리보기를 기다리지 않음)
    // ---------------------------------
    async void BtnDownload_Click(object sender, RoutedEventArgs e)
    {
        var url = TxtUrl.Text.Trim();
        if (url == "")
        {
            ShowNotice(WpfUi.InfoBarSeverity.Warning, "링크를 입력해 주세요", "");
            TxtUrl.Focus();
            return;
        }

        // 폴더 없으면 생성 시도
        try
        {
            Directory.CreateDirectory(_outputDir);
        }
        catch (Exception ex)
        {
            ShowNotice(WpfUi.InfoBarSeverity.Error, "저장 폴더를 만들 수 없습니다", ex.Message);
            return;
        }

        // 컨트롤의 IsEnabled 값을 참조하므로 입력 잠금(SetRunning) 전에 인자 구성
        var ytArgs = BuildYtDlpArgs(url, _outputDir);

        SetRunning(true);
        TxtStatus.Text = "다운로드 준비 중...";
        var lastError = "";

        try
        {
            var exitCode = await _ytDlp.RunAsync(ytArgs, line =>
            {
                UpdateProgressFromLine(line);
                if (line.StartsWith("ERROR:")) lastError = line["ERROR:".Length..].Trim();
            }, _runCts!.Token);

            if (exitCode == 0)
            {
                SetProgress(1);
                TxtStatus.Text = "다운로드 완료";
                ShowNotice(WpfUi.InfoBarSeverity.Success, "다운로드 완료", $"{_outputDir}에 저장했습니다.");
            }
            else
            {
                TxtStatus.Text = $"다운로드 실패 (종료 코드 {exitCode})";
                ShowNotice(WpfUi.InfoBarSeverity.Error, "다운로드 중 오류가 발생했습니다",
                    $"{lastError}\n더보기(…) → 'yt-dlp 업데이트' 후 다시 시도해 보세요. 비공개 · 연령 제한 영상이라면 먼저 로그인이 필요합니다.");
            }
        }
        catch (OperationCanceledException)
        {
            SetProgress(0);
            TxtStatus.Text = "다운로드가 취소되었습니다.";
        }
        catch (Exception ex)
        {
            TxtStatus.Text = $"오류: {ex.Message}";
            ShowNotice(WpfUi.InfoBarSeverity.Error, "오류", ex.Message);
        }
        finally
        {
            SetRunning(false);
            UpdateLoginState();
        }
    }

    // ---------------------------------
    // yt-dlp 업데이트 (yt-dlp -U)
    // ---------------------------------
    async void MenuYtDlpUpdate_Click(object sender, RoutedEventArgs e)
    {
        SetRunning(true);
        TxtStatus.Text = "yt-dlp 업데이트 확인 중...";
        var updateLog = new List<string>();

        try
        {
            var exitCode = await _ytDlp.RunAsync(["-U"], line =>
            {
                if (line.Trim() == "") return;
                updateLog.Add(line);
                TxtStatus.Text = line;
            }, _runCts!.Token);
            var summary = string.Join('\n', updateLog);

            if (exitCode == 0)
            {
                SetProgress(1);
                UpdateVersionLabel();
                TxtStatus.Text = $"{MenuYtDlpVersion.Header} 사용 중";
                ShowNotice(WpfUi.InfoBarSeverity.Success, "yt-dlp 업데이트", summary);
            }
            else
            {
                TxtStatus.Text = $"업데이트 실패 (종료 코드 {exitCode})";
                ShowNotice(WpfUi.InfoBarSeverity.Error, "yt-dlp 업데이트에 실패했습니다",
                    $"{summary}\n설치 폴더에 쓰기 권한이 있는지, 다른 곳에서 yt-dlp가 실행 중인지 확인해 주세요.");
            }
        }
        catch (OperationCanceledException)
        {
            TxtStatus.Text = "업데이트가 취소되었습니다.";
        }
        catch (Exception ex)
        {
            TxtStatus.Text = $"오류: {ex.Message}";
            ShowNotice(WpfUi.InfoBarSeverity.Error, "오류", ex.Message);
        }
        finally
        {
            SetRunning(false);
        }
    }

    // ---------------------------------
    // 앱 업데이트 (GitHub Releases, Velopack)
    //   시작 시 새 버전을 확인하고, 사용자가 동의하면 받아서 적용 후 재시작
    // ---------------------------------
    async Task CheckAppUpdateAsync()
    {
        var mgr = new UpdateManager(new GithubSource(RepoUrl, null, false));
        // 설치되지 않은 실행(dotnet run, 빌드 폴더 직접 실행)은 업데이트 대상 아님
        if (!mgr.IsInstalled) return;

        UpdateInfo? update;
        try
        {
            update = await mgr.CheckForUpdatesAsync();
        }
        catch
        {
            return;  // 오프라인 등 확인 실패는 다음 실행 때 다시 확인
        }
        // 그 사이 사용자가 다운로드 등을 시작했다면 방해하지 않음
        if (update is null || _busy) return;

        var answer = await new WpfUi.MessageBox
        {
            Title = "YTLoader 업데이트",
            Content = $"새 버전 v{update.TargetFullRelease.Version}이(가) 있습니다. (현재 v{mgr.CurrentVersion})\n지금 업데이트하고 다시 시작할까요?",
            PrimaryButtonText = "업데이트",
            CloseButtonText = "나중에",
        }.ShowDialogAsync();
        if (answer != WpfUi.MessageBoxResult.Primary || _busy) return;

        SetBusy(true);
        SetProgress(0);
        TxtStatus.Text = "앱 업데이트 다운로드 중...";
        try
        {
            await mgr.DownloadUpdatesAsync(update, pct => Dispatcher.InvokeAsync(() =>
            {
                SetProgress(pct / 100.0);
                TxtStatus.Text = $"앱 업데이트 다운로드 중... {pct}%";
            }));
            mgr.ApplyUpdatesAndRestart(update);
        }
        catch (Exception ex)
        {
            TxtStatus.Text = "앱 업데이트 실패";
            ShowNotice(WpfUi.InfoBarSeverity.Error, "앱 업데이트에 실패했습니다", ex.Message);
            SetBusy(false);
        }
    }

    // ---------------------------------
    // YouTube 로그인 / 로그아웃
    // ---------------------------------
    async void MenuLogin_Click(object sender, RoutedEventArgs e)
    {
        var browser = YouTubeLogin.FindBrowser();
        if (browser is null)
        {
            ShowNotice(WpfUi.InfoBarSeverity.Error, "로그인할 수 없습니다", "로그인에 사용할 Chrome 또는 Edge를 찾을 수 없습니다.");
            return;
        }

        SetBusy(true);
        _loginCts = new CancellationTokenSource();
        var ct = _loginCts.Token;
        var port = YouTubeLogin.GetFreePort();
        var connected = false;
        var loggedIn = false;

        try
        {
            Directory.CreateDirectory(DataDir);
            var psi = new ProcessStartInfo(browser)
            {
                ArgumentList =
                {
                    $"--user-data-dir={LoginProfileDir}",
                    $"--remote-debugging-port={port}",
                    "--no-first-run",
                    "--no-default-browser-check",
                    YouTubeLogin.LoginUrl,
                },
            };
            Process.Start(psi)?.Dispose();
            _loginPort = port;
            TxtStatus.Text = "브라우저 창에서 YouTube에 로그인해 주세요. (취소하려면 브라우저 창을 닫으세요)";
            var startedAt = DateTime.Now;

            while (true)
            {
                await Task.Delay(1500, ct);
                YouTubeLogin.Cookie[] cookies;
                try
                {
                    cookies = await YouTubeLogin.GetCookiesAsync(port);
                    connected = true;
                }
                catch (Exception) when (!ct.IsCancellationRequested)
                {
                    // 연결된 적이 있으면 사용자가 브라우저를 닫은 것, 아니면 아직 시작 중
                    if (connected) break;
                    if ((DateTime.Now - startedAt).TotalSeconds > 20)
                    {
                        throw new InvalidOperationException("브라우저와 연결할 수 없습니다. 이전 로그인 창이 열려 있다면 닫고 다시 시도해 주세요.");
                    }
                    continue;
                }

                if (YouTubeLogin.IsLoggedIn(cookies))
                {
                    // YouTube로 돌아오는 리다이렉트가 끝나 쿠키가 모두 설정될 때까지 잠시 대기
                    TxtStatus.Text = "로그인 확인됨. 쿠키 저장 중...";
                    await Task.Delay(3000, ct);
                    cookies = await YouTubeLogin.GetCookiesAsync(port);
                    YouTubeLogin.SaveNetscapeCookies(cookies, CookieFile);
                    loggedIn = true;
                    break;
                }
            }

            if (loggedIn)
            {
                MenuUseCookies.IsChecked = true;
                TxtStatus.Text = "준비됨";
                ShowNotice(WpfUi.InfoBarSeverity.Success, "로그인 완료", "비공개 · 연령 제한 영상도 다운로드할 수 있습니다.");
            }
            else
            {
                TxtStatus.Text = "로그인이 취소되었습니다.";
            }
        }
        catch (Exception) when (ct.IsCancellationRequested)
        {
            // 창 닫힘 (브라우저는 Closing에서 닫음)
            return;
        }
        catch (Exception ex)
        {
            TxtStatus.Text = "로그인 오류";
            ShowNotice(WpfUi.InfoBarSeverity.Error, "로그인 중 오류가 발생했습니다", ex.Message);
        }

        _loginPort = null;
        if (connected)
        {
            try { await YouTubeLogin.CloseBrowserAsync(port); } catch { }
        }
        SetBusy(false);
        UpdateLoginState();
    }

    async void MenuLogout_Click(object sender, RoutedEventArgs e)
    {
        var answer = await new WpfUi.MessageBox
        {
            Title = "로그아웃",
            Content = "저장된 로그인 쿠키와 로그인 전용 브라우저 프로필을 삭제합니다.\n계속하시겠습니까?",
            PrimaryButtonText = "로그아웃",
            CloseButtonText = "취소",
        }.ShowDialogAsync();
        if (answer != WpfUi.MessageBoxResult.Primary) return;

        try
        {
            File.Delete(CookieFile);
            if (Directory.Exists(LoginProfileDir)) Directory.Delete(LoginProfileDir, recursive: true);
            TxtStatus.Text = "로그아웃되었습니다.";
        }
        catch (Exception ex)
        {
            ShowNotice(WpfUi.InfoBarSeverity.Error, "로그인 프로필 일부를 삭제하지 못했습니다",
                $"로그인 브라우저 창이 열려 있다면 닫고 다시 시도해 주세요.\n{ex.Message}");
        }
        UpdateLoginState();
    }
}
