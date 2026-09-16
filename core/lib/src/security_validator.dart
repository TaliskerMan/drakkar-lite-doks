// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Valhalla (copied unchanged into Drakkar Lite).
//
// Valhalla is licensed under the MIT License. See LICENSE for details.

import 'dart:math';

/// Utility class containing helper methods to enforce password complexity criteria
/// and to generate cryptographically strong secrets.
class SecurityValidator {
  /// Validates a password against complexity requirements.
  static String? validatePasswordComplexity(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!password.contains(RegExp('[A-Z]'))) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!password.contains(RegExp('[a-z]'))) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!password.contains(RegExp('[0-9]'))) {
      return 'Password must contain at least one number.';
    }
    return null; // Valid
  }

  static final Random _rng = Random.secure();

  static const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O
  static const String _lower = 'abcdefghijkmnpqrstuvwxyz'; // no l/o
  static const String _digits = '23456789'; // no 0/1
  static const String _symbols = r'!@#$%^&*-_=+';

  /// Generate a cryptographically strong password that always satisfies
  /// [validatePasswordComplexity] (it includes at least one upper, lower, and
  /// digit, plus a symbol). Uses [Random.secure].
  static String generatePassword({int length = 20}) {
    const all = _upper + _lower + _digits + _symbols;
    // Guarantee one of each required class first.
    final chars = <String>[
      _upper[_rng.nextInt(_upper.length)],
      _lower[_rng.nextInt(_lower.length)],
      _digits[_rng.nextInt(_digits.length)],
      _symbols[_rng.nextInt(_symbols.length)],
    ];
    while (chars.length < length) {
      chars.add(all[_rng.nextInt(all.length)]);
    }
    chars.shuffle(_rng);
    return chars.join();
  }

  /// Generate a cryptographically strong recovery key (uppercase/digit groups,
  /// e.g. `RK-7H2K-9QF4-...`). The plaintext is shown to the user once; only its
  /// bcrypt hash is stored.
  static String generateRecoveryKey({int groups = 4, int groupLen = 4}) {
    const alphabet = _upper + _digits;
    final buf = StringBuffer('RK');
    for (var g = 0; g < groups; g++) {
      buf.write('-');
      for (var index = 0; index < groupLen; index++) {
        buf.write(alphabet[_rng.nextInt(alphabet.length)]);
      }
    }
    return buf.toString();
  }
}
