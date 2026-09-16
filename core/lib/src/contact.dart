// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Ported from Valhalla's lib/models/contact.dart. Differences:
//  * `id` is a UUID string (non-guessable in URLs), not an integer.
//  * `escalationContact` is a bool instead of 'Y'/'N'.
//  * JSON (camelCase) is the wire format; the server maps to snake_case columns.

import 'validation.dart';

/// A contact record belonging to one tenant (organization).
class Contact {
  /// Creates a [Contact].
  const Contact({
    required this.firstName,
    required this.lastName,
    this.id,
    this.title,
    this.function,
    this.companyName,
    this.workEmail,
    this.personalEmail,
    this.phoneNumber,
    this.products,
    this.escalationContact = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Builds a [Contact] from API JSON.
  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String?,
      firstName: (json['firstName'] as String? ?? '').trim(),
      lastName: (json['lastName'] as String? ?? '').trim(),
      title: _text(json['title']),
      function: _text(json['function']),
      companyName: _text(json['companyName']),
      workEmail: _text(json['workEmail']),
      personalEmail: _text(json['personalEmail']),
      phoneNumber: _text(json['phoneNumber']),
      products: _text(json['products']),
      escalationContact: json['escalationContact'] as bool? ?? false,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  final String? id;
  final String firstName;
  final String lastName;
  final String? title;
  final String? function;
  final String? companyName;
  final String? workEmail;
  final String? personalEmail;
  final String? phoneNumber;
  final String? products;
  final bool escalationContact;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display name, e.g. "Ada Lovelace".
  String get fullName => '$firstName $lastName'.trim();

  /// Serializes to API JSON.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'title': title,
        'function': function,
        'companyName': companyName,
        'workEmail': workEmail,
        'personalEmail': personalEmail,
        'phoneNumber': phoneNumber,
        'products': products,
        'escalationContact': escalationContact,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  /// Validation messages; empty when the contact is valid.
  List<String> validate() {
    final errors = <String>[];
    if (firstName.isEmpty) errors.add('firstName is required.');
    if (lastName.isEmpty) errors.add('lastName is required.');
    if (firstName.length > 100 || lastName.length > 100) {
      errors.add('Names must be 100 characters or fewer.');
    }
    if (workEmail != null && !isValidEmail(workEmail)) {
      errors.add('workEmail is not a valid email address.');
    }
    if (personalEmail != null && !isValidEmail(personalEmail)) {
      errors.add('personalEmail is not a valid email address.');
    }
    return errors;
  }
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
