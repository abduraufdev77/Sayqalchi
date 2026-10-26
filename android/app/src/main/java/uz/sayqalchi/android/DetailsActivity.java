package uz.sayqalchi.android;
import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.Bundle;
import android.widget.*;
import uz.sayqalchi.core.Engine;
public final class DetailsActivity extends Activity {
 private static Engine.Result pending;
 static void open(Context context,Engine.Result result){pending=result;context.startActivity(new Intent(context,DetailsActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}
 @Override public void onCreate(Bundle state){super.onCreate(state);Engine.Result result=pending;LinearLayout root=Ui.column(this);root.setPadding(Ui.dp(this,22),Ui.dp(this,58),Ui.dp(this,22),Ui.dp(this,24));root.setBackgroundColor(0xff070807);root.addView(Ui.button(this,"← Back",0xff202420,0xffeeeeee,this::finish));Ui.space(root,20);TextView content=Ui.text(this,result==null?"This result expired. Open a new suggestion.":result.details,18,0xfff6f6f1);content.setTextIsSelectable(true);ScrollView scroll=new ScrollView(this);scroll.addView(content);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));if(result!=null){Ui.space(root,16);root.addView(Ui.button(this,"Copy",Ui.CYAN,Ui.INK,()->((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Sayqalchi result",result.details))));if(!result.source.isEmpty())root.addView(Ui.button(this,"Open source ↗",0xff202420,Ui.CYAN,()->startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(result.source)))));}setContentView(root);}
}
