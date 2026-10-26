package uz.sayqalchi.core;
import java.text.Normalizer;
import java.util.*;
import java.util.regex.*;

public final class TextTools {
 public enum Tool { FORMAT, TRANSLATE, IZOHCHI, DOCUMENT;
  public String label() { return new String[]{"Format","Translate","Izohchi","Document"}[ordinal()]; }
 }
 public static final class Run { public final String text; public final boolean changed; public Run(String text,boolean changed){this.text=text;this.changed=changed;} }
 private static final String MARKS="'‘’ʻʼ`ʹ´＇";
 private static final Pattern PROTECTED=Pattern.compile("(?:https?://|www\\.)\\S+|[\\p{L}\\d._%+\\-]+@[\\p{L}\\d.\\-]+\\.[\\p{L}]{2,}|\\b[\\p{L}\\d\\-]+(?:\\.[\\p{L}\\d\\-]+)+\\b",Pattern.CASE_INSENSITIVE);
 public static String format(String input){StringBuilder result=new StringBuilder();for(Run run:runs(input))result.append(run.text);return result.toString();}
 public static List<Run> runs(String input){
  String source=Normalizer.normalize(input,Normalizer.Form.NFC); List<Run> output=new ArrayList<>(); Matcher matches=PROTECTED.matcher(source); int cursor=0;
  while(matches.find()){letters(source.substring(cursor,matches.start()),output);add(output,matches.group(),false);cursor=matches.end();}
  letters(source.substring(cursor),output); return output;
 }
 private static void add(List<Run> output,String text,boolean changed){ if(!text.isEmpty())output.add(new Run(text,changed)); }
 private static void letters(String source,List<Run> out){
  StringBuilder pending=new StringBuilder();boolean pendingChanged=false;
  for(int i=0;i<source.length();){
   int code=source.codePointAt(i),size=Character.charCount(code);String current=new String(Character.toChars(code)),mapped=null;int consume=size;
   int next=i+size<source.length()?source.codePointAt(i+size):-1;int low=Character.toLowerCase(code);
   if(next!=-1){if((low=='o'||low=='g')&&MARKS.indexOf(next)>=0)mapped=low=='o'?"ö":"ğ";else if(low=='s'&&Character.toLowerCase(next)=='h')mapped="ş";else if(low=='c'&&Character.toLowerCase(next)=='h')mapped="ç";
    if(mapped!=null){consume+=Character.charCount(next);if(Character.isUpperCase(code))mapped=mapped.toUpperCase(Locale.ROOT);}
   }
   if(mapped==null&&MARKS.indexOf(code)>=0&&i>0&&next!=-1&&Character.isLetter(source.codePointBefore(i))&&Character.isLetter(next))mapped="’";
   String value=mapped==null?current:mapped;boolean changed=!value.equals(current);
   if(consume>size)changed=true;
   if(pending.length()>0&&changed!=pendingChanged){add(out,pending.toString(),pendingChanged);pending.setLength(0);}
   pendingChanged=changed;pending.append(value);i+=consume;
  }
  add(out,pending.toString(),pendingChanged);
 }
 public static String clean(String text){return text.replaceAll("(?<=\\S)[ \\t]{2,}(?=\\S)"," ").replaceAll("(?m)[ \\t]+(?=\\r?$)","");}
 public static String statistics(String text){int words=0,paragraphs=0;for(String word:text.split("\\s+"))if(word.codePoints().anyMatch(Character::isLetterOrDigit))words++;for(String line:text.split("\\r\\n|\\r|\\n"))if(!line.trim().isEmpty())paragraphs++;return words+" words · "+text.codePointCount(0,text.length())+" characters · "+paragraphs+" paragraphs · "+Math.max(1,(int)Math.ceil(words/200.0))+" min read";}
 public static boolean supported(String source,String target){return !source.equals(target)&&((source.equals("uz-Latn")&&Arrays.asList("en","ru","uz-Cyrl").contains(target))||(target.equals("uz-Latn")&&Arrays.asList("en","ru","uz-Cyrl").contains(source)));}
 public static String dictionaryQuery(String text,int start,int end){
  String value="";
  if(start>=0&&end>start&&end<=text.length())value=text.substring(start,end).trim();
  else {int caret=start<0?text.length():Math.min(start,text.length());Matcher words=Pattern.compile("[\\p{L}\\p{M}]+(?:['‘’ʻʼ-][\\p{L}\\p{M}]+)*").matcher(text);
   while(words.find()){if(words.start()<=caret)value=words.group();if(words.end()>=caret&&!value.isEmpty())break;}
  }
  value=value.trim().toLowerCase(Locale.ROOT).replace("ö","o‘").replace("ğ","g‘").replace("ş","sh").replace("ç","ch");
  if(value.isEmpty()||value.length()>120||value.split("\\s+").length>10)throw new IllegalArgumentException("Select a word or short phrase to look up.");return value;
 }
 public static boolean sameDraft(String original,String current,int window,int currentWindow,String app,String currentApp,boolean editable,boolean password){return editable&&!password&&window==currentWindow&&app.equals(currentApp)&&original.equals(current);}
 private TextTools(){}
}
