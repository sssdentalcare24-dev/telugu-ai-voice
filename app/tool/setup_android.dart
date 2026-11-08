// Run once after `flutter create`:   dart run tool/setup_android.dart [--allow-http]
//
// Adds what this app needs to the generated Android project:
//   * INTERNET + RECORD_AUDIO permissions (release builds need INTERNET explicitly)
//   * the "Telugu AI Voice" app name and launcher icon
//   * package-visibility entries: open audio links in the browser, use the phone's TTS engine
//   * cleartext HTTP for DEBUG builds (local server at http://10.0.2.2:8000)
//   * --allow-http: also allow HTTP in RELEASE builds, for testing against a PC on Wi-Fi.
//     Do not use it for a Play Store build; production servers must use HTTPS.
// Safe to run more than once.
import 'dart:io';

void main(List<String> args) {
  final allowHttp = args.contains('--allow-http');
  final mainManifest = File('android/app/src/main/AndroidManifest.xml');
  final debugManifest = File('android/app/src/debug/AndroidManifest.xml');
  if (!mainManifest.existsSync()) {
    stderr.writeln(
      'android/ not found. First run:  '
      'flutter create --platforms=android,web --org com.teluguaivoice --project-name telugu_ai_voice .',
    );
    exit(1);
  }

  var m = mainManifest.readAsStringSync();
  final original = m;

  for (final permission in ['android.permission.INTERNET', 'android.permission.RECORD_AUDIO']) {
    if (!m.contains(permission)) {
      m = m.replaceFirst('<application', '<uses-permission android:name="$permission"/>\n    <application');
    }
  }

  final label = RegExp(r'android:label="[^"]*"');
  if (label.hasMatch(m) && !m.contains('android:label="Telugu AI Voice"')) {
    m = m.replaceFirst(label, 'android:label="Telugu AI Voice"');
  }

  final queries = <String, String>{
    'android.intent.action.VIEW': '''
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="http" />
        </intent>''',
    'android.intent.action.TTS_SERVICE': '''
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>''',
  };
  for (final entry in queries.entries) {
    if (m.contains(entry.key)) continue;
    if (m.contains('<queries>')) {
      m = m.replaceFirst('<queries>', '<queries>\n${entry.value}');
    } else {
      m = m.replaceFirst('</manifest>', '    <queries>\n${entry.value}\n    </queries>\n</manifest>');
    }
  }

  if (allowHttp && !m.contains('usesCleartextTraffic')) {
    m = m.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }

  if (m != original) {
    mainManifest.writeAsStringSync(m);
    stdout.writeln('Updated ${mainManifest.path}${allowHttp ? ' (HTTP allowed for testing)' : ''}');
  } else {
    stdout.writeln('${mainManifest.path} already set up');
  }

  if (debugManifest.existsSync()) {
    final d = debugManifest.readAsStringSync();
    if (!d.contains('usesCleartextTraffic')) {
      debugManifest.writeAsStringSync(
        d.replaceFirst('</manifest>', '    <application android:usesCleartextTraffic="true" />\n</manifest>'),
      );
      stdout.writeln('Updated ${debugManifest.path} (HTTP allowed in debug builds)');
    }
  }

  // Launcher icon (navy + gold microphone).
  final icons = Directory('tool/android_res');
  if (icons.existsSync()) {
    for (final entity in icons.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.png')) {
        final relative = entity.path.substring(icons.path.length + 1);
        final target = File('android/app/src/main/res/$relative');
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
      }
    }
    stdout.writeln('Launcher icons installed');
  }
  stdout.writeln('Android setup complete.');
}
