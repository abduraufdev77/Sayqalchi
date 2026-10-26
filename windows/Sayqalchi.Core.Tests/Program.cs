using System.Net;
using System.Text;
using System.Text.Json;
using Sayqalchi.Core;

var count = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); count++; }
void Reject(Action action, string name) { try { action(); } catch (InvalidOperationException) { count++; return; } throw new Exception(name); }
using (var fixtures = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "format-fixtures.json"))))
 foreach (var fixture in fixtures.RootElement.EnumerateArray()) {
  var input = fixture.GetProperty("input").GetString()!; var expected = fixture.GetProperty("expected").GetString()!;
  Check(Formatter.Convert(input) == expected, "Mac/Windows format parity");
  Check(Formatter.Convert(expected) == expected, "Idempotence");
 }
var text = new string('a', 501) + "  ö🙂\r\n\n  salom  ";
var segments = WritingServices.Segments(text);
Check(string.Concat(segments.Select(x => x.Text)) == text, "Segmentation preserves every character");
Check(segments.Where(x => x.Translate).All(x => Encoding.UTF8.GetByteCount(x.Text) <= 500 && !x.Text.Contains('\n')), "Provider UTF8 limits");
Reject(() => WritingServices.Segments(""), "Empty input");
Reject(() => WritingServices.Segments(new string('a', 5001)), "Never truncate public input");
Reject(() => WritingServices.CustomEndpoint(new(true, "http://example.test", "test-value")), "HTTPS required");
Reject(() => WritingServices.CustomEndpoint(new(true, "https://user:pass@example.test", "test-value")), "URL credentials rejected");
Check(WritingServices.CustomEndpoint(new(true, "https://example.test/base", "test-value")).AbsolutePath == "/base/api/translate/text", "Custom endpoint path");
Check(WritingServices.CustomEndpoint(new(true, "http://example.test:5177", "test-value", true)).Scheme == "http", "Explicit HTTP opt in");
Reject(() => WritingServices.ParseStream("{\"delta\":\"partial\"}"), "Partial translation never applied");
Check(WritingServices.ParseStream("{\"delta\":\"Done\"}\n{\"done\":true}\n") == "Done", "Completed stream");
Reject(() => WritingServices.ParsePublic("{\"responseStatus\":403,\"quotaFinished\":true}"), "Quota failure");
Check(WritingServices.ParsePublic("{\"responseStatus\":200,\"responseData\":{\"translatedText\":\"&lt;tag&gt;\"}}") == "<tag>", "Entities are text");
Check(UzbekScript.Convert("O‘zbekiston shahar", true) == "Ўзбекистон шаҳар", "Cyrillic");
Check(UzbekScript.Convert("Ўзбекистон ШАҲАР", false) == "O‘zbekiston SHAHAR", "Latin with case");
Check(UzbekScript.Convert("https://shahar.uz O‘zbekiston", true) == "https://shahar.uz Ўзбекистон", "Script URL protection");
Check(WritingServices.DictionaryQuery("Whole draft shahar\nmore", "şahar") == "shahar", "Explicit dictionary selection");
var entry = WritingServices.ParseEntry("<h1 itemprop='name'>jamoa</h1><div id='def-a'><p class='font-bold'>1. Group.</p><ol><li>One example.</li><li>Not in preview.</li></ol><p class='font-bold'>2. People.</p><p class='font-bold'>3. Community.</p></div>", new("https://izoh.uz/word/jamoa"));
Check(entry.Meanings.Count == 3 && !entry.Render(false).Contains("Community") && !entry.Render(false).Contains("Not in preview"), "Two meanings and one example");
var gesture = new DoubleRightShift();
Check(!gesture.Handle(true, 0, false) && !gesture.Handle(false, 50, false) && !gesture.Handle(true, 100, false) && gesture.Handle(false, 150, false), "Double right shift");
gesture.Handle(true, 200, false); gesture.OtherKey(); gesture.Handle(false, 210, false); gesture.Handle(true, 220, false);
Check(!gesture.Handle(false, 240, false), "Shift typing never toggles");
var handler = new FixtureHandler(); using var http = new HttpClient(handler); var services = new WritingServices(http);
Check(await services.Translate("salom\n\nsalom", "uz-Latn", "en", new(), default) == "hello\n\nhello", "Whole paragraph translation");
Check(handler.Requests == 2 && !handler.SawPrivateHeader, "Public provider carries no credential");
var before = handler.Requests;
Check(await services.Translate("shahar", "uz-Latn", "uz-Cyrl", new(), default) == "шаҳар" && handler.Requests == before, "Script conversion stays offline");
Console.WriteLine($"Passed {count} core checks.");
sealed class FixtureHandler : HttpMessageHandler
{
 public int Requests; public bool SawPrivateHeader;
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
  Requests++; SawPrivateHeader |= request.Headers.Contains("X-API-Token");
  return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"responseStatus\":200,\"responseData\":{\"translatedText\":\"hello\"}}") });
 }
}
