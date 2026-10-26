#!/usr/bin/env python3
"""Build a signed APK using a persistent key outside the repository.
No password or private key is printed, embedded in source, or copied to the APK.
"""
from pathlib import Path
import hashlib, json, os, secrets, shutil, subprocess, sys, tempfile, zipfile

ROOT=Path(__file__).resolve().parent.parent

def run(args, env=None):
    subprocess.run([str(x) for x in args],cwd=ROOT,env=env,check=True)

def main():
    env=os.environ.copy()
    sdk=Path(env.get('ANDROID_HOME',str(Path.home()/'Library/Android/sdk')))
    java=Path(env.get('JAVA_HOME','/Applications/Android Studio.app/Contents/jbr/Contents/Home'))
    if not (sdk/'platform-tools/adb').exists() or not (java/'bin/keytool').exists():
        sys.exit('Set ANDROID_HOME to an Android SDK and JAVA_HOME to JDK 21.')
    env['ANDROID_HOME']=str(sdk);env['JAVA_HOME']=str(java)
    env['PATH']=str(java/'bin')+os.pathsep+env.get('PATH','')
    names=['SAYQALCHI_ANDROID_KEYSTORE','SAYQALCHI_ANDROID_STORE_PASSWORD','SAYQALCHI_ANDROID_KEY_ALIAS','SAYQALCHI_ANDROID_KEY_PASSWORD']
    if any(env.get(n) for n in names) and not all(env.get(n) for n in names):
        sys.exit('Set all four Android signing environment variables, or none to use your local signing profile.')
    if not env.get(names[0]):
        private=Path.home()/'.local/share/sayqalchi/android'
        private.mkdir(parents=True,exist_ok=True,mode=0o700)
        profile=private/'signing.json'
        if profile.exists(): config=json.loads(profile.read_text())
        else:
            config={'store':str(private/'release.jks'),'password':secrets.token_urlsafe(36),'alias':'sayqalchi'}
            descriptor=os.open(profile,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(descriptor,'w') as stream:json.dump(config,stream)
        env.update(dict(zip(names,[config['store'],config['password'],config['alias'],config['password']])))
        if not Path(config['store']).exists():
            command=[str(java/'bin/keytool'),'-genkeypair','-keystore',config['store'],'-storepass:env',names[1],'-keypass:env',names[3],'-alias',config['alias'],'-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Sayqalchi Android, O=Sayqalchi, C=UZ']
            result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            if result.returncode:sys.exit('Could not create the local Android signing key. Check JDK and local profile permissions.')
            Path(config['store']).chmod(0o600)
    run([sys.executable,'scripts/audit-secrets.py'],env)
    run([ROOT/'android/gradlew','-p','android',':core:test',':app:lintRelease',':app:assembleRelease'],env)
    apk=ROOT/'android/app/build/outputs/apk/release/app-release.apk'
    if not apk.exists():sys.exit('The signed release APK was not produced.')
    tools=sdk/'build-tools/36.0.0'
    if not (tools/'apksigner').exists():tools=next(p for p in sorted((sdk/'build-tools').iterdir(),reverse=True) if (p/'apksigner').exists())
    run([tools/'apksigner','verify','--verbose',apk],env)
    with tempfile.TemporaryDirectory(prefix='sayqalchi-apk-audit-') as directory:
        with zipfile.ZipFile(apk) as archive:archive.extractall(directory)
        run([sys.executable,'scripts/audit-secrets.py','--bundle',directory],env)
    output=ROOT/'dist';output.mkdir(exist_ok=True)
    version=json.loads((ROOT/'android/app/build/outputs/apk/release/output-metadata.json').read_text())['elements'][0]['versionName']
    target=output/f'Sayqalchi-{version}-android.apk';shutil.copy2(apk,target)
    digest=hashlib.sha256(target.read_bytes()).hexdigest()
    (output/'SHA256SUMS-android.txt').write_text(f'{digest}  {target.name}\n')
    print(f'Packaged: {target}')
    print('Signing profile remains outside the repository. Keep it for future APK updates.')
if __name__=='__main__':main()
