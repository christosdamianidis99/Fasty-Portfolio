import 'package:fasty/database/account_database_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accountDatabaseName', () {
    test('normalizes email casing and whitespace', () {
      expect(
        accountDatabaseName('  Person@Example.com  '),
        accountDatabaseName('person@example.com'),
      );
    });

    test('creates different names for different accounts', () {
      expect(
        accountDatabaseName('first@example.com'),
        isNot(accountDatabaseName('second@example.com')),
      );
    });

    test('does not expose the email address', () {
      final name = accountDatabaseName('private.person@example.com');

      expect(name, startsWith('fasty_account_'));
      expect(name, isNot(contains('private')));
      expect(name, isNot(contains('example.com')));
    });

    test('rejects an empty email address', () {
      expect(() => accountDatabaseName('   '), throwsArgumentError);
    });
  });
}
