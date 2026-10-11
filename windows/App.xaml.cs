using System.Windows;
namespace Framelet;
public partial class App : Application
{
    internal Theme? Appearance { get; private set; }
    protected override void OnExit(ExitEventArgs e) { Appearance?.Dispose(); base.OnExit(e); }
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--self-test")) { try { SelfTest.Run(); Shutdown(0); } catch (Exception ex) { System.IO.File.WriteAllText(System.IO.Path.Combine(AppContext.BaseDirectory, "self-test-error.txt"), ex.ToString()); Shutdown(1); } return; }
        Appearance = new Theme(this);
        new Launcher().Show();
    }
}
