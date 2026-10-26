package uz.sayqalchi.android;
import android.content.*;
import android.security.keystore.*;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import uz.sayqalchi.core.*;

final class Preferences {
 final SharedPreferences values;
 Preferences(Context context){values=context.getSharedPreferences("sayqalchi",Context.MODE_PRIVATE);}
 boolean enabled(){return values.getBoolean("enabled",false);}
 void enabled(boolean value){values.edit().putBoolean("enabled",value).apply();}
 boolean consent(){return values.getBoolean("disclosureAccepted",false);}
 TextTools.Tool tool(){try{return TextTools.Tool.valueOf(values.getString("defaultTool","FORMAT"));}catch(Exception error){return TextTools.Tool.FORMAT;}}
 void tool(TextTools.Tool tool){values.edit().putString("defaultTool",tool.name()).apply();}
 String source(){return values.getString("source","uz-Latn");}String target(){return values.getString("target","en");}
 void languages(String source,String target){values.edit().putString("source",source).putString("target",target).apply();}
 WritingServices.Options options(){boolean custom=values.getBoolean("custom",false);return new WritingServices.Options(custom,values.getString("url",""),custom?readKey():"",values.getBoolean("allowHttp",false));}
 boolean excluded(String pkg){for(String value:values.getString("exclusions","").split(","))if(!value.trim().isEmpty()&&pkg.equals(value.trim()))return true;return false;}
 private SecretKey encryptionKey()throws Exception{KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);String alias="sayqalchi.translation";if(store.containsAlias(alias))return (SecretKey)store.getKey(alias,null);KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");generator.init(new KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());return generator.generateKey();}
 void saveKey(String key)throws Exception{if(key.trim().isEmpty()){values.edit().remove("encryptedKey").remove("keyIv").apply();return;}Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,encryptionKey());values.edit().putString("encryptedKey",Base64.encodeToString(cipher.doFinal(key.getBytes(java.nio.charset.StandardCharsets.UTF_8)),Base64.NO_WRAP)).putString("keyIv",Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP)).apply();}
 String readKey(){try{String stored=values.getString("encryptedKey","");if(stored.isEmpty())return "";Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,encryptionKey(),new GCMParameterSpec(128,Base64.decode(values.getString("keyIv",""),Base64.NO_WRAP)));return new String(cipher.doFinal(Base64.decode(stored,Base64.NO_WRAP)),java.nio.charset.StandardCharsets.UTF_8);}catch(Exception error){return "";}}
}
