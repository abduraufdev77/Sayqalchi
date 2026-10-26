package uz.sayqalchi.android;
import android.accessibilityservice.AccessibilityService;
import android.app.KeyguardManager;
import android.content.*;
import android.os.*;
import android.text.InputType;
import android.view.accessibility.*;
import java.util.*;
import java.util.concurrent.*;
import uz.sayqalchi.core.*;

public final class SuggestionService extends AccessibilityService implements Popup.Actions,SharedPreferences.OnSharedPreferenceChangeListener {
 static volatile SuggestionService connected;
 private final Handler handler=new Handler(Looper.getMainLooper());
 private final ThreadPoolExecutor executor=new ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,new ArrayBlockingQueue<>(1),new ThreadPoolExecutor.DiscardOldestPolicy());
 private final Engine engine=new Engine();private Preferences preferences;private Popup popup;private Snapshot snapshot;private Engine.Result result;private TextTools.Tool tool;private long generation;private WritingServices.Cancel cancellation;private Future<?> work;private Runnable pending;private String dismissed="";private boolean applying;
 private static final class Snapshot {final AccessibilityNodeInfo node;final String text,pkg;final int window,start,end;Snapshot(AccessibilityNodeInfo node,String text){this.node=node;this.text=text;pkg=String.valueOf(node.getPackageName());window=node.getWindowId();start=node.getTextSelectionStart();end=node.getTextSelectionEnd();}String key(){return pkg+":"+window+":"+text;}}
 private final BroadcastReceiver screen=new BroadcastReceiver(){@Override public void onReceive(Context context,Intent intent){if(Intent.ACTION_SCREEN_OFF.equals(intent.getAction()))clear();}};
 @Override protected void onServiceConnected(){super.onServiceConnected();preferences=new Preferences(this);tool=preferences.tool();popup=new Popup(this,this);popup.languages(preferences.source(),preferences.target());preferences.values.registerOnSharedPreferenceChangeListener(this);IntentFilter filter=new IntentFilter(Intent.ACTION_SCREEN_OFF);if(Build.VERSION.SDK_INT>=33)registerReceiver(screen,filter,Context.RECEIVER_NOT_EXPORTED);else registerReceiver(screen,filter);connected=this;}
 @Override public void onAccessibilityEvent(AccessibilityEvent event){
  if(preferences==null||popup==null||applying)return;
  if(!preferences.enabled()||!preferences.consent()||((KeyguardManager)getSystemService(KEYGUARD_SERVICE)).isKeyguardLocked()){clear();return;}
  String pkg=String.valueOf(event.getPackageName());String cls=String.valueOf(event.getClassName());
  if(pkg.equals(getPackageName())){if(cls.equals(MainActivity.class.getName())||cls.equals(DetailsActivity.class.getName()))clear();return;}
  if(pkg.contains("inputmethod")||pkg.contains("keyboard"))return;
  if(event.isPassword()){clear();return;}
  AccessibilityNodeInfo field=focused();
  if(!allowed(field)){clear();return;}
  String text=field.getText()==null?"":field.getText().toString();
  if(text.trim().isEmpty()||text.length()>200000){clear();return;}
  Snapshot next=new Snapshot(field,text);
  boolean same=snapshot!=null&&snapshot.node.equals(field)&&snapshot.text.equals(text);
  if(same&&(tool!=TextTools.Tool.IZOHCHI||snapshot.start==next.start&&snapshot.end==next.end))return;
  invalidate();snapshot=next;tool=preferences.tool();result=null;dismissed="";
  popup.processing(tool);long id=generation;pending=()->{if(id==generation)process();};handler.postDelayed(pending,650);
 }
 private AccessibilityNodeInfo focused(){
  AccessibilityNodeInfo root=getRootInActiveWindow();AccessibilityNodeInfo field=root==null?null:root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);if(field!=null)return field;
  for(AccessibilityWindowInfo window:getWindows())if(window.getType()==AccessibilityWindowInfo.TYPE_APPLICATION&&window.isFocused()){root=window.getRoot();if(root!=null){field=root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);if(field!=null)return field;}}
  return null;
 }
 private boolean allowed(AccessibilityNodeInfo node){
  if(node==null||!node.isFocused()||!node.isEditable()||!node.isEnabled()||node.isPassword())return false;
  String pkg=String.valueOf(node.getPackageName()).toLowerCase(Locale.ROOT);if(pkg.equals(getPackageName())||preferences.excluded(pkg))return false;
  for(String blocked:new String[]{"systemui","permissioncontroller","com.android.settings","dialer","incallui","bitwarden","onepassword","1password","keepass","lastpass","termux"})if(pkg.contains(blocked))return false;
  int input=node.getInputType(),kind=input&InputType.TYPE_MASK_CLASS,variation=input&InputType.TYPE_MASK_VARIATION;
  if(kind==InputType.TYPE_CLASS_TEXT&&(variation==InputType.TYPE_TEXT_VARIATION_PASSWORD||variation==InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD||variation==InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)||kind==InputType.TYPE_CLASS_NUMBER&&variation==InputType.TYPE_NUMBER_VARIATION_PASSWORD)return false;
  return node.getActionList().contains(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT);
 }
 private void invalidate(){generation++;if(pending!=null)handler.removeCallbacks(pending);pending=null;if(cancellation!=null)cancellation.cancel();if(work!=null)work.cancel(true);cancellation=null;work=null;}
 private void clear(){invalidate();snapshot=null;result=null;dismissed="";if(popup!=null)popup.hide();}
 private void process(){
  if(snapshot==null||!preferences.enabled()||snapshot.key().equals(dismissed))return;
  invalidate();Snapshot captured=snapshot;TextTools.Tool requested=tool;long id=generation;WritingServices.Cancel token=new WritingServices.Cancel();cancellation=token;
  String source=preferences.source(),target=preferences.target();WritingServices.Options options=preferences.options();popup.processing(tool);popup.languages(source,target);
  work=executor.submit(()->{try{Engine.Result output=engine.process(requested,captured.text,captured.start,captured.end,source,target,options,token);token.check();handler.post(()->{
    if(id!=generation||snapshot!=captured||!preferences.enabled())return;result=output;
    if(output.tool==TextTools.Tool.FORMAT&&output.text.equals(captured.text)){popup.idle(tool);return;}
    popup.result(captured.text,output,output.canReplace()&&!output.text.equals(captured.text),appLabel(captured.pkg));
   });}catch(CancellationException ignored){}catch(Exception error){handler.post(()->{if(id==generation){result=null;popup.error(error instanceof IllegalArgumentException?error.getMessage():"The service is unavailable. Check your connection and try again.");}});}});
 }
 private String appLabel(String pkg){try{return getPackageManager().getApplicationLabel(getPackageManager().getApplicationInfo(pkg,0)).toString();}catch(Exception ignored){return "Current app";}}
 @Override public void choose(TextTools.Tool selected){if(snapshot==null)return;tool=selected;dismissed="";process();}
 @Override public void apply(){
  if(result==null||!result.canReplace()||snapshot==null||!preferences.enabled())return;
  Snapshot captured=snapshot;Engine.Result output=result;AccessibilityNodeInfo current=focused();
  if(!allowed(current)||!current.equals(captured.node)||!current.refresh()||!TextTools.sameDraft(captured.text,current.getText()==null?"":current.getText().toString(),captured.window,current.getWindowId(),captured.pkg,String.valueOf(current.getPackageName()),current.isEditable(),current.isPassword())){invalidate();result=null;popup.error("The draft or focus changed. Nothing was replaced. Type again to refresh.");return;}
  invalidate();applying=true;
  try{Bundle arguments=new Bundle();arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,output.text);boolean applied=current.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,arguments);
   if(applied&&current.refresh()&&output.text.equals(current.getText()==null?"":current.getText().toString())){snapshot=new Snapshot(current,output.text);dismissed=snapshot.key();result=null;popup.idle(tool);}
   else {result=null;popup.error("The editor could not confirm replacement. Check your draft before trying again.");}
  }finally{applying=false;}
 }
 @Override public void copy(){if(result!=null)((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Sayqalchi result",result.text));}
 @Override public void details(){if(result!=null)DetailsActivity.open(this,result);}
 @Override public void dismiss(){if(snapshot!=null)dismissed=snapshot.key();invalidate();result=null;popup.idle(tool);}
 @Override public void pause(){preferences.enabled(false);}
 @Override public void language(boolean source){popup.chooseLanguage(source,source?preferences.source():preferences.target(),code->{String from=source?code:preferences.source(),to=source?preferences.target():code;if(!TextTools.supported(from,to)){if(source)to=from.equals("uz-Latn")?"en":"uz-Latn";else from=to.equals("uz-Latn")?"en":"uz-Latn";}preferences.languages(from,to);});}
 @Override public void onSharedPreferenceChanged(SharedPreferences prefs,String key){handler.post(()->{if(!preferences.enabled()||!preferences.consent()){clear();return;}if(snapshot!=null){tool=preferences.tool();dismissed="";process();}});}
 @Override public void onInterrupt(){clear();}
 @Override public void onDestroy(){clear();connected=null;if(preferences!=null)preferences.values.unregisterOnSharedPreferenceChangeListener(this);try{unregisterReceiver(screen);}catch(Exception ignored){}executor.shutdownNow();super.onDestroy();}
 @Override public void onConfigurationChanged(android.content.res.Configuration configuration){super.onConfigurationChanged(configuration);clear();}
}
