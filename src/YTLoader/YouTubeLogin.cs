using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace YTLoader;

// YouTube 로그인
//   로그인 전용 프로필로 Chrome(없으면 Edge)을 원격 디버깅 포트와 함께 띄우고,
//   DevTools 프로토콜로 쿠키를 읽어 로그인되면 cookies.txt(Netscape 형식)로 저장
//   (브라우저 쿠키 DB를 직접 읽지 않으므로 Chrome 쿠키 암호화 / 파일 잠금 영향 없음)
internal static class YouTubeLogin
{
    public const string LoginUrl = "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Dko%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F";

    public record Cookie(string Name, string Value, string Domain, string Path, double Expires, bool Secure, bool Session);

    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(2) };
    static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    static readonly Regex YouTubeDomain = new(@"(^|\.)youtube\.com$");
    static readonly Regex SavedDomain = new(@"(^|\.)(youtube|google)\.com$");

    public static string? FindBrowser()
    {
        foreach (var exe in new[] { "chrome.exe", "msedge.exe" })
        {
            foreach (var root in new[] { Registry.CurrentUser, Registry.LocalMachine })
            {
                using var key = root.OpenSubKey($@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{exe}");
                if (key?.GetValue(null) is string path && File.Exists(path)) return path;
            }
        }
        return null;
    }

    public static int GetFreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    // DevTools 프로토콜 명령 1회 실행 → result 반환 (브라우저가 없으면 예외)
    static async Task<JsonElement> InvokeCdpAsync(int port, string method)
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var version = await Http.GetFromJsonAsync<JsonElement>($"http://127.0.0.1:{port}/json/version", cts.Token).ConfigureAwait(false);
        var wsUrl = version.GetProperty("webSocketDebuggerUrl").GetString()!;

        using var ws = new ClientWebSocket();
        await ws.ConnectAsync(new Uri(wsUrl), cts.Token).ConfigureAwait(false);
        var request = JsonSerializer.SerializeToUtf8Bytes(new { id = 1, method });
        await ws.SendAsync(request, WebSocketMessageType.Text, true, cts.Token).ConfigureAwait(false);

        using var ms = new MemoryStream();
        var buf = new byte[65536];
        ValueWebSocketReceiveResult r;
        do
        {
            r = await ws.ReceiveAsync(buf.AsMemory(), cts.Token).ConfigureAwait(false);
            ms.Write(buf, 0, r.Count);
        } while (!r.EndOfMessage);

        using var doc = JsonDocument.Parse(ms.ToArray());
        return doc.RootElement.GetProperty("result").Clone();
    }

    public static async Task<Cookie[]> GetCookiesAsync(int port)
    {
        var result = await InvokeCdpAsync(port, "Storage.getCookies").ConfigureAwait(false);
        return result.GetProperty("cookies").Deserialize<Cookie[]>(JsonOptions) ?? [];
    }

    public static Task CloseBrowserAsync(int port) => InvokeCdpAsync(port, "Browser.close");

    // yt-dlp가 인증에 사용하는 YouTube 계정 쿠키 존재 여부
    public static bool IsLoggedIn(IEnumerable<Cookie> cookies) =>
        cookies.Any(c => YouTubeDomain.IsMatch(c.Domain) && c.Name is "SAPISID" or "__Secure-3PAPISID");

    // YouTube / Google 쿠키만 Netscape cookies.txt 형식으로 저장
    public static void SaveNetscapeCookies(IEnumerable<Cookie> cookies, string path)
    {
        var lines = new List<string> { "# Netscape HTTP Cookie File" };
        foreach (var c in cookies)
        {
            if (!SavedDomain.IsMatch(c.Domain)) continue;
            var subdomains = c.Domain.StartsWith('.') ? "TRUE" : "FALSE";
            var secure = c.Secure ? "TRUE" : "FALSE";
            var expires = c.Session ? 0 : (long)c.Expires;
            lines.Add(string.Join('\t', c.Domain, subdomains, c.Path, secure, expires, c.Name, c.Value));
        }
        File.WriteAllLines(path, lines);
    }
}
