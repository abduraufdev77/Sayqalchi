using System.Collections.Concurrent;
using System.Diagnostics;
using System.Windows.Automation;
using Sayqalchi.Core;

namespace Sayqalchi.Windows;
internal sealed record Draft(AutomationElement Element, int[] RuntimeId, uint ProcessId, nint Window, string Text, string Selection, string App);
internal sealed class AutomationWorker : IDisposable
{
    private readonly BlockingCollection<Action> queue = new(8);
    private readonly Thread thread;
    internal AutomationWorker()
    {
        thread = new Thread(() => { foreach (var action in queue.GetConsumingEnumerable()) action(); }) { IsBackground = true, Name = "Sayqalchi UI Automation" };
        thread.SetApartmentState(ApartmentState.MTA); thread.Start();
    }
    internal Task<T> Run<T>(Func<T> action)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!queue.TryAdd(() => { try { completion.SetResult(action()); } catch (Exception e) { completion.SetException(e); } })) completion.SetException(new InvalidOperationException("The editor is busy. Try again."));
        return completion.Task;
    }
    public void Dispose() { queue.CompleteAdding(); }
}
internal static class EditorAccess
{
    internal const int Maximum = 200_000;
    private static readonly string[] Protected = ["windowsterminal", "powershell", "pwsh", "cmd", "conhost", "credentialuibroker", "consent", "keepass", "1password", "bitwarden", "lastpass"];
    internal static Draft? Capture(string[] excluded, bool allowOwn = false)
    {
        var window = Native.GetForegroundWindow(); Native.GetWindowThreadProcessId(window, out var pid);
        if (pid == 0 || !allowOwn && pid == Environment.ProcessId) return null;
        using var process = Process.GetProcessById((int)pid); var app = process.ProcessName;
        if (Protected.Concat(excluded).Any(x => app.Equals(x.Trim().Replace(".exe", "", StringComparison.OrdinalIgnoreCase), StringComparison.OrdinalIgnoreCase))) return null;
        var element = AutomationElement.FocusedElement;
        if (element == null || element.Current.ProcessId != pid || element.Current.IsPassword || !element.Current.IsEnabled || !element.Current.IsKeyboardFocusable) return null;
        if (element.Current.ControlType != ControlType.Edit && element.Current.ControlType != ControlType.Document) return null;
        var text = EditableText(element);
        if (text == null || text.Length > Maximum || string.IsNullOrWhiteSpace(text)) return null;
        var selection = "";
        if (element.TryGetCurrentPattern(TextPattern.Pattern, out var pattern))
        {
            var ranges = ((TextPattern)pattern).GetSelection();
            if (ranges.Length == 1) selection = ranges[0].GetText(Maximum + 1);
        }
        return new(element, element.GetRuntimeId(), pid, window, text, selection, app);
    }
    private static string? EditableText(AutomationElement element)
    {
        if (element.Current.IsPassword) return null;
        // ValuePattern permits verified, atomic replacement without clipboard
        // injection or selecting unrelated document/history content.
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var value) && !((ValuePattern)value).Current.IsReadOnly) return ((ValuePattern)value).Current.Value;
        return null;
    }
    internal static bool Apply(Draft draft, string replacement, string[] excluded, bool allowOwn = false)
    {
        var current = Capture(excluded, allowOwn);
        if (current == null || current.ProcessId != draft.ProcessId || current.Window != draft.Window || !current.RuntimeId.SequenceEqual(draft.RuntimeId) || current.Text != draft.Text) return false;
        if (!current.Element.TryGetCurrentPattern(ValuePattern.Pattern, out var value) || ((ValuePattern)value).Current.IsReadOnly) return false;
        ((ValuePattern)value).SetValue(replacement);
        return EditableText(current.Element) == replacement;
    }
}
