using System.Globalization;
using System.Text.Json;

namespace YTLoader;

// yt-dlp -J 결과 중 미리보기에 표시할 정보
internal sealed record VideoInfo(
    string Title,
    string? Channel,
    TimeSpan? Duration,
    long? ViewCount,
    DateTime? UploadDate,
    string? ThumbnailUrl,
    int? PlaylistCount,
    string[] VideoQualities,
    string[] AudioQualities)
{
    public static VideoInfo Parse(JsonElement j)
    {
        var isPlaylist = Str(j, "_type") == "playlist";
        var formats = j.TryGetProperty("formats", out var f) && f.ValueKind == JsonValueKind.Array
            ? f.EnumerateArray().ToArray()
            : [];

        // 해상도별 최고 fps (예: 2160p60, 1080p60, 720p), 360p 미만은 생략
        var videoFormats = formats.Where(x => Str(x, "vcodec") is { } v && v != "none" && Num(x, "height") > 0).ToArray();
        var videoQualities = (videoFormats.Any(x => Num(x, "height") >= 360) ? videoFormats.Where(x => Num(x, "height") >= 360) : videoFormats)
            .GroupBy(x => (int)Num(x, "height")!)
            .OrderByDescending(g => g.Key)
            .Select(g => g.Max(x => Num(x, "fps") ?? 0) > 30 ? $"{g.Key}p{g.Max(x => (int)(Num(x, "fps") ?? 0))}" : $"{g.Key}p")
            .ToArray();

        // 코덱별 최고 비트레이트 (예: Opus 160kbps, AAC 130kbps)
        var audioQualities = formats
            .Where(x => Str(x, "vcodec") == "none" && Str(x, "acodec") is { } a && a != "none" && Num(x, "abr") > 0)
            .GroupBy(x => CodecName(Str(x, "acodec")!))
            .Select(g => (Codec: g.Key, Abr: g.Max(x => Num(x, "abr")!.Value)))
            .OrderByDescending(x => x.Abr)
            .Select(x => $"{x.Codec} {Math.Round(x.Abr)}kbps")
            .ToArray();

        int? playlistCount = null;
        if (isPlaylist)
        {
            playlistCount = (int?)Num(j, "playlist_count")
                ?? (j.TryGetProperty("entries", out var e) && e.ValueKind == JsonValueKind.Array ? e.GetArrayLength() : 0);
        }

        return new VideoInfo(
            Title: Str(j, "title") ?? "(제목 없음)",
            Channel: Str(j, "channel") ?? Str(j, "uploader"),
            Duration: Num(j, "duration") is double d ? TimeSpan.FromSeconds(d) : null,
            ViewCount: (long?)Num(j, "view_count"),
            UploadDate: DateTime.TryParseExact(Str(j, "upload_date"), "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : null,
            ThumbnailUrl: Str(j, "thumbnail") ?? LastThumbnail(j),
            PlaylistCount: playlistCount,
            VideoQualities: videoQualities,
            AudioQualities: audioQualities);
    }

    static string CodecName(string acodec) => acodec switch
    {
        _ when acodec.StartsWith("opus") => "Opus",
        _ when acodec.StartsWith("mp4a") => "AAC",
        _ => acodec.Split('.')[0].ToUpperInvariant(),
    };

    // 재생목록은 thumbnail 대신 thumbnails 목록만 있음 (마지막이 가장 큼)
    static string? LastThumbnail(JsonElement j) =>
        j.TryGetProperty("thumbnails", out var t) && t.ValueKind == JsonValueKind.Array
            ? t.EnumerateArray().Select(x => Str(x, "url")).LastOrDefault(u => u is not null)
            : null;

    static string? Str(JsonElement j, string name) =>
        j.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static double? Num(JsonElement j, string name) =>
        j.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
}
