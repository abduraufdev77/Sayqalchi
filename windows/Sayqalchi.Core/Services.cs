using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using HtmlAgilityPack;

namespace Sayqalchi.Core;

public sealed record ServiceOptions(bool Custom = false, string Url = "", string Token = "", bool AllowHttp = false);
public sealed record Meaning(string Definition, string? Example);
public sealed record Entry(string Word, IReadOnlyList<Meaning> Meanings, Uri Source)
{
    public string Render(bool details) => Word + "\n\n" + string.Join("\n\n", (details ? Meanings : Meanings.Take(2)).Select((m, i) => $"{i + 1}. {m.Definition}" + (m.Example is { Length: > 0 } ? "\n" + m.Example : "")));
}
public sealed class WritingServices(HttpClient client)
{
    public static IReadOnlyList<(string Text, bool Translate)> Segments(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("Open a draft or enter text first.");
        if (text.EnumerateRunes().Count() > 5000) throw new InvalidOperationException("MyMemory supports up to 5,000 characters per day. Nothing was truncated.");
        var segments = new List<(string, bool)>();
        foreach (Match line in Regex.Matches(text, @"[^\r\n]+|[\r\n]+"))
        {
            var remaining = line.Value;
            while (remaining.Length > 0)
            {
                var whitespace = new string(remaining.TakeWhile(char.IsWhiteSpace).ToArray());
                if (whitespace.Length > 0) { segments.Add((whitespace, false)); remaining = remaining[whitespace.Length..]; continue; }
                var body = remaining.TrimEnd(); var bytes = 0; var end = 0; var enumerator = StringInfo.GetTextElementEnumerator(body);
                while (enumerator.MoveNext())
                {
                    var element = enumerator.GetTextElement(); var count = Encoding.UTF8.GetByteCount(element);
                    if (bytes + count > 500) break;
                    bytes += count; end += element.Length;
                }
                if (end == 0) throw new InvalidOperationException("This character sequence exceeds the provider’s request limit.");
                if (end < body.Length) { var space = body[..end].LastIndexOfAny([' ', '\t']); if (space > 0) end = space; }
                segments.Add((body[..end], true)); remaining = remaining[end..];
            }
        }
        return segments;
    }
    public static Uri CustomEndpoint(ServiceOptions options)
    {
        if (!Uri.TryCreate(options.Url.Trim(), UriKind.Absolute, out var uri) || !(uri.Scheme == "https" || options.AllowHttp && uri.Scheme == "http") || string.IsNullOrEmpty(uri.Host) || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0 || string.IsNullOrWhiteSpace(options.Token))
            throw new InvalidOperationException("Set a valid HTTPS service URL and API key in Settings.");
        return uri.AbsolutePath.TrimEnd('/').EndsWith("api/translate/text", StringComparison.Ordinal) ? uri : new Uri(uri.AbsoluteUri.TrimEnd('/') + "/api/translate/text");
    }
    public async Task<string> Translate(string text, string source, string target, ServiceOptions options, CancellationToken token)
    {
        if (!Directions.Supported(source, target)) throw new InvalidOperationException("Choose Uzbek ↔ English, Russian or Cyrillic.");
        if (string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("Open a draft or enter text first.");
        if (source == "uz-Cyrl" || target == "uz-Cyrl") return UzbekScript.Convert(text, target == "uz-Cyrl");
        if (options.Custom)
        {
            if (text.EnumerateRunes().Count() > 20_000) throw new InvalidOperationException("Translate up to 20,000 characters at a time. Nothing was truncated.");
            using var request = new HttpRequestMessage(HttpMethod.Post, CustomEndpoint(options));
            request.Headers.Add("X-API-Token", options.Token); request.Headers.Accept.ParseAdd("application/x-ndjson");
            request.Content = JsonContent.Create(new { sourceLanguage = source, targetLanguage = target, text });
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            CheckStatus(response); var raw = await ReadBounded(response, token); return ParseStream(raw);
        }
        var result = new StringBuilder();
        foreach (var segment in Segments(text))
        {
            token.ThrowIfCancellationRequested();
            if (!segment.Translate) { result.Append(segment.Text); continue; }
            var pair = (source == "uz-Latn" ? "uz" : source) + "|" + (target == "uz-Latn" ? "uz" : target);
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.mymemory.translated.net/get?q=" + Uri.EscapeDataString(segment.Text) + "&langpair=" + Uri.EscapeDataString(pair) + "&mt=1");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            CheckStatus(response); result.Append(ParsePublic(await ReadBounded(response, token)));
        }
        return result.ToString();
    }
    public static string ParsePublic(string raw)
    {
        using var json = JsonDocument.Parse(raw); var root = json.RootElement;
        var status = root.TryGetProperty("responseStatus", out var s) ? s.ToString() : "";
        if (root.TryGetProperty("quotaFinished", out var quota) && quota.ValueKind == JsonValueKind.True || status is "429" or "403") throw new InvalidOperationException("MyMemory’s daily quota is used up. Try tomorrow or choose your custom service.");
        if (status != "200" || !root.TryGetProperty("responseData", out var data) || !data.TryGetProperty("translatedText", out var text) || string.IsNullOrWhiteSpace(text.GetString())) throw new InvalidOperationException("The provider returned no translation.");
        return WebUtility.HtmlDecode(text.GetString()!);
    }
    public static string ParseStream(string raw)
    {
        var output = new StringBuilder(); var done = false;
        foreach (var line in raw.Split('\n').Where(x => !string.IsNullOrWhiteSpace(x)))
        {
            if (done) throw new InvalidOperationException("The service returned an invalid stream.");
            using var json = JsonDocument.Parse(line); var data = json.RootElement;
            if (data.TryGetProperty("error", out _)) throw new InvalidOperationException("The service could not complete the translation.");
            if (data.TryGetProperty("delta", out var delta)) output.Append(delta.GetString());
            if (data.TryGetProperty("done", out var completion)) done = completion.ValueKind == JsonValueKind.True;
        }
        if (!done || string.IsNullOrWhiteSpace(output.ToString())) throw new InvalidOperationException("Translation was incomplete. Please try again.");
        return output.ToString();
    }
    public static string DictionaryQuery(string text, string? selection = null)
    {
        var query = string.IsNullOrWhiteSpace(selection) ? Regex.Matches(text, @"[\p{L}\p{M}]+(?:['‘’ʻʼ-][\p{L}\p{M}]+)*").LastOrDefault()?.Value ?? "" : selection.Trim();
        if (query.Length == 0 || query.Length > 120 || query.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length > 10) throw new InvalidOperationException("Select a word or short phrase to look up.");
        return query.ToLowerInvariant().Replace("ö", "o‘").Replace("ğ", "g‘").Replace("ş", "sh").Replace("ç", "ch");
    }
    public async Task<Entry> Lookup(string query, CancellationToken token)
    {
        var url = new Uri("https://izoh.uz/word/" + Uri.EscapeDataString(query));
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        CheckStatus(response); return ParseEntry(await ReadBounded(response, token), url);
    }
    public static Entry ParseEntry(string html, Uri source)
    {
        var doc = new HtmlDocument(); doc.LoadHtml(html);
        var word = doc.DocumentNode.SelectSingleNode("//h1[@itemprop='name']");
        var blocks = doc.DocumentNode.SelectNodes("//div[starts-with(@id,'def-')]/p[contains(concat(' ',normalize-space(@class),' '),' font-bold ')]");
        if (word == null || blocks == null) throw new InvalidOperationException("No definition found. Try the dictionary form of the word.");
        static string Text(HtmlNode node) => WebUtility.HtmlDecode(Regex.Replace(node.InnerText, @"\s+", " ")).Trim();
        var meanings = blocks.Select(p => {
            var next = p.NextSibling; while (next != null && next.NodeType != HtmlNodeType.Element) next = next.NextSibling;
            return new Meaning(Regex.Replace(Text(p), @"^\d+\.\s*", ""), next?.Name == "ol" && next.SelectSingleNode(".//li") is { } example ? Text(example) : null);
        }).Where(x => x.Definition.Length > 0).ToArray();
        if (meanings.Length == 0) throw new InvalidOperationException("No definition found.");
        return new(Text(word), meanings, source);
    }
    private static void CheckStatus(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden ? "The service rejected the request. Check your provider and API key." : response.StatusCode == HttpStatusCode.TooManyRequests ? "The provider’s quota is used up. Please try later." : "The source is unavailable. Please try again.");
    }
    private static async Task<string> ReadBounded(HttpResponseMessage response, CancellationToken token)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(token); using var data = new MemoryStream(); var buffer = new byte[8192];
        int count; while ((count = await stream.ReadAsync(buffer, token)) > 0) { if (data.Length + count > 2_000_000) throw new InvalidOperationException("The response is too large."); data.Write(buffer, 0, count); }
        return Encoding.UTF8.GetString(data.ToArray());
    }
}
