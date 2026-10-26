using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sayqalchi.Core;

namespace Sayqalchi.Windows;
public sealed class Settings
{
    public bool Enabled { get; set; }
    public Tool DefaultTool { get; set; } = Tool.Format;
    public string Source { get; set; } = "uz-Latn";
    public string Target { get; set; } = "en";
    public bool CustomProvider { get; set; }
    public string ServiceUrl { get; set; } = "";
    public bool AllowHttp { get; set; }
    public string[] ExcludedProcesses { get; set; } = [];
    private static string DirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sayqalchi");
    private static string FilePath => Path.Combine(DirectoryPath, "settings.json");
    public static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(DirectoryPath); var temp = FilePath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this)); File.Move(temp, FilePath, true);
    }
    public string ReadToken()
    {
        try { return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(Path.Combine(DirectoryPath, "credential.bin")), null, DataProtectionScope.CurrentUser)); }
        catch (Exception e) when (e is IOException or CryptographicException or UnauthorizedAccessException) { return ""; }
    }
    public void SaveToken(string value)
    {
        Directory.CreateDirectory(DirectoryPath); var path = Path.Combine(DirectoryPath, "credential.bin");
        if (string.IsNullOrWhiteSpace(value)) { if (File.Exists(path)) File.Delete(path); return; }
        var temp = path + ".tmp"; File.WriteAllBytes(temp, ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser)); File.Move(temp, path, true);
    }
    public ServiceOptions ServiceOptions() => new(CustomProvider, ServiceUrl, CustomProvider ? ReadToken() : "", AllowHttp);
}
