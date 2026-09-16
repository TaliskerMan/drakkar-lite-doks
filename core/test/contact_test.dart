import 'package:drakkar_core/drakkar_core.dart';
import 'package:test/test.dart';

void main() {
  group('Contact', () {
    test('round-trips through JSON', () {
      const contact = Contact(
        id: '7d1f0c1e-7c4c-4a8e-9a55-2b1f7c1f0a11',
        firstName: 'Ada',
        lastName: 'Lovelace',
        companyName: 'Analytical Engines',
        workEmail: 'ada@example.com',
        escalationContact: true,
      );
      final copy = Contact.fromJson(contact.toJson());
      expect(copy.id, contact.id);
      expect(copy.fullName, 'Ada Lovelace');
      expect(copy.escalationContact, isTrue);
      expect(copy.validate(), isEmpty);
    });

    test('blank optional strings become null', () {
      final c = Contact.fromJson({'firstName': 'A', 'lastName': 'B', 'title': '  '});
      expect(c.title, isNull);
    });

    test('requires names and valid emails', () {
      final c = Contact.fromJson({'firstName': ' ', 'lastName': '', 'workEmail': 'nope'});
      expect(c.validate(), hasLength(3));
    });
  });

  group('SecurityValidator (ported from Valhalla)', () {
    test('generated passwords satisfy the complexity rules', () {
      for (var i = 0; i < 50; i++) {
        final pw = SecurityValidator.generatePassword();
        expect(SecurityValidator.validatePasswordComplexity(pw), isNull);
      }
    });

    test('rejects weak passwords', () {
      expect(SecurityValidator.validatePasswordComplexity('short'), isNotNull);
      expect(SecurityValidator.validatePasswordComplexity('alllowercase1'), isNotNull);
    });
  });

  test('isValidEmail', () {
    expect(isValidEmail('chuck@example.com'), isTrue);
    expect(isValidEmail('not-an-email'), isFalse);
    expect(isValidEmail(null), isFalse);
  });
}
