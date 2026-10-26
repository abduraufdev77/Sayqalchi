package uz.sayqalchi.android;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.os.PowerManager;
import android.view.*;
import android.widget.*;
import android.text.*;
import android.text.style.ForegroundColorSpan;
import uz.sayqalchi.core.*;

final class Ui {
 static final int INK=Color.rgb(27,29,27),MUTED=Color.rgb(133,138,133),CYAN=0xff00ddf1,GREEN=0xff91ef57,ORANGE=0xffff743d,PAPER=0xfff8f8f4;
 static int dp(Context c,float n){return Math.round(n*c.getResources().getDisplayMetrics().density);}
 static GradientDrawable rounded(int color,float radius,Context c){GradientDrawable shape=new GradientDrawable();shape.setColor(color);shape.setCornerRadius(dp(c,radius));return shape;}
 static android.graphics.Typeface font(Context c){return c.getResources().getFont(R.font.voicelab);}
 static TextView text(Context c,String text,int size,int color){TextView view=new TextView(c);view.setText(text);view.setTextSize(size);view.setTextColor(color);view.setTypeface(font(c));return view;}
 static TextView button(Context c,String text,int background,int foreground,Runnable action){TextView view=text(c,text,13,foreground);view.setGravity(Gravity.CENTER);view.setMinHeight(dp(c,40));view.setPadding(dp(c,14),dp(c,8),dp(c,14),dp(c,8));view.setBackground(rounded(background,20,c));view.setClickable(true);view.setFocusable(true);view.setOnClickListener(v->action.run());view.setContentDescription(text);return view;}
 static LinearLayout column(Context c){LinearLayout view=new LinearLayout(c);view.setOrientation(LinearLayout.VERTICAL);return view;}
 static LinearLayout row(Context c){LinearLayout view=new LinearLayout(c);view.setOrientation(LinearLayout.HORIZONTAL);view.setGravity(Gravity.CENTER_VERTICAL);return view;}
 static void space(LinearLayout parent,int height){View view=new View(parent.getContext());parent.addView(view,new LinearLayout.LayoutParams(1,dp(parent.getContext(),height)));}
 static LinearLayout.LayoutParams weight(){return new LinearLayout.LayoutParams(0,LinearLayout.LayoutParams.WRAP_CONTENT,1);}
 static CharSequence rendered(String input,Engine.Result result){
  if(result.tool!=TextTools.Tool.FORMAT){SpannableString output=new SpannableString(result.text);output.setSpan(new ForegroundColorSpan(ORANGE),0,output.length(),0);return output;}
  SpannableStringBuilder output=new SpannableStringBuilder();for(TextTools.Run run:TextTools.runs(input)){int start=output.length();output.append(run.text);if(run.changed)output.setSpan(new ForegroundColorSpan(ORANGE),start,output.length(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);}return output;
 }
 static final class Logo extends View {
  private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Paint.FontMetrics metrics=new Paint.FontMetrics();
  Logo(Context c){super(c);paint.setTypeface(font(c));setContentDescription("Sayqalchi ö");}
  @Override protected void onSizeChanged(int width,int height,int oldWidth,int oldHeight){super.onSizeChanged(width,height,oldWidth,oldHeight);paint.setTextSize(height*.89f);paint.setShader(new LinearGradient(0,0,width,height,new int[]{0xffaaa2f8,0xffedb4ce,0xfff5c5a1},null,Shader.TileMode.CLAMP));paint.getFontMetrics(metrics);}
  @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);canvas.drawText("ö",(getWidth()-paint.measureText("ö"))/2,(getHeight()-metrics.ascent-metrics.descent)/2,paint);}
 }
 static final class Waveform extends View {
  private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private ValueAnimator animator;private float phase;private boolean busy;
  Waveform(Context c){super(c);setContentDescription("Processing status");}
  void busy(boolean value){if(value==busy)return;busy=value;stop();PowerManager power=(PowerManager)getContext().getSystemService(Context.POWER_SERVICE);
   if(value&&ValueAnimator.areAnimatorsEnabled()&&!power.isPowerSaveMode()){animator=ValueAnimator.ofFloat(0,6.283f);animator.setDuration(1000);animator.setRepeatCount(ValueAnimator.INFINITE);animator.addUpdateListener(a->{phase=(float)a.getAnimatedValue();invalidate();});animator.start();}invalidate();}
  private void stop(){if(animator!=null){animator.cancel();animator=null;}}
  @Override protected void onDetachedFromWindow(){stop();super.onDetachedFromWindow();}
  @Override protected void onDraw(Canvas c){super.onDraw(c);float slot=getWidth()/6f;for(int i=0;i<6;i++){float fraction=busy?(.25f+.7f*(float)Math.abs(Math.sin(phase+i*.8))):.24f;float height=getHeight()*fraction;paint.setColor(i<3?CYAN:GREEN);paint.setAlpha(busy?255:150);c.drawRoundRect(i*slot+slot*.22f,(getHeight()-height)/2,i*slot+slot*.65f,(getHeight()+height)/2,slot/2,slot/2,paint);}}
 }
 private Ui(){}
}
