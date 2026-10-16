import 'package:fasty/auth/email_confirmation_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmailConfirmationLink.tryParse', () {
    test('parses a valid Fasty confirmation URL', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/confirm-email'
          '?email=person%40example.com'
          '&token=encoded%2Bconfirmation%2Ftoken',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'encoded+confirmation/token');
    });

    test('continues to parse a web confirmation URL', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'https://app.example.com/confirm-email'
          '?email=person%40example.com'
          '&token=confirmation-token',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'confirmation-token');
    });

    test('accepts a trailing slash', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/confirm-email/'
          '?email=person%40example.com'
          '&token=confirmation-token',
        ),
      );

      expect(link, isNotNull);
      expect(link!.email, 'person@example.com');
      expect(link.token, 'confirmation-token');
    });

    test('rejects a different path', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/login'
          '?email=person%40example.com'
          '&token=confirmation-token',
        ),
      );

      expect(link, isNull);
    });

    test('rejects a missing email', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/confirm-email'
          '?token=confirmation-token',
        ),
      );

      expect(link, isNull);
    });

    test('rejects a missing token', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/confirm-email'
          '?email=person%40example.com',
        ),
      );

      expect(link, isNull);
    });

    test('rejects blank parameters', () {
      final link = EmailConfirmationLink.tryParse(
        Uri.parse(
          'fasty://account/confirm-email'
          '?email=%20%20&token=%20',
        ),
      );

      expect(link, isNull);
    });
  });
}
