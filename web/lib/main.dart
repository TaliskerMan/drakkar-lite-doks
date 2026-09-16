// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/auth_screen.dart';
import 'src/contacts_screen.dart';

void main() {
  runApp(DrakkarApp(state: AppState()));
}

class DrakkarApp extends StatelessWidget {
  const DrakkarApp({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drakkar Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.blueGrey, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.session == null
            ? AuthScreen(state: state)
            : ContactsScreen(key: ValueKey(state.session!.token), state: state),
      ),
    );
  }
}
