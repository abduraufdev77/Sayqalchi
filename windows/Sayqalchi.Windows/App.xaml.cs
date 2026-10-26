using System.Threading;
using System.Windows;
using Application = System.Windows.Application;

namespace Sayqalchi.Windows;
public partial class App : Application
{
    private Mutex? instance;
    private Controller? controller;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--smoke-test")) { _ = SmokeTest.Run(this); return; }
        instance = new Mutex(true, "Local\\Sayqalchi.WritingAssistant", out var first);
        if (!first) { MessageBox.Show("Sayqalchi is already running. Open its ö icon in the notification area.", "Sayqalchi"); Shutdown(); return; }
        controller = new Controller(this); controller.ShowMain();
    }
    protected override void OnExit(ExitEventArgs e) { controller?.Dispose(); instance?.Dispose(); base.OnExit(e); }
}
