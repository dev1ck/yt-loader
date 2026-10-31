using System.Windows;
using System.Windows.Media;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace YTLoader;

public partial class App : Application
{
    // 강조색: 앱 아이콘의 빨강
    static readonly Color BrandColor = Color.FromRgb(0xEB, 0x4B, 0x3C);

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 시스템 테마(다크 / 라이트)를 따르되, 강조색은 시스템 색 대신 앱 색으로 유지
        ApplicationThemeManager.Changed += (theme, _) => ApplicationAccentColorManager.Apply(BrandColor, theme);
        var theme = ApplicationThemeManager.GetSystemTheme() is SystemTheme.Dark or SystemTheme.HCBlack or SystemTheme.Glow or SystemTheme.CapturedMotion
            ? ApplicationTheme.Dark
            : ApplicationTheme.Light;
        ApplicationThemeManager.Apply(theme, WindowBackdropType.Mica, updateAccent: false);
        ApplicationAccentColorManager.Apply(BrandColor, theme);
    }
}
