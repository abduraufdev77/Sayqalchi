using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Sayqalchi.Core;
using Button = System.Windows.Controls.Button;

namespace Sayqalchi.Windows;
public partial class WidgetWindow : Window
{
    private readonly Controller controller;
    private readonly DispatcherTimer hoverDelay = new() { Interval = TimeSpan.FromMilliseconds(250) };
    public bool Expanded { get; private set; }
    private bool showingResult;
    internal WidgetWindow(Controller controller)
    {
        this.controller = controller; InitializeComponent(); DataContext = controller;
        SourceInitialized += (_, _) => { Native.NoActivate(this); Position(); };
        SizeChanged += (_, _) => Position();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += DisplayChanged;
        Closed += (_, _) => { Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= DisplayChanged; hoverDelay.Stop(); };
        hoverDelay.Tick += (_, _) => { hoverDelay.Stop(); Expanded = false; Refresh(); };
    }
    private void DisplayChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(Position);
    private void Position()
    {
        // WPF dimensions are DIPs. Full screen bounds, not WorkArea, keep the
        // island flush to the display edge even with a taskbar at the top.
        var source = PresentationSource.FromVisual(this); if (source?.CompositionTarget == null) return;
        var bounds = System.Windows.Forms.Screen.PrimaryScreen!.Bounds;
        var transform = source.CompositionTarget.TransformFromDevice;
        var top = transform.Transform(new Point(bounds.Left, bounds.Top)); var size = transform.Transform(new Point(bounds.Width, bounds.Height));
        Top = top.Y; Left = top.X + (size.X - ActualWidth) / 2;
    }
    public void Compact() { Expanded = false; showingResult = false; Refresh(); }
    public void ShowResult() { showingResult = true; Refresh(); }
    public void Refresh()
    {
        if (!IsInitialized) return;
        ExpandedControls.Visibility = Expanded ? Visibility.Visible : Visibility.Collapsed;
        LanguagesRow.Visibility = Expanded && controller.ActiveTool == Tool.Translate ? Visibility.Visible : Visibility.Collapsed;
        var hasResult = showingResult && controller.Result.Length > 0 || controller.Error.Length > 0;
        ResultBody.Visibility = hasResult ? Visibility.Visible : Visibility.Collapsed;
        ResultScroll.MaxHeight = Expanded ? 235 : 155;
        ActivityLabel.Text = controller.Busy ? "Working…" : controller.ActiveTool.ToString();
        ResultText.Inlines.Clear();
        if (controller.ActiveTool == Tool.Format)
            foreach (var run in Formatter.Runs(controller.Input)) ResultText.Inlines.Add(new Run(run.Text) { Foreground = run.Changed ? (Brush)FindResource("Orange") : Brushes.White });
        else ResultText.Inlines.Add(new Run(controller.Result) { Foreground = (Brush)FindResource("Orange") });
        foreach (var button in new[] { FormatTab, TranslateTab, IzohchiTab, DocumentTab })
        {
            var active = button.Tag?.ToString() == controller.ActiveTool.ToString();
            button.Background = active ? (Brush)FindResource("Green") : new SolidColorBrush(Color.FromRgb(32, 34, 32)); button.Foreground = active ? Brushes.Black : Brushes.White;
        }
        Waveform.BeginAnimation(OpacityProperty, null);
        if (controller.Busy && SystemParameters.ClientAreaAnimation && System.Windows.Forms.SystemInformation.PowerStatus.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Online)
            Waveform.BeginAnimation(OpacityProperty, new DoubleAnimation(0.25, 1, TimeSpan.FromMilliseconds(550)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        else Waveform.Opacity = controller.Busy ? 0.85 : 0.5;
        var width = Expanded ? 440 : hasResult ? 340 : 318;
        ResultBody.Measure(new Size(width - 32, double.PositiveInfinity));
        var height = 36 + (Expanded ? controller.ActiveTool == Tool.Translate ? 97 : 58 : 0) + (hasResult ? ResultBody.DesiredSize.Height + 20 : 0);
        Animate(WidthProperty, width); Animate(HeightProperty, Math.Min(Expanded ? 420 : 270, height));
    }
    private void Animate(DependencyProperty property, double target)
    {
        var current = (double)GetValue(property); var duration = SystemParameters.ClientAreaAnimation ? 280 : 0;
        BeginAnimation(property, new DoubleAnimation(current, target, TimeSpan.FromMilliseconds(duration)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }, FillBehavior = FillBehavior.HoldEnd });
    }
    private void HoverEnter(object sender, System.Windows.Input.MouseEventArgs e) { hoverDelay.Stop(); Expanded = true; Refresh(); }
    private void HoverLeave(object sender, System.Windows.Input.MouseEventArgs e) => hoverDelay.Start();
    private void ToolClick(object sender, RoutedEventArgs e) { if (sender is Button { Tag: string name } && Enum.TryParse<Tool>(name, out var tool)) controller.SelectTool(tool); }
    private void ApplyClick(object sender, RoutedEventArgs e) => _ = controller.Apply();
    private void CopyClick(object sender, RoutedEventArgs e) => controller.Copy();
    private void MoreClick(object sender, RoutedEventArgs e) => controller.More();
}
