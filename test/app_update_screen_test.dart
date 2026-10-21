import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/app_update_screen.dart';
import 'package:hermes_android/core/services/app_update.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _UiUpdateService extends AppUpdateService {
  _UiUpdateService(this.actions);
  final List<String> actions;
  @override
  Future<AppUpdateRelease?> check() async {
    actions.add('check');
    return AppUpdateRelease(
      versionName: '1.3.0-ru.1',
      versionCode: 11631,
      notes: 'Изменения приложения',
      apkUrl: AppUpdateService.assetUrl(
        'v1.3.0-ru.1',
        AppUpdateService.apkName,
      ),
      sha256Hex: 'a' * 64,
      size: 100,
    );
  }

  @override
  Future<void> download(
    AppUpdateRelease release,
    void Function(double) progress,
  ) async {
    actions.add('download');
    progress(0.5);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(AppUpdateService.channel, null),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'RU ${dark ? 'dark' : 'light'} requires separate check, download, installer actions',
      (tester) async {
        final actions = <String>[];
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var installs = 0;
        messenger.setMockMethodCallHandler(AppUpdateService.channel, (
          call,
        ) async {
          actions.add(call.method);
          if (call.method == 'getInfo') {
            return {
              'supported': true,
              'versionName': '1.3.0',
              'versionCode': 11630,
            };
          }
          if (call.method == 'install') {
            installs++;
            return installs == 1 ? 'permission_required' : 'cancelled';
          }
          return null;
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: Strings.localizationsDelegates,
            supportedLocales: Strings.supportedLocales,
            theme: dark ? AppTheme.hermesRedDark : AppTheme.hermesRedLight,
            home: AppUpdateScreen(
              serviceFactory: () => _UiUpdateService(actions),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(actions, isEmpty);
        await tester.tap(find.text('Проверить обновление приложения'));
        await tester.pumpAndSettle();
        expect(actions, ['getInfo', 'check']);
        expect(find.textContaining('1.3.0-ru.1 (11631)'), findsOneWidget);
        expect(find.text('Открыть установщик Android'), findsNothing);
        await tester.ensureVisible(find.text('Скачать проверенный APK'));
        await tester.tap(find.text('Скачать проверенный APK'));
        await tester.pumpAndSettle();
        expect(actions, ['getInfo', 'check', 'download']);
        await tester.ensureVisible(find.text('Открыть установщик Android'));
        await tester.tap(find.text('Открыть установщик Android'));
        await tester.pumpAndSettle();
        expect(installs, 1);
        final settings = find.text('Открыть разрешение на установку');
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(actions.last, 'openSources');
        expect(
          installs,
          1,
          reason: 'Opening unknown-source settings never auto-installs',
        );
        await tester.ensureVisible(find.text('Открыть установщик Android'));
        await tester.tap(find.text('Открыть установщик Android'));
        await tester.pumpAndSettle();
        expect(installs, 2);
        expect(
          find.textContaining('Установка отменена или отклонена.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unsupported device never checks GitHub', (tester) async {
    final actions = <String>[];
    messenger.setMockMethodCallHandler(
      AppUpdateService.channel,
      (_) async => {'supported': false, 'versionCode': 9630},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedLight,
        home: AppUpdateScreen(serviceFactory: () => _UiUpdateService(actions)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for app updates'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    expect(find.textContaining('ARM64 Android device'), findsOneWidget);
  });
}
