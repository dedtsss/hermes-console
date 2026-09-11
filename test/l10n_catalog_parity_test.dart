import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _readCatalog(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> _messageKeys(Map<String, Object?> catalog) =>
    catalog.keys.where((key) => !key.startsWith('@')).toSet();

Set<String> _placeholders(Object? message) => RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)\s*(?:\}|,)',
).allMatches(message as String).map((match) => match.group(1)!).toSet();

/// Returns the names, formats, and plural/select arms of every ICU argument.
/// This deliberately ignores translated prose while making an incompatible ICU
/// message (including a missing plural arm) fail deterministically.
List<String> _icuShape(String message) {
  final result = <String>[];
  for (var index = 0; index < message.length; index++) {
    if (message[index] != '{') continue;
    var depth = 1;
    var end = index + 1;
    while (end < message.length && depth > 0) {
      if (message[end] == '{') depth++;
      if (message[end] == '}') depth--;
      end++;
    }
    if (depth != 0) {
      result.add('unclosed@$index');
      break;
    }
    final argument = message.substring(index + 1, end - 1);
    final head = RegExp(r'^\s*([A-Za-z][A-Za-z0-9_]*)(?:\s*,\s*([A-Za-z]+))?')
        .firstMatch(argument);
    if (head != null) {
      final name = head.group(1)!;
      final kind = head.group(2) ?? 'argument';
      final arms = RegExp(r'([=A-Za-z]+)\s*\{').allMatches(argument)
          .map((match) => match.group(1)!)
          .toList()
        ..sort();
      result.add('$name:$kind:${arms.join(',')}');
    }
    index = end - 1;
  }
  return result;
}

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
      expect(
        _icuShape(es[key] as String),
        _icuShape(en[key] as String),
        reason: 'ICU structure of $key must match EN/ES',
      );
    }
  });

  test(
    'Russian fully implements the English canonical message contract',
    () {
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
          _icuShape(ru[key] as String),
          _icuShape(en[key] as String),
          reason: 'ICU structure of $key must match EN/RU',
        );
      }
    },
  );

  test(
    'Notificaciones conserva la misma mayúscula inicial que cada pantalla',
    () {
      final es = _readCatalog('lib/l10n/app_es.arb');
      final en = _readCatalog('lib/l10n/app_en.arb');

      expect(es['notifTitle'], 'Notificaciones');
      expect(en['notifTitle'], 'Notifications');
    },
  );

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

    expect(es['voiceModeServerSub'], contains('no cambia al móvil'));
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
