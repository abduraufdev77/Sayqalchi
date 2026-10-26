using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Sayqalchi.Core;
using Application = System.Windows.Application;
using TextBox = System.Windows.Controls.TextBox;

namespace Sayqalchi.Windows;
internal static class SmokeTest
{
    internal static async Task Run(Application app)
    {
        try
        {
            using var worker = new AutomationWorker();
            var original = "O'zbekcha yozish oson.\r\n\r\nG'oya va shahar.";
            var editor = new TextBox { Text = original, AcceptsReturn = true, Name = "FixtureEditor" };
            var window = new Window { Title = "Sayqalchi disposable test editor", Width = 500, Height = 300, Content = editor };
            window.Show(); window.Activate(); Native.SetForegroundWindow(new WindowInteropHelper(window).Handle); editor.Focus();
            await Task.Delay(500);
            var draft = await worker.Run(() => EditorAccess.Capture([], true)).WaitAsync(TimeSpan.FromSeconds(8));
            if (draft == null || draft.Text != original) throw new Exception("Whole editable draft was not captured.");
            var replaced = await worker.Run(() => EditorAccess.Apply(draft, Formatter.Convert(original), [], true)).WaitAsync(TimeSpan.FromSeconds(8));
            if (!replaced || editor.Text != Formatter.Convert(original)) throw new Exception("Whole-draft replacement failed.");
            if (editor.CaretIndex != editor.Text.Length || editor.SelectionLength != 0) throw new Exception("Replacement did not leave the caret ready to continue typing.");
            editor.Text = "A newer draft";
            if (await worker.Run(() => EditorAccess.Apply(draft, "Must not replace", [], true))) throw new Exception("Stale replacement was allowed.");
            var password = new PasswordBox { Password = "disposable-fixture-only" }; window.Content = password; password.Focus(); await Task.Delay(150);
            if (await worker.Run(() => EditorAccess.Capture([], true)) != null) throw new Exception("Password field was captured.");
            window.Close();
            using var controller = new Controller(app); controller.ShowMain();
            if (!controller.Enabled) controller.Toggle();
            controller.Input = original; await Task.Delay(900);
            if (controller.Result != Formatter.Convert(original)) throw new Exception("Playground pause did not prepare formatting.");
            // Allow the result's 280 ms transition to finish before rendering.
            await Task.Delay(400);
            Directory.CreateDirectory("smoke-output");
            var widget = app.Windows.OfType<WidgetWindow>().Single();
            File.WriteAllText("smoke-output/layout.txt", $"Result length: {controller.Result.Length}; busy: {controller.Busy}; widget: {widget.Width} x {widget.Height}; actual: {widget.ActualWidth} x {widget.ActualHeight}; body: {widget.ResultBody.Visibility}");
            if (widget.ActualHeight <= 36 || widget.ResultBody.Visibility != Visibility.Visible) throw new Exception("The automatic result did not expand the widget.");
            foreach (Window view in app.Windows)
            {
                if (!view.IsVisible || view.ActualWidth < 1 || view.ActualHeight < 1) continue;
                view.UpdateLayout(); var bitmap = new RenderTargetBitmap((int)view.ActualWidth, (int)view.ActualHeight, 96, 96, PixelFormats.Pbgra32); bitmap.Render(view);
                var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.Combine("smoke-output", view is WidgetWindow ? "windows-widget.png" : "windows-playground.png")); png.Save(file);
            }
            File.WriteAllText("smoke-output/result.txt", "Passed: whole-draft capture, replacement, stale-draft rejection, password exclusion, automatic playground formatting and WPF rendering.");
            app.Shutdown(0);
        }
        catch (Exception error)
        {
            Directory.CreateDirectory("smoke-output"); File.WriteAllText("smoke-output/failure.txt", error.ToString()); app.Shutdown(1);
        }
    }
}
