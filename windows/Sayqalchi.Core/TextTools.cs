using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Sayqalchi.Core;

public record TextRun(string Text, bool Changed);
public static class Formatter
{
    private const string Marks = "'‘’ʻʼ`ʹ´＇";
    private static readonly Regex Protected = new(@"(?:https?://|www\.)\S+|[\p{L}\d._%+\-]+@[\p{L}\d.\-]+\.[\p{L}]{2,}|\b[\p{L}\d\-]+(?:\.[\p{L}\d\-]+)+\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    public static string Convert(string text) => string.Concat(Runs(text).Select(x => x.Text));
    public static IReadOnlyList<TextRun> Runs(string text)
    {
        var source = text.Normalize(); var runs = new List<TextRun>(); var cursor = 0;
        var pending = new StringBuilder(); var pendingChanged = false;
        void Add(string value, bool changed)
        {
            if (value.Length == 0) return;
            if (pending.Length > 0 && pendingChanged != changed) { runs.Add(new(pending.ToString(), pendingChanged)); pending.Clear(); }
            pendingChanged = changed; pending.Append(value);
        }
        void Letters(string part)
        {
            var items = new List<string>(); var elements = StringInfo.GetTextElementEnumerator(part);
            while (elements.MoveNext()) items.Add(elements.GetTextElement());
            for (var i = 0; i < items.Count; i++)
            {
                var c = items[i]; var low = c.ToLowerInvariant();
                if (i + 1 < items.Count)
                {
                    var next = items[i + 1]; var pair = low + next.ToLowerInvariant();
                    string? mapped = (low is "o" or "g") && Marks.Contains(next, StringComparison.Ordinal) ? low == "o" ? "ö" : "ğ" : pair == "sh" ? "ş" : pair == "ch" ? "ç" : null;
                    if (mapped != null) { Add(char.IsUpper(c, 0) ? mapped.ToUpperInvariant() : mapped, true); i++; continue; }
                }
                if (Marks.Contains(c, StringComparison.Ordinal) && i > 0 && i + 1 < items.Count && char.IsLetter(items[i - 1], 0) && char.IsLetter(items[i + 1], 0)) Add("’", c != "’");
                else Add(c, false);
            }
        }
        foreach (Match match in Protected.Matches(source)) { Letters(source[cursor..match.Index]); Add(match.Value, false); cursor = match.Index + match.Length; }
        Letters(source[cursor..]); if (pending.Length > 0) runs.Add(new(pending.ToString(), pendingChanged)); return runs;
    }
}

public enum Tool { Format, Translate, Izohchi, Document }
public sealed record Language(string Code, string Label)
{
    public static readonly Language[] All = [new("uz-Latn", "O‘zbek"), new("en", "English"), new("ru", "Русский"), new("uz-Cyrl", "Ўзбек")];
}
public static class Directions
{
    public static bool Supported(string source, string target) => source != target &&
        ((source == "uz-Latn" && target is "en" or "ru" or "uz-Cyrl") || (target == "uz-Latn" && source is "en" or "ru" or "uz-Cyrl"));
}
public static class DocumentTools
{
    public static string Clean(string text) => Regex.Replace(Regex.Replace(text, @"(?<=\S)[ \t]{2,}(?=\S)", " "), @"[ \t]+(?=\r?$)", "", RegexOptions.Multiline);
    public static string Summary(string text)
    {
        var words = Regex.Matches(text, @"\S+").Count(m => m.Value.Any(char.IsLetterOrDigit));
        var paragraphs = Regex.Split(text, @"\r\n|\r|\n").Count(p => !string.IsNullOrWhiteSpace(p));
        return $"{words:N0} words · {StringInfo.ParseCombiningCharacters(text).Length:N0} characters · {paragraphs} paragraphs · {Math.Max(1, (int)Math.Ceiling(words / 200.0))} min read";
    }
}
public sealed class DoubleRightShift
{
    private bool down, used; private long? last;
    public bool Handle(bool pressed, long milliseconds, bool otherModifiers)
    {
        if (pressed) { if (down) return false; down = true; used = otherModifiers; return false; }
        if (!down) return false;
        down = false;
        if (used || otherModifiers) { last = null; return false; }
        var toggle = last.HasValue && milliseconds - last.Value is >= 0 and <= 420;
        last = toggle ? null : milliseconds; return toggle;
    }
    public void OtherKey() { used = true; last = null; }
}
