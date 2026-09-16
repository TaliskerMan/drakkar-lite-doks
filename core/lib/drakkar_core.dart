// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

/// Shared, platform-neutral code for Drakkar. No `dart:io`, no Flutter, so it
/// compiles for the server, the web client and (later) desktop builds.
library;

export 'src/contact.dart';
export 'src/security_validator.dart';
export 'src/validation.dart';
