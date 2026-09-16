// Copyright (C) 2026 Chuck Talk <chuck@nordheim.online>
// This file is part of Drakkar, the SaaS edition of Valhalla.
//
// Condensed web version of Valhalla's contact_dashboard.dart + the audit
// section of admin_dashboard.dart, backed by the API instead of SQLite.

import 'dart:async';

import 'package:drakkar_core/drakkar_core.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_state.dart';
import 'served_by_footer.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.people_outline), text: 'Contacts'),
      if (session.canWrite) const Tab(icon: Icon(Icons.history), text: 'Audit log'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Drakkar Lite — ${session.tenantName}'),
          bottom: TabBar(tabs: tabs),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text(session.email)),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: state.signOut,
            ),
          ],
        ),
        bottomNavigationBar: ServedByFooter(state: state),
        body: TabBarView(
          children: [
            _ContactsTab(state: state),
            if (session.canWrite) _AuditTab(api: state.api),
          ],
        ),
      ),
    );
  }
}

class _ContactsTab extends StatefulWidget {
  const _ContactsTab({required this.state});

  final AppState state;

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Contact> _contacts = const [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.state.api;
  bool get _canWrite => widget.state.session?.canWrite ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // The first call comes from initState, where _loading is already true,
    // so setState is skipped there.
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _api.contacts(query: _search.text.trim());
      if (mounted) setState(() => _contacts = items);
    } on ApiError catch (e) {
      if (e.status == 401) {
        await widget.state.signOut();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _add() async {
    final contact = await showDialog<Contact>(
      context: context,
      builder: (_) => const _ContactDialog(),
    );
    if (contact == null) return;
    try {
      await _api.createContact(contact);
      await _load();
    } catch (e) {
      _snack('Could not add contact: $e');
    }
  }

  Future<void> _delete(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text(contact.fullName),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteContact(contact.id!);
      await _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add contact'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name, company or email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh (watch "served by" change)',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _contacts.isEmpty && !_loading
                ? const Center(child: Text('No contacts yet.'))
                : ListView.separated(
                    itemCount: _contacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = _contacts[i];
                      final subtitle = [c.title, c.companyName, c.workEmail]
                          .whereType<String>()
                          .join(' · ');
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(c.firstName.isEmpty ? '?' : c.firstName[0].toUpperCase()),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(c.fullName)),
                            if (c.escalationContact) ...[
                              const SizedBox(width: 8),
                              const Chip(label: Text('Escalation'), visualDensity: VisualDensity.compact),
                            ],
                          ],
                        ),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: _canWrite
                            ? IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(c),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _escalation = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _company, _title, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.pop(
      context,
      Contact(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        companyName: opt(_company),
        title: opt(_title),
        workEmail: opt(_email),
        phoneNumber: opt(_phone),
        escalationContact: _escalation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add contact'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _first,
                  decoration: const InputDecoration(labelText: 'First name *'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _last,
                  decoration: const InputDecoration(labelText: 'Last name *'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Job title'),
                ),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Work email'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty || isValidEmail(v)) ? null : 'Invalid email',
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Escalation contact'),
                  value: _escalation,
                  onChanged: (v) => setState(() => _escalation = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _AuditTab extends StatefulWidget {
  const _AuditTab({required this.api});

  final ApiClient api;

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  late Future<List<AuditEntry>> _future = widget.api.auditLog();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = widget.api.auditLog();
        setState(() {
          _future = next;
        });
        await next;
      },
      child: FutureBuilder<List<AuditEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(children: [
              Padding(padding: const EdgeInsets.all(16), child: Text('${snapshot.error}')),
            ]);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final entries = snapshot.data!;
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              final when = e.createdAt.toString().substring(0, 19);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.bolt_outlined),
                title: Text('${e.action}${e.entityType == null ? '' : ' · ${e.entityType}'}'),
                subtitle: Text('${e.userName ?? 'system'} · $when'),
              );
            },
          );
        },
      ),
    );
  }
}
