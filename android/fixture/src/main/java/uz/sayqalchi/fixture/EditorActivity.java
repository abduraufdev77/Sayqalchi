package uz.sayqalchi.fixture;
import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.*;

public class EditorActivity extends Activity {
 @Override public void onCreate(Bundle state) {
  super.onCreate(state); LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setPadding(24,100,24,24);
  TextView title = new TextView(this); title.setText("Disposable cross-app editor"); title.setTextSize(22); root.addView(title);
  EditText draft = new EditText(this); draft.setHint("Draft"); draft.setContentDescription("Fixture draft"); draft.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_MULTI_LINE); draft.setMinLines(4); root.addView(draft);
  EditText password = new EditText(this); password.setHint("Password"); password.setContentDescription("Fixture password"); password.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD); root.addView(password);
  Button stale = new Button(this); stale.setText("Change draft"); stale.setOnClickListener(v -> { draft.setText("Newer draft"); draft.requestFocus(); }); root.addView(stale);
  root.setOnApplyWindowInsetsListener((v,insets) -> { v.setPadding(24,100+insets.getSystemWindowInsetTop(),24,24); return insets; });
  setContentView(root); draft.requestFocus();
 }
}
