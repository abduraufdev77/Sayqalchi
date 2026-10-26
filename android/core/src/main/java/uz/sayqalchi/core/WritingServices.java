package uz.sayqalchi.core;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CancellationException;
import java.util.regex.*;
import org.json.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;

public final class WritingServices {
 public static final class Cancel {
  private volatile boolean cancelled; private volatile HttpURLConnection connection;
  public void cancel(){cancelled=true;HttpURLConnection c=connection;if(c!=null)c.disconnect();}
  public void check(){if(cancelled||Thread.currentThread().isInterrupted())throw new CancellationException();}
  void attach(HttpURLConnection c){connection=c;check();}
 }
 public static final class Options {
  public final boolean custom,allowHttp;public final String url,key;
  public Options(boolean custom,String url,String key,boolean allowHttp){this.custom=custom;this.url=url;this.key=key;this.allowHttp=allowHttp;}
  public static Options publicProvider(){return new Options(false,"","",false);}
 }
 public static final class Segment { public final String text;public final boolean translate;Segment(String text,boolean translate){this.text=text;this.translate=translate;} }
 public static final class Meaning { public final String definition,example;Meaning(String definition,String example){this.definition=definition;this.example=example;} }
 public static final class Entry {
  public final String word,source;public final List<Meaning> meanings;
  Entry(String word,String source,List<Meaning> meanings){this.word=word;this.source=source;this.meanings=meanings;}
  public String render(boolean detailed){StringBuilder text=new StringBuilder(word);int count=detailed?meanings.size():Math.min(2,meanings.size());for(int i=0;i<count;i++){Meaning m=meanings.get(i);text.append("\n\n").append(i+1).append(". ").append(m.definition);if(!m.example.isEmpty())text.append("\n").append(m.example);}return text.toString();}
 }
 public interface Transport {String request(String method,URI url,Map<String,String> headers,String body,Cancel cancel)throws Exception;}
 private final Transport transport;
 public WritingServices(){this(new NetworkTransport());}
 public WritingServices(Transport transport){this.transport=transport;}
 public static List<Segment> segments(String text){
  if(text.trim().isEmpty())throw new IllegalArgumentException("Open a draft or enter text first.");
  if(text.codePointCount(0,text.length())>5000)throw new IllegalArgumentException("MyMemory allows 5,000 characters per day. Nothing was truncated.");
  List<Segment> output=new ArrayList<>();Matcher lines=Pattern.compile("[^\\r\\n]+|[\\r\\n]+").matcher(text);
  while(lines.find()){String remaining=lines.group();while(!remaining.isEmpty()){
   int whitespace=0;while(whitespace<remaining.length()&&Character.isWhitespace(remaining.charAt(whitespace)))whitespace++;
   if(whitespace>0){output.add(new Segment(remaining.substring(0,whitespace),false));remaining=remaining.substring(whitespace);continue;}
   int bodyEnd=remaining.length();while(bodyEnd>0&&Character.isWhitespace(remaining.charAt(bodyEnd-1)))bodyEnd--;
   int end=0,bytes=0;while(end<bodyEnd){int code=remaining.codePointAt(end),length=Character.charCount(code),count=remaining.substring(end,end+length).getBytes(StandardCharsets.UTF_8).length;if(bytes+count>500)break;bytes+=count;end+=length;}
   if(end==0)throw new IllegalArgumentException("The text exceeds this provider’s request limit.");
   if(end<bodyEnd){int space=remaining.substring(0,end).lastIndexOf(' ');if(space>0)end=space;}
   output.add(new Segment(remaining.substring(0,end),true));remaining=remaining.substring(end);
  }}return output;
 }
 private static String encode(String value){try{return URLEncoder.encode(value,"UTF-8");}catch(UnsupportedEncodingException impossible){throw new AssertionError(impossible);}}
 public static URI endpoint(Options options){
  try{URI uri=new URI(options.url.trim());String scheme=uri.getScheme();if(!("https".equals(scheme)||options.allowHttp&&"http".equals(scheme))||uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null||options.key.trim().isEmpty())throw new IllegalArgumentException();
   return uri.getPath().replaceAll("/+$","").endsWith("api/translate/text")?uri:new URI(uri.toString().replaceAll("/+$","")+"/api/translate/text");
  }catch(Exception error){throw new IllegalArgumentException("Set a valid HTTPS service URL and API key in Settings.");}
 }
 public String translate(String text,String source,String target,Options options,Cancel cancel)throws Exception{
  if(!TextTools.supported(source,target))throw new IllegalArgumentException("Choose Uzbek ↔ English, Russian or Cyrillic.");
  if(text.trim().isEmpty())throw new IllegalArgumentException("Open a draft or enter text first.");cancel.check();
  if(source.equals("uz-Cyrl")||target.equals("uz-Cyrl"))return UzbekScript.convert(text,target.equals("uz-Cyrl"));
  if(options.custom){if(text.codePointCount(0,text.length())>20000)throw new IllegalArgumentException("Translate up to 20,000 characters. Nothing was truncated.");
   JSONObject body=new JSONObject();body.put("sourceLanguage",source);body.put("targetLanguage",target);body.put("text",text);
   Map<String,String> headers=new HashMap<>();headers.put("X-API-Token",options.key);headers.put("Content-Type","application/json");headers.put("Accept","application/x-ndjson");
   return parseStream(transport.request("POST",endpoint(options),headers,body.toString(),cancel));
  }
  StringBuilder result=new StringBuilder();String pair=(source.equals("uz-Latn")?"uz":source)+"|"+(target.equals("uz-Latn")?"uz":target);
  for(Segment segment:segments(text)){cancel.check();if(!segment.translate){result.append(segment.text);continue;}
   URI url=URI.create("https://api.mymemory.translated.net/get?q="+encode(segment.text)+"&langpair="+encode(pair)+"&mt=1");
   result.append(parsePublic(transport.request("GET",url,Collections.singletonMap("Accept","application/json"),null,cancel)));
  }return result.toString();
 }
 public static String parsePublic(String raw)throws JSONException{
  JSONObject data=new JSONObject(raw);String status=data.optString("responseStatus");if(data.optBoolean("quotaFinished",false)||status.equals("403")||status.equals("429"))throw new IllegalArgumentException("MyMemory’s daily quota is used up. Try tomorrow or select your custom service.");
  JSONObject response=data.optJSONObject("responseData");String output=response==null?"":response.optString("translatedText","");
  if(!status.equals("200")||output.trim().isEmpty())throw new IllegalArgumentException("The provider returned no translation.");return org.jsoup.parser.Parser.unescapeEntities(output,false);
 }
 public static String parseStream(String raw)throws JSONException{
  StringBuilder output=new StringBuilder();boolean done=false;
  for(String line:raw.split("\n")){if(line.trim().isEmpty())continue;if(done)throw new IllegalArgumentException("Invalid translation stream.");JSONObject event=new JSONObject(line);if(event.has("error"))throw new IllegalArgumentException("The service could not complete this translation.");if(event.has("delta"))output.append(event.getString("delta"));if(event.optBoolean("done",false))done=true;}
  if(!done||output.toString().trim().isEmpty())throw new IllegalArgumentException("Translation was incomplete. Try again.");return output.toString();
 }
 public Entry lookup(String query,Cancel cancel)throws Exception{
  if(query.trim().isEmpty()||query.length()>120)throw new IllegalArgumentException("Select a word or short phrase.");
  URI url=URI.create("https://izoh.uz/word/"+encode(query).replace("+","%20"));return parseEntry(transport.request("GET",url,Collections.singletonMap("Accept","text/html"),null,cancel),url.toString());
 }
 public static Entry parseEntry(String html,String source){
  org.jsoup.nodes.Document doc=Jsoup.parse(html);Element title=doc.selectFirst("h1[itemprop=name]");List<Meaning> meanings=new ArrayList<>();
  if(title!=null)for(Element block:doc.select("div[id^=def-]"))for(Element p:block.children())if(p.tagName().equals("p")&&p.hasClass("font-bold")){
   String definition=p.text().replaceFirst("^\\d+\\.\\s*","");Element next=p.nextElementSibling();Element example=next!=null&&next.tagName().equals("ol")?next.selectFirst("li"):null;
   if(!definition.isEmpty())meanings.add(new Meaning(definition,example==null?"":example.text()));
  }
  if(title==null||meanings.isEmpty())throw new IllegalArgumentException("No definition found. Try the dictionary form of the word.");return new Entry(title.text(),source,meanings);
 }
 private static final class NetworkTransport implements Transport {
  public String request(String method,URI url,Map<String,String> headers,String body,Cancel cancel)throws Exception{
   cancel.check();HttpURLConnection connection=(HttpURLConnection)url.toURL().openConnection();connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(12000);connection.setReadTimeout(20000);connection.setRequestMethod(method);connection.setUseCaches(false);cancel.attach(connection);
   try{for(Map.Entry<String,String> header:headers.entrySet())connection.setRequestProperty(header.getKey(),header.getValue());
    if(body!=null){connection.setDoOutput(true);try(OutputStream output=connection.getOutputStream()){output.write(body.getBytes(StandardCharsets.UTF_8));}}
    int status=connection.getResponseCode();if(status!=200)throw new IllegalArgumentException(status==429?"The provider’s quota is used up. Try later.":status==401||status==403?"The provider rejected the request. Check its settings.":status==404?"No definition found.":"The source is unavailable. Try again.");
    try(InputStream input=connection.getInputStream();ByteArrayOutputStream output=new ByteArrayOutputStream()){
     byte[] bytes=new byte[8192];int count;while((count=input.read(bytes))!=-1){cancel.check();if(output.size()+count>2000000)throw new IllegalArgumentException("The response is too large.");output.write(bytes,0,count);}return output.toString("UTF-8");
    }
   }finally{connection.disconnect();}
  }
 }
}
