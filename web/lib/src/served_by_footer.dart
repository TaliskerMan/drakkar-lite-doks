// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.

import 'package:flutter/material.dart';

import 'app_state.dart';

/// Shows which Kubernetes pod answered the last API call — the visible proof
/// that the Service is load-balancing across replicas.
class ServedByFooter extends StatelessWidget {
  const ServedByFooter({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final session = state.session;
        final parts = <String>[
          'Drakkar Lite',
          if (session != null) '${session.tenantName} · ${session.name} (${session.role})',
          'served by ${state.servedBy ?? '—'}',
        ];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(
            parts.join('   |   '),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
