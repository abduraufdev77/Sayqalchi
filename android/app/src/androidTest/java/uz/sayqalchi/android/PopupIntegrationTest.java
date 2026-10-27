package uz.sayqalchi.android;
import android.content.*;
import android.os.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.*;
import org.junit.*;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import uz.sayqalchi.core.*;
import java.io.File;

@RunWith(AndroidJUnit4.class)
public class PopupIntegrationTest {
 private UiDevice device;private Context target;
 @Before public void prepare()throws Exception{
  Configurator.getInstance().setUiAutomationFlags(android.app.UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
  device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
  // Permission setup is permitted only on this disposable emulator, never a phone.
  Assume.assumeTrue("Integration setup is emulator-only",device.executeShellCommand("getprop ro.kernel.qemu").trim().equals("1"));
  target=InstrumentationRegistry.getInstrumentation().getTargetContext();
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{Preferences prefs=new Preferences(target);prefs.values.edit().clear().putBoolean("disclosureAccepted",true).putBoolean("enabled",true).apply();});
  device.wakeUp();
  device.executeShellCommand("settings put secure enabled_accessibility_services null");
  Thread.sleep(150);
  device.executeShellCommand("settings put secure enabled_accessibility_services uz.sayqalchi.android/uz.sayqalchi.android.SuggestionService");device.executeShellCommand("settings put secure accessibility_enabled 1");
  for(int i=0;i<50&&SuggestionService.connected==null;i++)Thread.sleep(100);
  assertNotNull("Service connected",SuggestionService.connected);
  device.executeShellCommand("am start -W -S -n uz.sayqalchi.fixture/.EditorActivity");
  assertTrue(device.wait(Until.hasObject(By.desc("Fixture draft")),5000));
 }
 private UiObject2 draft(){return device.findObject(By.desc("Fixture draft"));}
 @Test public void pauseShowsWholeDraftAndUseReplacesIt()throws Exception{
  String original="O'zbekcha yozish oson.\n\nG'oya va shahar.";draft().click();draft().setText(original);
  assertTrue("Automatic popup result",device.wait(Until.hasObject(By.text(TextTools.format(original))),6000));
  assertTrue(device.hasObject(By.desc("Sayqalchi popup")));
  device.takeScreenshot(new File(target.getExternalFilesDir(null),"android-popup.png"));
  device.findObject(By.desc("Use suggested text")).click();
  assertTrue(device.wait(Until.hasObject(By.desc("Fixture draft").text(TextTools.format(original))),5000));
 }
 @Test public void passwordFieldsHideThePopup()throws Exception{
  draft().setText("O'zbekcha");assertTrue(device.wait(Until.hasObject(By.text("Özbekça")),5000));
  UiObject2 password=device.findObject(By.desc("Fixture password"));password.click();password.setText("disposable-fixture-only");
  assertTrue("No password popup",device.wait(Until.gone(By.desc("Sayqalchi popup")),5000));
 }
 @Test public void changedDraftCannotReceiveOldResult()throws Exception{
  draft().setText("O'zbekcha");assertTrue(device.wait(Until.hasObject(By.text("Özbekça")),5000));
  draft().setText("A newer draft");
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->SuggestionService.connected.apply());
  assertEquals("A newer draft",draft().getText());
 }
 @Test public void customTranslationAppearsAutomaticallyAfterPause()throws Exception{
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{try{Preferences prefs=new Preferences(target);prefs.saveKey("fixture-only");prefs.values.edit().putString("defaultTool","TRANSLATE").putBoolean("custom",true).putString("url","http://10.0.2.2:18325").putBoolean("allowHttp",true).apply();}catch(Exception error){throw new AssertionError(error);}});
  draft().setText("Salom\n\nDunyo");
  assertTrue("Automatic translation result",device.wait(Until.hasObject(By.text("Translated: Salom\n\nDunyo")),8000));
  device.findObject(By.desc("Use suggested text")).click();
  assertTrue(device.wait(Until.hasObject(By.desc("Fixture draft").text("Translated: Salom\n\nDunyo")),5000));
 }
 @Test public void pauseRemovesPopupAndStopsNewSuggestions()throws Exception{
  draft().setText("O'zbekcha");assertTrue(device.wait(Until.hasObject(By.text("Özbekça")),5000));
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->new Preferences(target).enabled(false));
  assertTrue(device.wait(Until.gone(By.desc("Sayqalchi popup")),5000));draft().setText("Shahar");Thread.sleep(900);assertFalse(device.hasObject(By.desc("Sayqalchi popup")));
 }
 @Test public void localScriptResultAndDetails()throws Exception{
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->new Preferences(target).values.edit().putString("defaultTool","TRANSLATE").putString("source","uz-Latn").putString("target","uz-Cyrl").apply());
  draft().setText("O‘zbekiston shahar");assertTrue(device.wait(Until.hasObject(By.text("Ўзбекистон шаҳар")),5000));
  device.findObject(By.text("More ↗")).click();assertTrue(device.wait(Until.hasObject(By.text("Ўзбекистон шаҳар")),5000));
 }
 @Test public void popupTabsAndLanguageBadgeWork()throws Exception{
  InstrumentationRegistry.getInstrumentation().runOnMainSync(()->{try{Preferences prefs=new Preferences(target);prefs.saveKey("fixture-only");prefs.values.edit().putBoolean("custom",true).putString("url","http://10.0.2.2:18325").putBoolean("allowHttp",true).apply();}catch(Exception error){throw new AssertionError(error);}});
  draft().setText("O'zbekcha");assertTrue(device.wait(Until.hasObject(By.text("Özbekça")),5000));
  device.findObject(By.desc("Show Sayqalchi tools")).click();
  device.findObject(By.desc("Translate")).click();
  assertTrue(device.wait(Until.hasObject(By.text("Translated: O'zbekcha")),8000));
  if(!device.hasObject(By.text("EN")))device.findObject(By.desc("Show Sayqalchi tools")).click();
  assertTrue(device.wait(Until.hasObject(By.text("EN")),3000));device.findObject(By.text("EN")).click();
  assertTrue(device.wait(Until.hasObject(By.text("Ўзбек")),3000));device.findObject(By.text("Ўзбек")).click();
  assertTrue(device.wait(Until.hasObject(By.text("Ўзбекча")),5000));
 }
 @Test public void keystoreDoesNotPersistPlaintext()throws Exception{
  Preferences prefs=new Preferences(target);prefs.saveKey("fixture-secret-android-only");assertEquals("fixture-secret-android-only",prefs.readKey());
  assertFalse(prefs.values.getString("encryptedKey","").contains("fixture-secret-android-only"));assertFalse(prefs.values.getAll().containsValue("fixture-secret-android-only"));
 }
}
