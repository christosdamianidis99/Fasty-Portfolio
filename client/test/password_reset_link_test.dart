import 'package:fasty/auth/password_reset_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordResetLink.tryParse', () {
    test('parses a valid Fasty reset URL', () {
      final link = PasswordResetLink.tryParse(
        Uri.parse(
          'fasty://account/reset-password'
          '?email=person%40example.com'
          '&token=encoded%2Breset%2Ftoken',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'encoded+reset/token');
    });

    test('continues to parse a web reset URL', () {
      final link = PasswordResetLink.tryParse(
        Uri.parse(
          'https://app.example.com/reset-password'
          '?email=person%40example.com'
          '&token=reset-token',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'reset-token');
    });

    test('accepts a trailing slash', () {
      final link = PasswordResetLink.tryParse(
        Uri.parse(
          'fasty://account/reset-password/'
          '?email=person%40example.com'
          '&token=reset-token',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'reset-token');
    });

    test('rejects a different path', () {
      final link = PasswordResetLink.tryParse(
        Uri.parse(
          'fasty://account/login'
          '?email=person%40example.com'
          '&token=reset-token',
        ),
      );

      expect(link, isNull);
    });

    test('rejects missing parameters', () {
      expect(
        PasswordResetLink.tryParse(
          Uri.parse(
            'fasty://account/reset-password'
            '?email=person%40example.com',
          ),
        ),
        isNull,
      );

      expect(
        PasswordResetLink.tryParse(
          Uri.parse(
            'fasty://account/reset-password'
            '?token=reset-token',
          ),
        ),
        isNull,
      );
    });

    test('rejects blank parameters', () {
      final link = PasswordResetLink.tryParse(
        Uri.parse(
          'fasty://account/reset-password'
          '?email=%20&token=%20',
        ),
      );

      expect(link, isNull);
    });
  });
}
