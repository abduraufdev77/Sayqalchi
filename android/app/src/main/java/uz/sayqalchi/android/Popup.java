package uz.sayqalchi.android;
import android.animation.ValueAnimator;
import android.content.*;
import android.graphics.PixelFormat;
import android.os.Build;
import android.view.*;
import android.view.animation.PathInterpolator;
import android.widget.*;
import java.util.*;
import uz.sayqalchi.core.*;

final class Popup {
 interface Actions {void choose(TextTools.Tool tool);void apply();void copy();void details();void dismiss();void pause();void language(boolean source);}
 private final Context context;private final WindowManager windows;private final Actions actions;private final LinearLayout root,body,tabs,languages;private final LinearLayout header;private final TextView status,result,caption,use;private final Ui.Waveform waveform;
 private final WindowManager.LayoutParams params;private final Map<TextTools.Tool,TextView> badges=new EnumMap<>(TextTools.Tool.class);
 private boolean attached,expanded;private ValueAnimator resize;private TextTools.Tool selected=TextTools.Tool.FORMAT;private int currentWidth,currentHeight;
 Popup(Context context,Actions actions){
  this.context=context;this.actions=actions;windows=(WindowManager)context.getSystemService(Context.WINDOW_SERVICE);
  root=Ui.column(context);root.setPadding(Ui.dp(context,16),Ui.dp(context,3),Ui.dp(context,16),Ui.dp(context,12));root.setBackground(Ui.rounded(0xff070807,26,context));root.setClipToOutline(true);root.setElevation(Ui.dp(context,16));root.setContentDescription("Sayqalchi popup");
  header=Ui.row(context);Ui.Logo logo=new Ui.Logo(context);header.addView(logo,new LinearLayout.LayoutParams(Ui.dp(context,28),Ui.dp(context,30)));
  status=Ui.text(context,"Format",11,Ui.MUTED);status.setPadding(Ui.dp(context,9),0,0,0);header.addView(status,Ui.weight());waveform=new Ui.Waveform(context);header.addView(waveform,new LinearLayout.LayoutParams(Ui.dp(context,38),Ui.dp(context,22)));root.addView(header,new LinearLayout.LayoutParams(-1,Ui.dp(context,36)));
  header.setOnClickListener(v->{expanded=!expanded;updateVisibility();});header.setContentDescription("Show Sayqalchi tools");
  tabs=Ui.row(context);String[] labels={"Aa","◎","▣","▤"};for(TextTools.Tool tool:TextTools.Tool.values()){TextView badge=Ui.button(context,labels[tool.ordinal()],0xff202420,0xffeeeeee,()->actions.choose(tool));badge.setContentDescription(tool.label());LinearLayout.LayoutParams lp=Ui.weight();lp.setMargins(0,0,Ui.dp(context,5),0);tabs.addView(badge,lp);badges.put(tool,badge);}root.addView(tabs);
  languages=Ui.row(context);root.addView(languages);
  body=Ui.column(context);caption=Ui.text(context,"Entire draft",10,Ui.MUTED);body.addView(caption);Ui.space(body,8);
  ScrollView scroll=new ScrollView(context);scroll.setFillViewport(false);result=Ui.text(context,"",15,0xfff6f6f1);result.setLineSpacing(Ui.dp(context,3),1);scroll.addView(result);body.addView(scroll,new LinearLayout.LayoutParams(-1,-2));
  LinearLayout footer=Ui.row(context);Ui.space(body,12);body.addView(footer);TextView copy=Ui.button(context,"Copy",0xff202420,0xfff6f6f1,actions::copy);footer.addView(copy);TextView more=Ui.button(context,"More ↗",0xff202420,0xfff6f6f1,actions::details);LinearLayout.LayoutParams moreLp=new LinearLayout.LayoutParams(-2,-2);moreLp.setMargins(Ui.dp(context,6),0,0,0);footer.addView(more,moreLp);View gap=new View(context);footer.addView(gap,Ui.weight());use=Ui.button(context,"Use ↵",Ui.CYAN,Ui.INK,actions::apply);use.setContentDescription("Use suggested text");footer.addView(use);root.addView(body);
  LinearLayout extra=Ui.row(context);TextView dismiss=Ui.button(context,"Dismiss",0xff202420,0xffdddddd,actions::dismiss);TextView pause=Ui.button(context,"Pause",0xff202420,0xffdddddd,actions::pause);extra.addView(dismiss);extra.addView(pause);tabs.setTag(extra);root.addView(extra);
  params=new WindowManager.LayoutParams(Ui.dp(context,188),Ui.dp(context,48),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL|WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,PixelFormat.TRANSLUCENT);
  params.gravity=Gravity.TOP|Gravity.CENTER_HORIZONTAL;params.setTitle("Sayqalchi suggestions");params.y=safeTop()+Ui.dp(context,7);updateVisibility();
 }
 private int safeTop(){int top=Ui.dp(context,28);if(Build.VERSION.SDK_INT>=30){android.view.WindowInsets insets=windows.getCurrentWindowMetrics().getWindowInsets();top=Math.max(top,insets.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.statusBars()).top);android.view.DisplayCutout cutout=insets.getDisplayCutout();if(cutout!=null)top=Math.max(top,cutout.getSafeInsetTop());}return top;}
 private int maxWidth(){return Math.min(Ui.dp(context,360),context.getResources().getDisplayMetrics().widthPixels-Ui.dp(context,24));}
 void show(){if(attached)return;try{windows.addView(root,params);attached=true;}catch(RuntimeException ignored){attached=false;}}
 void hide(){if(resize!=null)resize.cancel();waveform.busy(false);if(attached){try{windows.removeView(root);}catch(RuntimeException ignored){}attached=false;}expanded=false;}
 void processing(TextTools.Tool tool){selected=tool;result.setText("");body.setVisibility(View.GONE);status.setText(tool.label());waveform.busy(true);expanded=false;updateVisibility();show();}
 void idle(TextTools.Tool tool){selected=tool;waveform.busy(false);result.setText("");status.setText(tool.label());expanded=false;updateVisibility();}
 void result(String input,Engine.Result output,boolean canUse,String app){selected=output.tool;waveform.busy(false);status.setText(output.tool.label());caption.setText(app+" · "+output.summary);result.setTextColor(0xfff6f6f1);result.setText(Ui.rendered(input,output));use.setEnabled(canUse);use.setVisibility(output.tool==TextTools.Tool.IZOHCHI?View.GONE:View.VISIBLE);limitResultHeight();updateVisibility();show();}
 void error(String message){waveform.busy(false);caption.setText("Sayqalchi");result.setText(message);result.setTextColor(Ui.ORANGE);use.setEnabled(false);limitResultHeight();updateVisibility();show();}
 private void limitResultHeight(){int width=maxWidth()-Ui.dp(context,32);result.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));android.view.ViewGroup scroll=(android.view.ViewGroup)result.getParent();scroll.setLayoutParams(new LinearLayout.LayoutParams(-1,Math.min(Ui.dp(context,180),result.getMeasuredHeight()+Ui.dp(context,2))));}
 void languages(String source,String target){languages.removeAllViews();TextView from=Ui.button(context,shortLang(source),0xff202420,Ui.CYAN,()->actions.language(true));TextView arrow=Ui.text(context,"  ⇄  ",15,Ui.MUTED);TextView to=Ui.button(context,shortLang(target),0xff202420,Ui.CYAN,()->actions.language(false));languages.addView(from);languages.addView(arrow);languages.addView(to);}
 static String shortLang(String language){switch(language){case "en":return "EN";case "ru":return "RU";case "uz-Cyrl":return "ЎЗ";default:return "UZ";}}
 void chooseLanguage(boolean source,String current,java.util.function.Consumer<String> selected){
  android.widget.PopupMenu menu=new android.widget.PopupMenu(context,source?languages.getChildAt(0):languages.getChildAt(2));String[] codes={"uz-Latn","en","ru","uz-Cyrl"};String[] names={"O‘zbek","English","Русский","Ўзбек"};for(int i=0;i<codes.length;i++)menu.getMenu().add(0,i,i,names[i]).setCheckable(true).setChecked(codes[i].equals(current));menu.setOnMenuItemClickListener(item->{selected.accept(codes[item.getItemId()]);return true;});menu.show();
 }
 private void updateVisibility(){
  tabs.setVisibility(expanded?View.VISIBLE:View.GONE);((View)tabs.getTag()).setVisibility(expanded?View.VISIBLE:View.GONE);languages.setVisibility(expanded&&selected==TextTools.Tool.TRANSLATE?View.VISIBLE:View.GONE);body.setVisibility(result.getText().length()>0?View.VISIBLE:View.GONE);
  for(Map.Entry<TextTools.Tool,TextView> entry:badges.entrySet()){boolean active=entry.getKey()==selected;entry.getValue().setBackground(Ui.rounded(active?Ui.GREEN:0xff202420,20,context));entry.getValue().setTextColor(active?Ui.INK:0xffdddddd);}
  boolean big=expanded||body.getVisibility()==View.VISIBLE;int width=big?maxWidth():Ui.dp(context,188);
  root.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));animate(width,Math.max(Ui.dp(context,48),root.getMeasuredHeight()));
 }
 private void animate(int width,int height){
  if(resize!=null)resize.cancel();int fromWidth=attached?params.width:width,fromHeight=attached?params.height:height;
  params.y=safeTop()+Ui.dp(context,7);
  if(!attached||!ValueAnimator.areAnimatorsEnabled()){params.width=width;params.height=height;if(attached)windows.updateViewLayout(root,params);return;}
  resize=ValueAnimator.ofFloat(0,1);resize.setDuration(260);resize.setInterpolator(new PathInterpolator(.2f,0,.2f,1));resize.addUpdateListener(a->{float t=(float)a.getAnimatedValue();params.width=Math.round(fromWidth+(width-fromWidth)*t);params.height=Math.round(fromHeight+(height-fromHeight)*t);if(attached)try{windows.updateViewLayout(root,params);}catch(RuntimeException ignored){}});resize.start();
 }
}
