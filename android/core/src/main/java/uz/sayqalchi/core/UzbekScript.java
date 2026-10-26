package uz.sayqalchi.core;
import java.util.*;
import java.util.regex.*;
public final class UzbekScript {
 private static final Map<String,String> CYRILLIC=new HashMap<>();
 static {
  CYRILLIC.put("ё","yo");
  CYRILLIC.put("ю","yu");
  CYRILLIC.put("я","ya");
  CYRILLIC.put("щ","shch");
  CYRILLIC.put("ў","o‘");
  CYRILLIC.put("ғ","g‘");
  CYRILLIC.put("ҳ","h");
  CYRILLIC.put("қ","q");
  CYRILLIC.put("ц","ts");
  CYRILLIC.put("ч","ch");
  CYRILLIC.put("ш","sh");
  CYRILLIC.put("а","a");
  CYRILLIC.put("б","b");
  CYRILLIC.put("в","v");
  CYRILLIC.put("г","g");
  CYRILLIC.put("д","d");
  CYRILLIC.put("ж","j");
  CYRILLIC.put("з","z");
  CYRILLIC.put("и","i");
  CYRILLIC.put("й","y");
  CYRILLIC.put("к","k");
  CYRILLIC.put("л","l");
  CYRILLIC.put("м","m");
  CYRILLIC.put("н","n");
  CYRILLIC.put("о","o");
  CYRILLIC.put("п","p");
  CYRILLIC.put("р","r");
  CYRILLIC.put("с","s");
  CYRILLIC.put("т","t");
  CYRILLIC.put("у","u");
  CYRILLIC.put("ф","f");
  CYRILLIC.put("х","x");
  CYRILLIC.put("ъ","’");
  CYRILLIC.put("ы","i");
  CYRILLIC.put("ь","");
  CYRILLIC.put("э","e");
 }
 private static final String[][] LATIN={
  {"tsiya","ция"},
  {"sh","ш"},
  {"ch","ч"},
  {"yo","ё"},
  {"yu","ю"},
  {"ya","я"},
  {"ye","е"},
  {"o‘","ў"},
  {"g‘","ғ"},
  {"ö","ў"},
  {"ğ","ғ"},
  {"ş","ш"},
  {"ç","ч"},
  {"a","а"},
  {"b","б"},
  {"d","д"},
  {"f","ф"},
  {"g","г"},
  {"h","ҳ"},
  {"i","и"},
  {"j","ж"},
  {"k","к"},
  {"l","л"},
  {"m","м"},
  {"n","н"},
  {"o","о"},
  {"p","п"},
  {"q","қ"},
  {"r","р"},
  {"s","с"},
  {"t","т"},
  {"u","у"},
  {"v","в"},
  {"x","х"},
  {"y","й"},
  {"z","з"},
  {"’","ъ"}
 };
 private static final Pattern PROTECTED=Pattern.compile("https?://\\S+|www\\.\\S+|[\\w.+-]+@[\\w-]+\\.[\\w.-]+|\\b[\\w-]+(?:\\.[\\w-]+)*\\.(?:uz|com|org|net|edu|gov|ru|io|info|pdf|docx?|xlsx?)\\b",Pattern.CASE_INSENSITIVE);
 public static String convert(String input,boolean toCyrillic){Matcher matcher=PROTECTED.matcher(input);StringBuilder result=new StringBuilder();int cursor=0;while(matcher.find()){result.append(map(input.substring(cursor,matcher.start()),toCyrillic)).append(matcher.group());cursor=matcher.end();}return result.append(map(input.substring(cursor),toCyrillic)).toString();}
 private static String map(String input,boolean toCyrillic){
  char[] chars=input.toCharArray();for(int i=0;toCyrillic&&i<chars.length;i++)if("'‘’ʻʼ`´′".indexOf(chars[i])>=0)chars[i]=i>0&&"oOgG".indexOf(chars[i-1])>=0?'‘':'’';
  String source=new String(chars),lower=source.toLowerCase(Locale.ROOT);StringBuilder output=new StringBuilder();
  for(int i=0;i<source.length();i++){
   boolean initial=i==0||!Character.isLetter(source.charAt(i-1));int prev=i-1;if(prev>=0&&source.charAt(prev)=='‘')prev--;
   char before=prev>=0?lower.charAt(prev):'\0';String target=null;int length=1;
   if(toCyrillic){if(lower.charAt(i)=='e')target=initial||"aeiou".indexOf(before)>=0?"э":"е";else if(initial&&lower.startsWith("ts",i)){target="ц";length=2;}else for(String[] pair:LATIN)if(lower.startsWith(pair[0],i)){target=pair[1];length=pair[0].length();break;}}
   else if(lower.charAt(i)=='е')target=initial||"аеёиоуэюяў".indexOf(before)>=0?"ye":"e";else target=CYRILLIC.get(lower.substring(i,i+1));
   if(target==null){output.append(source.charAt(i));continue;}
   if(Character.isUpperCase(source.charAt(i))){int start=i,end=i+length;while(start>0&&Character.isLetter(source.charAt(start-1)))start--;while(end<source.length()&&Character.isLetter(source.charAt(end)))end++;int letters=0;boolean allCaps=true;for(int k=start;k<end;k++)if(Character.isLetter(source.charAt(k))){letters++;allCaps&=Character.isUpperCase(source.charAt(k));}target=allCaps&&letters>1?target.toUpperCase(Locale.ROOT):target.isEmpty()?"":target.substring(0,1).toUpperCase(Locale.ROOT)+target.substring(1);}
   output.append(target);i+=length-1;
  }return output.toString();
 }
}
