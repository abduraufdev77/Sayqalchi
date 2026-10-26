using System.Text;
using System.Text.RegularExpressions;
namespace Sayqalchi.Core;

public static class UzbekScript
{
    private static readonly Dictionary<string, string> Cyrillic = new()
    {
        ["ё"] = "yo",
        ["ю"] = "yu",
        ["я"] = "ya",
        ["щ"] = "shch",
        ["ў"] = "o‘",
        ["ғ"] = "g‘",
        ["ҳ"] = "h",
        ["қ"] = "q",
        ["ц"] = "ts",
        ["ч"] = "ch",
        ["ш"] = "sh",
        ["а"] = "a",
        ["б"] = "b",
        ["в"] = "v",
        ["г"] = "g",
        ["д"] = "d",
        ["ж"] = "j",
        ["з"] = "z",
        ["и"] = "i",
        ["й"] = "y",
        ["к"] = "k",
        ["л"] = "l",
        ["м"] = "m",
        ["н"] = "n",
        ["о"] = "o",
        ["п"] = "p",
        ["р"] = "r",
        ["с"] = "s",
        ["т"] = "t",
        ["у"] = "u",
        ["ф"] = "f",
        ["х"] = "x",
        ["ъ"] = "’",
        ["ы"] = "i",
        ["ь"] = "",
        ["э"] = "e"
    };
    private static readonly (string From, string To)[] Latin =
    [
        ("tsiya", "ция"),
        ("sh", "ш"),
        ("ch", "ч"),
        ("yo", "ё"),
        ("yu", "ю"),
        ("ya", "я"),
        ("ye", "е"),
        ("o‘", "ў"),
        ("g‘", "ғ"),
        ("ö", "ў"),
        ("ğ", "ғ"),
        ("ş", "ш"),
        ("ç", "ч"),
        ("a", "а"),
        ("b", "б"),
        ("d", "д"),
        ("f", "ф"),
        ("g", "г"),
        ("h", "ҳ"),
        ("i", "и"),
        ("j", "ж"),
        ("k", "к"),
        ("l", "л"),
        ("m", "м"),
        ("n", "н"),
        ("o", "о"),
        ("p", "п"),
        ("q", "қ"),
        ("r", "р"),
        ("s", "с"),
        ("t", "т"),
        ("u", "у"),
        ("v", "в"),
        ("x", "х"),
        ("y", "й"),
        ("z", "з"),
        ("’", "ъ")
    ];
    public static string Convert(string text, bool toCyrillic) => Regex.Replace(text,
        @"https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.-]+|\b[\w-]+(?:\.[\w-]+)*\.(?:uz|com|org|net|edu|gov|ru|io|info|pdf|docx?|xlsx?)\b|[^\s]+",
        m => Regex.IsMatch(m.Value, @"^(?:https?://|www\.)|@|\.(?:uz|com|org|net|edu|gov|ru|io|info|pdf|docx?|xlsx?)\b", RegexOptions.IgnoreCase) ? m.Value : Map(m.Value, toCyrillic), RegexOptions.IgnoreCase);
    private static string Map(string input, bool toCyrillic)
    {
        var chars = input.ToCharArray();
        for (var i = 0; toCyrillic && i < chars.Length; i++)
            if ("'‘’ʻʼ`´′".Contains(chars[i])) chars[i] = i > 0 && "oOgG".Contains(chars[i - 1]) ? '‘' : '’';
        var source = new string(chars); var lower = source.ToLowerInvariant(); var output = new StringBuilder();
        for (var i = 0; i < source.Length; i++)
        {
            var initial = i == 0 || !char.IsLetter(source[i - 1]); var prev = i - 1;
            if (prev >= 0 && source[prev] == '‘') prev--;
            var before = prev >= 0 ? lower[prev] : '\0'; string? target = null; var length = 1;
            if (toCyrillic)
            {
                if (lower[i] == 'e') target = initial || "aeiou".Contains(before) ? "э" : "е";
                else if (initial && lower[i..].StartsWith("ts", StringComparison.Ordinal)) { target = "ц"; length = 2; }
                else foreach (var (from, to) in Latin) if (lower[i..].StartsWith(from, StringComparison.Ordinal)) { target = to; length = from.Length; break; }
            }
            else if (lower[i] == 'е') target = initial || "аеёиоуэюяў".Contains(before) ? "ye" : "e";
            else Cyrillic.TryGetValue(lower[i].ToString(), out target);
            if (target == null) { output.Append(source[i]); continue; }
            if (char.IsUpper(source[i]))
            {
                var start = i; var end = i + length;
                while (start > 0 && char.IsLetter(source[start - 1])) start--;
                while (end < source.Length && char.IsLetter(source[end])) end++;
                var letters = source[start..end].Where(char.IsLetter).ToArray();
                target = letters.Length > 1 && letters.All(char.IsUpper) ? target.ToUpperInvariant() : target.Length == 0 ? "" : char.ToUpperInvariant(target[0]) + target[1..];
            }
            output.Append(target); i += length - 1;
        }
        return output.ToString();
    }
}
