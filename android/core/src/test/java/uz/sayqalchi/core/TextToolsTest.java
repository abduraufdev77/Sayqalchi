package uz.sayqalchi.core;
import org.junit.Test;
import static org.junit.Assert.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.net.URI;
import java.util.*;
import org.json.*;

public class TextToolsTest {
 @Test public void sharedDesktopAlphabet()throws Exception{
  JSONArray fixtures=new JSONArray(Files.readString(Path.of(System.getProperty("sayqalchi.fixtures"))));for(int i=0;i<fixtures.length();i++){JSONObject fixture=fixtures.getJSONObject(i);String expected=fixture.getString("expected");assertEquals(expected,TextTools.format(fixture.getString("input")));assertEquals(expected,TextTools.format(expected));}
 }
 @Test public void wholeDraftAndStaleProtection(){assertEquals("Özbekça\n\nŞahar 👋",TextTools.format("O'zbekcha\n\nShahar 👋"));assertTrue(TextTools.sameDraft("one","one",1,1,"app","app",true,false));assertFalse(TextTools.sameDraft("old","new",1,1,"app","app",true,false));assertFalse(TextTools.sameDraft("one","one",1,2,"app","app",true,false));assertFalse(TextTools.sameDraft("one","one",1,1,"app","app",true,true));}
 @Test public void scriptsAndLinks(){assertEquals("Ўзбекистон шаҳар https://shahar.uz",UzbekScript.convert("O‘zbekiston shahar https://shahar.uz",true));assertEquals("O‘zbekiston SHAHAR",UzbekScript.convert("Ўзбекистон ШАҲАР",false));}
 @Test public void publicSegmentsPreserveUnicodeAndParagraphs(){String text="a".repeat(501)+"  ö🙂\r\n\n  salom  ";StringBuilder joined=new StringBuilder();for(WritingServices.Segment s:WritingServices.segments(text)){joined.append(s.text);if(s.translate){assertTrue(s.text.getBytes(StandardCharsets.UTF_8).length<=500);assertFalse(s.text.contains("\n"));}}assertEquals(text,joined.toString());}
 @Test public void providerNeverGetsCustomCredential()throws Exception{
  List<Map<String,String>> requests=new ArrayList<>();WritingServices services=new WritingServices((method,url,headers,body,cancel)->{requests.add(headers);return "{\"responseStatus\":200,\"responseData\":{\"translatedText\":\"hello\"}}";});
  assertEquals("hello\n\nhello",services.translate("salom\n\nsalom","uz-Latn","en",new WritingServices.Options(false,"https://fixture.example","fixture-only",false),new WritingServices.Cancel()));assertEquals(2,requests.size());assertFalse(requests.get(0).containsKey("X-API-Token"));
  assertEquals("шаҳар",services.translate("shahar","uz-Latn","uz-Cyrl",WritingServices.Options.publicProvider(),new WritingServices.Cancel()));assertEquals(2,requests.size());
 }
 @Test public void dictionaryLimitsAndCursor(){assertEquals("shahar",TextTools.dictionaryQuery("A shahar after",4,4));WritingServices.Entry entry=WritingServices.parseEntry("<h1 itemprop='name'>jamoa</h1><div id='def-a'><p class='font-bold'>1. Group.</p><ol><li>First example</li><li>Extra</li></ol><p class='font-bold'>People.</p><p class='font-bold'>Community.</p></div>","https://izoh.uz/word/jamoa");assertEquals(3,entry.meanings.size());assertFalse(entry.render(false).contains("Community"));assertFalse(entry.render(false).contains("Extra"));}
 @Test public void completeStreamsOnly()throws Exception{assertEquals("Done",WritingServices.parseStream("{\"delta\":\"Done\"}\n{\"done\":true}\n"));assertThrows(IllegalArgumentException.class,()->WritingServices.parseStream("{\"delta\":\"partial\"}"));assertThrows(IllegalArgumentException.class,()->WritingServices.parsePublic("{\"responseStatus\":403,\"quotaFinished\":true}"));}
 @Test public void urlAndSizeValidation(){assertThrows(IllegalArgumentException.class,()->WritingServices.endpoint(new WritingServices.Options(true,"http://fixture.example","fixture-only",false)));assertThrows(IllegalArgumentException.class,()->WritingServices.endpoint(new WritingServices.Options(true,"https://user:pass@fixture.example","fixture-only",false)));assertEquals("/api/translate/text",WritingServices.endpoint(new WritingServices.Options(true,"https://fixture.example","fixture-only",false)).getPath());assertThrows(IllegalArgumentException.class,()->WritingServices.segments("a".repeat(5001)));}
 @Test public void cancelledRequestsCannotRun(){WritingServices.Cancel cancel=new WritingServices.Cancel();cancel.cancel();assertThrows(java.util.concurrent.CancellationException.class,cancel::check);}
}
