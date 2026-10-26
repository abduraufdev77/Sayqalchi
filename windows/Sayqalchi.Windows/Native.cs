using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Sayqalchi.Core;

namespace Sayqalchi.Windows;
internal static class Native
{
    internal delegate nint Hook(int code, nint wParam, nint lParam);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint pid);
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(nint hwnd);
    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] internal static extern nint SetWindowsHookEx(int id, Hook callback, nint module, uint thread);
    [DllImport("user32.dll")] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint wParam, nint lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern nint GetModuleHandle(string? name);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
    internal static void NoActivate(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        SetWindowLongPtr(handle, -20, GetWindowLongPtr(handle, -20) | 0x08000000 | 0x00000080);
    }
    [StructLayout(LayoutKind.Sequential)] internal struct KeyData { public uint Key, Scan, Flags, Time; public nuint Extra; }
    internal static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;
    internal static bool OwnForeground() { GetWindowThreadProcessId(GetForegroundWindow(), out var pid); return pid == Environment.ProcessId; }
}
internal sealed class KeyboardShortcut : IDisposable
{
    private readonly Native.Hook callback;
    private readonly nint hook;
    private readonly DoubleRightShift gesture = new();
    internal bool Connected => hook != 0;
    internal KeyboardShortcut(Action toggle, Action typing, Func<bool> accept, Action dismiss)
    {
        callback = (code, w, l) => {
            if (code < 0) return Native.CallNextHookEx(hook, code, w, l);
            var key = Marshal.PtrToStructure<Native.KeyData>(l);
            if ((key.Flags & 0x10) != 0) return Native.CallNextHookEx(hook, code, w, l);
            var down = w == 0x100 || w == 0x104;
            if (key.Key == 0xA1)
            {
                if (gesture.Handle(down, Environment.TickCount64, Native.Down(0xA0) || Native.Down(0x11) || Native.Down(0x12) || Native.Down(0x5B) || Native.Down(0x5C))) toggle();
            }
            else if (down)
            {
                gesture.OtherKey();
                if (key.Key == 13 && Native.Down(0x12) && !Native.Down(0x11) && !Native.Down(0x10) && accept()) return 1;
                if (key.Key == 27) dismiss();
                if (!Native.OwnForeground() && key.Key is not (0x10 or 0x11 or 0x12 or 0xA0 or 0xA2 or 0xA3 or 0xA4 or 0xA5 or 0x5B or 0x5C)) typing();
            }
            return Native.CallNextHookEx(hook, code, w, l);
        };
        hook = Native.SetWindowsHookEx(13, callback, Native.GetModuleHandle(null), 0);
    }
    public void Dispose() { if (hook != 0) Native.UnhookWindowsHookEx(hook); GC.KeepAlive(callback); }
}
