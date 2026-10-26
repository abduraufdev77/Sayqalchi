package uz.sayqalchi.android;
import android.service.quicksettings.*;
import android.app.PendingIntent;
import android.content.Intent;
public final class PauseTile extends TileService {
 @Override public void onStartListening(){super.onStartListening();refresh();}
 private void refresh(){Tile tile=getQsTile();if(tile!=null){Preferences prefs=new Preferences(this);tile.setState(prefs.enabled()?Tile.STATE_ACTIVE:Tile.STATE_INACTIVE);tile.setLabel("Sayqalchi");tile.updateTile();}}
 @Override public void onClick(){super.onClick();Preferences prefs=new Preferences(this);if(!prefs.consent()){
  Intent intent=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);PendingIntent pending=PendingIntent.getActivity(this,0,intent,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  if(android.os.Build.VERSION.SDK_INT>=34)startActivityAndCollapse(pending);else try{pending.send();}catch(PendingIntent.CanceledException ignored){}return;
 }prefs.enabled(!prefs.enabled());refresh();}
}
