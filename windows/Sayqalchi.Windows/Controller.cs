using System.ComponentModel;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Threading;
using Sayqalchi.Core;
using Application = System.Windows.Application;
using Clipboard = System.Windows.Clipboard;

namespace Sayqalchi.Windows;
internal sealed class Controller : INotifyPropertyChanged, IDisposable
{
    internal readonly Settings Settings = Settings.Load();
    private readonly Application app;
    private readonly AutomationWorker worker = new();
    private readonly HttpClient http = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(90) };
    private readonly WritingServices services;
    private readonly KeyboardShortcut keyboard;
    private readonly System.Windows.Forms.NotifyIcon tray;
    private readonly DispatcherTimer pause;
    private readonly WidgetWindow widget;
    private MainWindow? main;
    private CancellationTokenSource? work;
    private Draft? draft;
    private long generation;
    private string input = "", result = "", error = "", appName = "Your apps", status = "";
    private bool busy, applying, manual;
    private Tool tool;
    internal Entry? DictionaryEntry;
    public string Input { get => input; set { if (input == value) return; input = value; Changed(); manual = true; draft = null; Invalidate(); result = ""; error = ""; busy = Enabled; widget.Compact(); ChangedAll(); Schedule(); } }
    public string Result => result;
    public string Error => error;
    public string AppName => appName;
    public string Status => status;
    public bool Busy => busy;
    public bool Enabled => Settings.Enabled;
    public Tool ActiveTool => tool;
    public bool CanApply => Enabled && !busy && draft != null && result.Length > 0 && result != input && tool != Tool.Izohchi;
    public bool CanCopy => !busy && result.Length > 0;
    public string Source { get => Settings.Source; set { Settings.Source = value; Settings.Save(); Invalidate(); _ = Process(); Changed(); } }
    public string Target { get => Settings.Target; set { Settings.Target = value; Settings.Save(); Invalidate(); _ = Process(); Changed(); } }
    public Language[] Languages => Language.All;
    internal Controller(Application app)
    {
        this.app = app; tool = Settings.DefaultTool; services = new(http);
        widget = new(this);
        pause = new(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(650) };
        pause.Tick += async (_, _) => { pause.Stop(); if (manual) await Process(); else await Capture(); };
        keyboard = new(() => app.Dispatcher.BeginInvoke(Toggle), () => app.Dispatcher.BeginInvoke(Typed), () => { if (!CanApply || !widget.IsVisible) return false; app.Dispatcher.BeginInvoke(() => _ = Apply()); return true; }, () => app.Dispatcher.BeginInvoke(Dismiss));
        status = keyboard.Connected ? "Shortcut connected · double-press Right Shift" : "Shortcut unavailable · restart Sayqalchi";
        tray = new() { Text = "Sayqalchi", Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!), Visible = true };
        tray.DoubleClick += (_, _) => app.Dispatcher.Invoke(Toggle);
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Open Sayqalchi", null, (_, _) => app.Dispatcher.Invoke(ShowMain));
        menu.Items.Add("Pause / enable", null, (_, _) => app.Dispatcher.Invoke(Toggle));
        menu.Items.Add("Quit", null, (_, _) => app.Dispatcher.Invoke(app.Shutdown)); tray.ContextMenuStrip = menu;
        if (Enabled) widget.Show();
    }
    public void ShowMain() { main ??= new(this); main.Show(); main.Activate(); }
    public void Toggle()
    {
        Settings.Enabled = !Settings.Enabled; Settings.Save(); Invalidate(); result = ""; input = ""; draft = null; manual = false;
        if (Enabled) widget.Show(); else widget.Hide(); ChangedAll();
    }
    private void Typed()
    {
        if (!Enabled || applying) return;
        manual = false; Invalidate(); result = ""; error = ""; busy = true; widget.Compact(); widget.Show(); ChangedAll(); Schedule();
    }
    private void Schedule() { if (!Enabled) return; pause.Stop(); pause.Start(); }
    private void Invalidate() { generation++; work?.Cancel(); work?.Dispose(); work = null; busy = false; DictionaryEntry = null; }
    public void Dismiss() { Invalidate(); result = ""; error = ""; widget.Compact(); ChangedAll(); }
    public void SelectTool(Tool selected)
    {
        if (tool == selected) return;
        Invalidate(); tool = selected; result = ""; ChangedAll(); _ = Process();
    }
    public void SetDefault(Tool selected) { Settings.DefaultTool = selected; Settings.Save(); SelectTool(selected); ChangedAll(); }
    public async Task Capture()
    {
        if (!Enabled) return;
        var id = generation;
        try
        {
            var captured = await worker.Run(() => EditorAccess.Capture(Settings.ExcludedProcesses)).WaitAsync(TimeSpan.FromSeconds(3));
            if (generation != id || !Enabled) return;
            if (captured == null) { input = ""; result = ""; busy = false; status = "This editor does not expose an editable draft. Use the Playground."; ChangedAll(); return; }
            draft = captured; manual = false; input = captured.Text; appName = captured.App; tool = Settings.DefaultTool; ChangedAll(); await Process();
        }
        catch (Exception e) when (e is not OutOfMemoryException) { if (id == generation) { busy = false; error = "The editor is unavailable. Use the Playground or try again."; ChangedAll(); } }
    }
    private async Task Process()
    {
        Invalidate(); result = ""; error = "";
        if (!Enabled || string.IsNullOrWhiteSpace(input)) { ChangedAll(); return; }
        var id = generation; var sourceText = input; var selected = tool; work = new(); var token = work.Token; busy = true; ChangedAll();
        try
        {
            string output;
            switch (selected)
            {
                case Tool.Format: output = Formatter.Convert(sourceText); break;
                case Tool.Translate: output = await services.Translate(sourceText, Source, Target, Settings.ServiceOptions(), token); break;
                case Tool.Izohchi:
                    var entry = await services.Lookup(WritingServices.DictionaryQuery(sourceText, manual ? sourceText : draft?.Selection), token);
                    if (id != generation) return;
                    DictionaryEntry = entry; output = entry.Render(false); break;
                default: output = DocumentTools.Clean(sourceText); break;
            }
            if (id != generation || token.IsCancellationRequested) return;
            result = output; status = selected == Tool.Document ? DocumentTools.Summary(sourceText) : manual ? "Playground · copy result" : appName + " · Entire draft";
            if (selected == Tool.Format && result == sourceText && !widget.Expanded) result = "";
            if (result.Length > 0) { widget.Show(); widget.ShowResult(); }
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is not OutOfMemoryException)
        { if (id == generation) error = e is InvalidOperationException ? e.Message : "The service is unavailable. Check your connection and try again."; }
        finally { if (id == generation) { busy = false; ChangedAll(); } }
    }
    public async Task Apply()
    {
        if (!CanApply || draft == null) return;
        var captured = draft; var replacement = result;
        if (Native.GetForegroundWindow() != captured.Window)
        {
            if (!Native.OwnForeground() || !Native.SetForegroundWindow(captured.Window)) { error = "Return to the original editor, then press Alt + Enter."; ChangedAll(); return; }
            await Task.Delay(100);
        }
        applying = true;
        try
        {
            var applied = await worker.Run(() => EditorAccess.Apply(captured, replacement, Settings.ExcludedProcesses)).WaitAsync(TimeSpan.FromSeconds(3));
            if (applied) { Dismiss(); status = "Draft updated"; }
            else { error = "The draft or focus changed. Nothing was replaced. Type again to refresh."; }
        }
        catch (Exception e) when (e is not OutOfMemoryException) { error = "The editor could not confirm replacement. Check the draft before trying again."; }
        finally { applying = false; ChangedAll(); }
    }
    public void Copy() { if (CanCopy) { try { Clipboard.SetText(result); } catch (System.Runtime.InteropServices.COMException) { error = "The clipboard is busy. Try again."; ChangedAll(); } } }
    public void More()
    {
        var text = DictionaryEntry?.Render(true) ?? result;
        var details = new Window { Title = "Sayqalchi · Details", Width = 720, Height = 580, Background = System.Windows.Media.Brushes.Black, Foreground = System.Windows.Media.Brushes.White };
        details.Content = new System.Windows.Controls.TextBox { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, VerticalScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility.Auto, Background = System.Windows.Media.Brushes.Black, Foreground = (System.Windows.Media.Brush)app.FindResource("Orange"), Margin = new Thickness(20), FontSize = 17 };
        details.Show();
    }
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    private void ChangedAll() { Changed(""); widget.Refresh(); }
    public void Dispose() { pause.Stop(); work?.Cancel(); keyboard.Dispose(); tray.Dispose(); worker.Dispose(); http.Dispose(); }
}
