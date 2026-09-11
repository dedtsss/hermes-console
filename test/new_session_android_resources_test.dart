import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortcut and widget use collision-free secret-free native actions', () {
    const action = 'io.github.dedtsss.hermesconsole.action.NEW_SESSION';
    final shortcut = File(
      'android/app/src/main/res/xml/shortcuts.xml',
    ).readAsStringSync();
    final contract = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'NewSessionLaunchContract.kt',
    ).readAsStringSync();
    final provider = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'NewSessionWidgetProvider.kt',
    ).readAsStringSync();
    final glance = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesConsoleGlanceWidget.kt',
    ).readAsStringSync();

    expect(shortcut, contains(action));
    expect(contract, contains(action));
    expect(provider, contains('HomeWidgetGlanceWidgetReceiver'));
    expect(glance, contains('NewSessionLaunchContract.newIntent'));
    expect(glance, contains('SOURCE_WIDGET'));
    expect(contract, contains('EXTRA_TARGET'));
    for (final actionName in [
      'ACTION_NEW_SESSION',
      'ACTION_NEW_SESSION_CAMERA',
      'ACTION_NEW_SESSION_GALLERY',
      'ACTION_NEW_SESSION_VOICE',
      'ACTION_OPEN_APP',
      'ACTION_OPEN_SESSION',
      'ACTION_OPEN_SETUP',
    ]) {
      expect(contract, contains('const val $actionName'));
    }
    final nativeActions = RegExp(
      r'const val ACTION_[A-Z_]+ = "([^"]+)"',
    ).allMatches(contract).map((match) => match.group(1)).whereType<String>();
    expect(nativeActions.toSet(), hasLength(nativeActions.length));
    expect(contract, contains('action = actionFor(kind, target)'));
    expect(contract, contains('.appendPath(kind.wireValue)'));
    expect(contract, contains('appendPath(target.wireValue)'));
    expect(contract, contains('matchesLaunchUri('));
    expect(contract, contains('.scheme("hermes-console-widget")'));
    expect(contract, contains('intent.data = null'));
    for (final target in ['COMPOSER', 'CAMERA', 'GALLERY', 'VOICE']) {
      expect(contract, contains(target));
    }
    expect(glance, contains('NewSessionLaunchTarget.COMPOSER'));
    expect(glance, contains('NewSessionLaunchTarget.VOICE'));
    expect(glance, contains('openSessionIntent'));

    final nativeSurface = '$shortcut\n$contract\n$provider\n$glance'
        .toLowerCase();
    expect(nativeSurface, isNot(contains('api_key')));
    expect(nativeSurface, isNot(contains('bearer')));
    expect(nativeSurface, isNot(contains('gateway_url')));
    expect(nativeSurface, isNot(contains('prompt_text')));
  });

  test('widget routes are neutralized before Flutter sees the intent', () {
    final activity = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'MainActivity.kt',
    ).readAsStringSync();
    final onCreate = activity.substring(
      activity.indexOf('override fun onCreate'),
      activity.indexOf('override fun onNewIntent'),
    );
    final onNewIntent = activity.substring(
      activity.indexOf('override fun onNewIntent'),
      activity.indexOf('override fun configureFlutterEngine'),
    );

    void expectConsumedBeforeSuper(String body, String superCall) {
      final parse = body.indexOf('NewSessionLaunchContract.parse(intent)');
      final neutralize = body.indexOf(
        'NewSessionLaunchContract.neutralize(intent)',
      );
      final delegate = body.indexOf(superCall);

      expect(parse, greaterThanOrEqualTo(0));
      expect(neutralize, greaterThan(parse));
      expect(delegate, greaterThan(neutralize));
    }

    expectConsumedBeforeSuper(onCreate, 'super.onCreate(savedInstanceState)');
    expectConsumedBeforeSuper(onNewIntent, 'super.onNewIntent(intent)');
  });

  test('Glance widgets expose three height-stable adaptive variants', () {
    final dashboardInfo = File(
      'android/app/src/main/res/xml/new_session_widget_info.xml',
    ).readAsStringSync();
    final compactInfo = File(
      'android/app/src/main/res/xml/hermes_widget_compact_info.xml',
    ).readAsStringSync();
    final controlInfo = File(
      'android/app/src/main/res/xml/hermes_widget_control_info.xml',
    ).readAsStringSync();
    final shortcut = File(
      'android/app/src/main/res/xml/shortcuts.xml',
    ).readAsStringSync();
    final controlPreview = File(
      'android/app/src/main/res/layout/new_session_widget_large.xml',
    ).readAsStringSync();
    final compactPreview = File(
      'android/app/src/main/res/layout/hermes_widget_compact_preview.xml',
    ).readAsStringSync();
    final dashboardPreview = File(
      'android/app/src/main/res/layout/hermes_widget_dashboard_preview.xml',
    ).readAsStringSync();
    final provider = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'NewSessionWidgetProvider.kt',
    ).readAsStringSync();
    final glance = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesConsoleGlanceWidget.kt',
    ).readAsStringSync();
    final state = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesWidgetState.kt',
    ).readAsStringSync();
    final expiryWorker = File(
      'android/app/src/main/kotlin/com/hermesagent/hermes_android/'
      'HermesWidgetExpiryWorker.kt',
    ).readAsStringSync();
    final appGradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final publisher = File(
      'lib/core/services/home_widget_publisher.dart',
    ).readAsStringSync();

    expect(shortcut, contains('android:icon="@mipmap/ic_launcher"'));
    expect(compactPreview, contains('192.168.1.20'));
    expect(compactPreview, contains('@string/hermes_widget_voice'));
    expect(controlPreview, contains('@string/hermes_widget_context'));
    expect(controlPreview, contains('<ProgressBar'));
    expect(dashboardPreview, contains('@string/hermes_widget_brand'));
    expect(dashboardPreview, contains('TTFT&#10;860ms'));
    for (final info in [dashboardInfo, compactInfo, controlInfo]) {
      expect(info, contains('android:updatePeriodMillis="0"'));
      expect(info, contains('android:resizeMode="horizontal"'));
      expect(info, contains('android:minResizeWidth'));
      expect(info, isNot(contains('android:minResizeHeight')));
    }
    expect(
      dashboardInfo,
      contains(
        'android:initialLayout="@layout/hermes_widget_dashboard_preview"',
      ),
    );
    expect(
      dashboardInfo,
      contains(
        'android:previewLayout="@layout/hermes_widget_dashboard_preview"',
      ),
    );
    expect(compactInfo, contains('android:targetCellWidth="2"'));
    expect(compactInfo, contains('android:targetCellHeight="1"'));
    expect(controlInfo, contains('android:targetCellWidth="4"'));
    expect(controlInfo, contains('android:targetCellHeight="1"'));
    expect(dashboardInfo, contains('android:targetCellWidth="4"'));
    expect(dashboardInfo, contains('android:targetCellHeight="2"'));
    expect(provider, contains('HomeWidgetGlanceWidgetReceiver'));
    expect(provider, contains('HermesConsoleGlanceWidget'));
    expect(provider, contains('HermesCompactWidgetProvider'));
    expect(provider, contains('HermesControlWidgetProvider'));
    expect(provider, contains('HermesWidgetVariant.COMPACT'));
    expect(provider, contains('HermesWidgetVariant.CONTROL'));
    expect(provider, contains('HermesWidgetVariant.DASHBOARD'));
    expect(glance, contains('SizeMode.Exact'));
    expect(glance, isNot(contains('SizeMode.Responsive')));
    expect(glance, contains('LocalSize.current'));
    expect(glance, contains('WidgetLayoutProfile'));
    expect(glance, contains('enum class WidgetContentTier'));
    expect(glance, contains('width < 100.dp || height < 54.dp'));
    expect(glance, contains('width < 190.dp || height < 100.dp'));
    expect(glance, contains('width < 270.dp || height < 190.dp'));
    expect(glance, contains('variantCeiling'));
    expect(glance, contains('enum class HermesWidgetVariant'));
    expect(glance, contains('CompactContent(context, state, colors, layout)'));
    expect(glance, contains('ControlContent(context, state, colors, layout)'));
    expect(glance, contains('ExpandedContent(context, state, colors, layout)'));
    expect(glance, contains('private fun ExpandedStatusPanel'));
    expect(glance, contains('.background(colors.surface)'));
    expect(glance, contains('ExpandedDetails(context, state, colors, roomy)'));
    expect(glance, contains('LinearProgressIndicator'));
    expect(glance, contains('firstTokenLatencyMs'));
    expect(state, contains('SCHEMA_VERSION'));
    expect(state, contains('cacheReadTokens'));
    expect(state, contains('firstTokenLatencyMs'));
    expect(state, contains('lastActivityAtMs'));
    expect(state, contains('fun staleAtMs()'));
    expect(state, contains('ATOMIC_SNAPSHOT'));
    expect(state, contains('JSONObject'));
    expect(state, contains('atomicSnapshotValues'));
    expect(glance, contains('HermesWidgetExpiryScheduler.replace'));
    expect(expiryWorker, contains('HomeWidgetPlugin.getData'));
    expect(expiryWorker, contains('OneTimeWorkRequestBuilder'));
    expect(expiryWorker, contains('ExistingWorkPolicy.REPLACE'));
    expect(expiryWorker, contains('NewSessionWidgetProvider::class.java'));
    expect(expiryWorker, contains('HermesCompactWidgetProvider::class.java'));
    expect(expiryWorker, contains('HermesControlWidgetProvider::class.java'));
    expect(expiryWorker, isNot(contains('PeriodicWorkRequest')));
    expect(expiryWorker, isNot(contains('NetworkType')));
    expect(appGradle, contains('androidx.work:work-runtime-ktx:2.11.2'));
    expect(glance, isNot(contains('RemoteViews')));
    expect(provider, isNot(contains('WorkManager')));
    expect(glance, isNot(contains('WorkManager')));
    expect(manifest, contains('android.app.shortcuts'));
    expect(manifest, contains('.NewSessionWidgetProvider'));
    expect(manifest, contains('.HermesCompactWidgetProvider'));
    expect(manifest, contains('.HermesControlWidgetProvider'));
    expect(manifest, contains('@xml/new_session_widget_info'));
    expect(manifest, contains('@xml/hermes_widget_compact_info'));
    expect(manifest, contains('@xml/hermes_widget_control_info'));
    expect(publisher, contains('HermesCompactWidgetProvider'));
    expect(publisher, contains('HermesControlWidgetProvider'));
  });

  test('widget has localized Material You and OLED-safe resources', () {
    final strings = File(
      'android/app/src/main/res/values/new_session_widget.xml',
    ).readAsStringSync();
    final spanish = File(
      'android/app/src/main/res/values-es/new_session_widget.xml',
    ).readAsStringSync();
    final dynamic = File(
      'android/app/src/main/res/values-v31/new_session_widget.xml',
    ).readAsStringSync();
    final dynamicNight = File(
      'android/app/src/main/res/values-night-v31/new_session_widget.xml',
    ).readAsStringSync();
    final background = File(
      'android/app/src/main/res/drawable/new_session_widget_background.xml',
    ).readAsStringSync();

    expect(strings, contains('name="new_session_widget_action"'));
    expect(spanish, contains('Nueva conversación'));
    expect(strings, contains('name="hermes_widget_session"'));
    expect(spanish, contains('name="hermes_widget_session"'));
    expect(strings, contains('name="hermes_widget_instance"'));
    expect(spanish, contains('name="hermes_widget_instance"'));
    expect(spanish, contains('>Instancia</string>'));
    expect(strings, contains('name="hermes_widget_agent"'));
    expect(spanish, contains('name="hermes_widget_agent"'));
    expect(strings, contains('name="hermes_widget_compact_name"'));
    expect(strings, contains('name="hermes_widget_control_name"'));
    expect(strings, contains('name="hermes_widget_dashboard_name"'));
    expect(spanish, contains('Hermes · Compacto'));
    expect(spanish, contains('Hermes · Controles'));
    expect(spanish, contains('Hermes · Panel'));
    expect(strings, contains('name="new_session_widget_composer_hint"'));
    expect(spanish, contains('Escribe a Hermes'));
    expect(dynamic, contains('@android:color/system_neutral1_50'));
    expect(dynamic, contains('@android:color/system_accent1_700'));
    expect(dynamicNight, contains('@android:color/black'));
    expect(dynamicNight, contains('@android:color/system_accent1_200'));
    expect(
      dynamic,
      contains('@android:dimen/system_app_widget_background_radius'),
    );
    expect(background, contains('@dimen/new_session_widget_corner_radius'));
  });
}
