import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/l10n/app_localizations_en.dart';
import 'package:hermes_android/l10n/app_localizations_es.dart';
import 'package:hermes_android/l10n/app_localizations_ru.dart';

Map<String, Object?> _readCatalog(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> _messageKeys(Map<String, Object?> catalog) =>
    catalog.keys.where((key) => !key.startsWith('@')).toSet();

Set<String> _placeholders(Object? message) =>
    RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\s*(?:\}|,)')
        .allMatches(message as String)
        .map((match) => match.group(1)!)
        .toSet();

void main() {
  test('Spanish retains the English canonical message contract', () {
    final en = _readCatalog('lib/l10n/app_en.arb');
    final es = _readCatalog('lib/l10n/app_es.arb');

    expect(_messageKeys(es), _messageKeys(en));
    for (final key in _messageKeys(en)) {
      expect(
        _placeholders(es[key]),
        _placeholders(en[key]),
        reason: 'Placeholders of $key must match EN/ES',
      );
    }
  });

  test('Russian implements all source keys and typed placeholder metadata', () {
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');
    final ru = _readCatalog('lib/l10n/app_ru.arb');

    expect(_messageKeys(ru), _messageKeys(en));
    expect(ru['@@locale'], 'ru');

    for (final key in _messageKeys(en)) {
      expect(
        (ru[key] as String).trim(),
        isNotEmpty,
        reason: 'Russian translation for $key must not be blank',
      );
      expect(
        _placeholders(ru[key]),
        _placeholders(en[key]),
        reason: 'Placeholders of $key must match EN/RU',
      );
      expect(
        (ru['@$key'] as Map<String, Object?>?)?['placeholders'],
        (es['@$key'] as Map<String, Object?>?)?['placeholders'],
        reason: 'Placeholder metadata of $key must match source ES/RU',
      );
    }
  });

  test('Russian generated catalog resolves new copy and typed plurals', () {
    final ru = StringsRu();
    expect(ru.commonCancel, 'Отмена');
    expect(ru.o2WelcomeTitle, 'Подключитесь к своему Hermes');
    expect(ru.chaBackgroundWorkRemaining(1), contains('1 фоновая задача'));
    expect(ru.chaBackgroundWorkRemaining(5), contains('5'));
  });

  test(
    'Notificaciones conserva la misma mayúscula inicial que cada pantalla',
    () {
      final es = _readCatalog('lib/l10n/app_es.arb');
      final en = _readCatalog('lib/l10n/app_en.arb');

      expect(es['notifTitle'], 'Notificaciones');
      expect(en['notifTitle'], 'Notifications');
    },
  );

  test('las tareas restantes usan singular y plural', () {
    expect(
      StringsEn().chaBackgroundWorkRemaining(1),
      'Could not stop everything: 1 background task remains',
    );
    expect(
      StringsEn().chaBackgroundWorkRemaining(2),
      'Could not stop everything: 2 background tasks remain',
    );
    expect(
      StringsEs().chaBackgroundWorkRemaining(1),
      'No se pudo detener todo: queda 1 tarea en segundo plano',
    );
    expect(
      StringsEs().chaBackgroundWorkRemaining(2),
      'No se pudo detener todo: quedan 2 tareas en segundo plano',
    );
  });

  test('el hint de voz explica barge-in sin pedir que Hermes termine', () {
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');

    expect(es['chaVoiceCanInterruptHint'], contains('interrumpir hablando'));
    expect(es['chaVoiceCanInterruptHint'], isNot(contains('Espera')));
    expect(en['chaVoiceCanInterruptHint'], contains('interrupt by speaking'));
    expect(en['chaVoiceCanInterruptHint'], isNot(contains('Wait')));
  });

  test('Servidor Hermes nunca promete cambiar a la voz local', () {
    final es = _readCatalog('lib/l10n/app_es.arb');
    final en = _readCatalog('lib/l10n/app_en.arb');

    expect(es['voiceModeServerSub'], contains('no cambia al teléfono'));
    expect(
      es['nativeVoiceConsentBody'],
      contains('no cambiará a la voz local'),
    );
    expect(
      es['voiceServerFallbackNote'],
      contains('No activa automáticamente'),
    );

    expect(en['voiceModeServerSub'], contains('never switches'));
    expect(
      en['nativeVoiceConsentBody'],
      contains('will not switch to local voice'),
    );
    expect(en['voiceServerFallbackNote'], contains('does not automatically'));
  });
}
