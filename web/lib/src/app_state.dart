// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// App-wide state. Plays the role Valhalla's AuthService played, but the
/// server now owns authentication; this only remembers the current session.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    this.api.onServedBy = (pod) {
      if (pod != servedBy) {
        servedBy = pod;
        notifyListeners();
      }
    };
  }

  final ApiClient api;
  Session? session;

  /// Last Kubernetes pod that answered a request.
  String? servedBy;

  Future<void> signIn(String email, String password) async {
    session = await api.login(email, password);
    notifyListeners();
  }

  Future<void> signUp({
    required String organization,
    required String name,
    required String email,
    required String password,
  }) async {
    session = await api.signup(
      organization: organization,
      name: name,
      email: email,
      password: password,
    );
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } catch (_) {
      // Signing out locally still makes sense if the server call fails.
    }
    session = null;
    notifyListeners();
  }
}
