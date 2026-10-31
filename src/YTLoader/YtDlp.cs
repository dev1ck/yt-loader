using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace YTLoader;

// yt-dlp 실행 (같은 폴더의 ffmpeg / deno를 함께 지정)
internal sealed class YtDlp(string path)
{
    // ffmpeg / deno(YouTube 추출용 JS 런타임): 같은 폴더에 있으면 직접 지정, 없으면 PATH 사용
    readonly string? _ffmpegPath = FindLocal("ffmpeg.exe");
    readonly string? _denoPath = FindLocal("deno.exe");

    public string Path => path;

    // 실행 파일과 같은 폴더에 있는 도구 경로 (없으면 null)
    static string? FindLocal(string exe)
    {
        var p = System.IO.Path.Combine(AppContext.BaseDirectory, exe);
        return File.Exists(p) ? p : null;
    }

    // 같은 폴더 우선, 없으면 PATH에서 탐색
    public static string? Find(string exe) =>
        FindLocal(exe) ??
        (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(dir => System.IO.Path.Combine(dir.Trim(), exe))
            .FirstOrDefault(File.Exists);

    // 공통 인자 (ffmpeg / deno 경로)
    public List<string> CreateArgs()
    {
        var args = new List<string>();
        if (_ffmpegPath is not null) args.AddRange(["--ffmpeg-location", _ffmpegPath]);
        if (_denoPath is not null) args.AddRange(["--js-runtimes", $"deno:{_denoPath}"]);
        return args;
    }

    // 실행: 출력(stdout / stderr)을 한 줄씩 호출한 스레드(UI)에서 onLine에 전달, 종료 코드 반환
    // 취소되면 하위 프로세스(ffmpeg 등)까지 종료하고 OperationCanceledException
    public async Task<int> RunAsync(IEnumerable<string> args, Action<string> onLine, CancellationToken ct)
    {
        // 출력 이벤트는 백그라운드 스레드에서 발생하므로 Progress로 UI 스레드에 넘김
        IProgress<string> progress = new Progress<string>(onLine);
        using var proc = Start(args);
        proc.OutputDataReceived += (_, e) => { if (e.Data is not null) progress.Report(e.Data); };
        proc.ErrorDataReceived += (_, e) => { if (e.Data is not null) progress.Report(e.Data); };
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();
        await WaitAsync(proc, ct);
        return proc.ExitCode;
    }

    // 영상 / 재생목록 정보 조회 (yt-dlp -J, 재생목록은 항목 목록만 빠르게)
    public async Task<VideoInfo> FetchInfoAsync(string url, bool playlist, string? cookieFile, CancellationToken ct)
    {
        var args = CreateArgs();
        args.AddRange(["-J", "--flat-playlist", playlist ? "--yes-playlist" : "--no-playlist"]);
        if (cookieFile is not null) args.AddRange(["--cookies", cookieFile]);
        args.Add(url);

        using var proc = Start(args);
        var stdout = proc.StandardOutput.ReadToEndAsync(CancellationToken.None);
        var stderr = proc.StandardError.ReadToEndAsync(CancellationToken.None);
        await WaitAsync(proc, ct);

        if (proc.ExitCode != 0)
        {
            var error = (await stderr).Split('\n').LastOrDefault(l => l.StartsWith("ERROR:"));
            throw new InvalidOperationException(error?["ERROR:".Length..].Trim() ?? $"yt-dlp 종료 코드 {proc.ExitCode}");
        }
        using var doc = JsonDocument.Parse(await stdout);
        return VideoInfo.Parse(doc.RootElement);
    }

    Process Start(IEnumerable<string> args)
    {
        var psi = new ProcessStartInfo(path)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        return Process.Start(psi)!;
    }

    static async Task WaitAsync(Process proc, CancellationToken ct)
    {
        // 취소 즉시(Cancel 호출 중에) 종료해야 창을 닫을 때도 프로세스가 남지 않음
        using (ct.Register(() => { try { proc.Kill(entireProcessTree: true); } catch (InvalidOperationException) { } }))
        {
            await proc.WaitForExitAsync();
        }
        ct.ThrowIfCancellationRequested();
    }
}
