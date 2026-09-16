// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns true when [value] looks like an email address.
bool isValidEmail(String? value) =>
    value != null && value.length <= 254 && _email.hasMatch(value.trim());
