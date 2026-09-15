import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/pairing_link.dart';

void main() {
  group('PairingLink', () {
    test('roundtrip build → parse conserva todos los campos', () {
      const link = PairingLink(
        host: '100.101.102.103',
        port: 8642,
        token: 'test-pairing-token',
        label: 'Hermes lab',
        useHttps: true,
        dashboardUrl: 'http://100.101.102.103:9119',
        bridgeUrl: 'https://100.101.102.103/bridge-proxy',
        bridgeToken: 'bridge-only-token',
      );
      final parsed = PairingLink.tryParse(link.build())!;
      expect(parsed.host, link.host);
      expect(parsed.port, link.port);
      expect(parsed.token, link.token);
      expect(parsed.label, link.label);
      expect(parsed.useHttps, isTrue);
      expect(parsed.dashboardUrl, link.dashboardUrl);
      expect(parsed.bridgeUrl, link.bridgeUrl);
      expect(parsed.bridgeToken, link.bridgeToken);
    });

    test(
      'mínimo (solo host+port+token) válido; https/dashboard por defecto',
      () {
        const link = PairingLink(
          host: '192.168.1.10',
          port: 8642,
          token: 'abc',
        );
        final s = link.build();
        expect(s, startsWith('hermes://pair?'));
        final parsed = PairingLink.tryParse(s)!;
        expect(parsed.host, '192.168.1.10');
        expect(parsed.token, 'abc');
        expect(parsed.useHttps, isFalse);
        expect(parsed.label, isNull);
        expect(parsed.dashboardUrl, isNull);
        expect(parsed.bridgeUrl, isNull);
        expect(parsed.bridgeToken, isNull);
      },
    );

    test('genera un draft de conexión usable', () {
      const link = PairingLink(
        host: 'h.example',
        port: 9000,
        token: 'tok',
        label: 'Mi Hermes',
      );
      final c = link.toDraftConnection();
      expect(c.host, 'h.example');
      expect(c.port, 9000);
      expect(c.apiKey, 'tok');
      expect(c.label, 'Mi Hermes');
      expect(c.id, isNotEmpty);
    });

    test('label por defecto = host cuando falta', () {
      const link = PairingLink(host: 'h.example', port: 9000, token: 'tok');
      expect(link.toDraftConnection().label, 'h.example');
    });

    test('rechaza esquema/authority/campos inválidos', () {
      expect(PairingLink.tryParse(''), isNull);
      expect(
        PairingLink.tryParse('https://pair?host=h&port=1&token=t'),
        isNull,
      );
      expect(
        PairingLink.tryParse('hermes://other?host=h&port=1&token=t'),
        isNull,
      );
      expect(
        PairingLink.tryParse('hermes://pair?port=1&token=t'),
        isNull,
      ); // sin host
      expect(
        PairingLink.tryParse('hermes://pair?host=h&port=1'),
        isNull,
      ); // sin token
      expect(
        PairingLink.tryParse('hermes://pair?host=h&port=0&token=t'),
        isNull,
      );
      expect(
        PairingLink.tryParse('hermes://pair?host=h&port=99999&token=t'),
        isNull,
      );
      expect(
        PairingLink.tryParse('hermes://pair?host=h&port=abc&token=t'),
        isNull,
      );
    });

    test('parsea el formato que emite el comando del servidor', () {
      // Usa direcciones y credenciales reservadas exclusivamente para tests.
      const real =
          'hermes://pair?host=192.0.2.40&port=8642&token=test-pairing-token&label=hermes-lab';
      final p = PairingLink.tryParse(real)!;
      expect(p.host, '192.0.2.40');
      expect(p.port, 8642);
      expect(p.token, 'test-pairing-token');
      expect(p.label, 'hermes-lab');
    });

    test('tolera espacios y token con caracteres URL-sensibles', () {
      const tok = 'a+b/c=d_e-f';
      const link = PairingLink(host: 'h', port: 8642, token: tok);
      final parsed = PairingLink.tryParse('  ${link.build()}  ')!;
      expect(parsed.token, tok);
    });

    test('acepta nombres legacy del helper para Bridge', () {
      final parsed = PairingLink.tryParse(
        'hermes://pair?host=192.0.2.41&port=8642&token=gateway'
        '&bridge_url=https%3A%2F%2Fbridge.example%2Fbridge'
        '&bridgeToken=bridge-secret',
      );
      expect(parsed?.bridgeUrl, 'https://bridge.example/bridge');
      expect(parsed?.bridgeToken, 'bridge-secret');
    });
  });
}
