using System.Windows;
using Velopack;

namespace YTLoader;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        // 설치 / 업데이트 / 제거 시 Velopack이 넘기는 인자를 처리 (가장 먼저 실행해야 함)
        VelopackApp.Build().Run();

        var ytDlpPath = YtDlp.Find("yt-dlp.exe");
        if (ytDlpPath is null)
        {
            MessageBox.Show("yt-dlp.exe를 찾을 수 없습니다.\nYTLoader.exe와 같은 폴더에 두거나 PATH에 추가해 주세요.", "오류");
            return;
        }

        var app = new App();
        app.InitializeComponent();
        app.Run(new MainWindow(new YtDlp(ytDlpPath)));
    }
}
