import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';
import 'settings_repository.dart';
import 'token_store.dart';

/// Thrown when a re-login cookie belongs to a different workspace. The caller
/// can offer to add it as a separate account instead of mixing histories.
class WorkspaceChangedException implements Exception {
  const WorkspaceChangedException({
    required this.currentWorkspaceId,
    required this.nextWorkspaceId,
  });

  final String currentWorkspaceId;
  final String nextWorkspaceId;

  @override
  String toString() =>
      'workSpace changed: $currentWorkspaceId -> $nextWorkspaceId';
}

class AccountRepository {
  AccountRepository({
    required this.db,
    required this.tokens,
    required this.settings,
  });

  final Database db;
  final TokenStore tokens;
  final SettingsRepository settings;

  Future<void> _writeQueue = Future<void>.value();

  /// Serializes addAccount so two quick login submissions cannot create
  /// duplicate rows for the same token/workspace pair.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _writeQueue;
    _writeQueue = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  Future<List<Account>> listAccounts() async {
    final rows = await db.query('accounts', orderBy: 'id ASC');
    final result = <Account>[];
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt() ?? 0;
      final token = await tokens.read(id);
      result.add(
        Account.fromDbMap(row, hasToken: (token ?? '').trim().isNotEmpty),
      );
    }
    return result;
  }

  Future<Account?> getAccount(int id) async {
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final token = await tokens.read(id);
    return Account.fromDbMap(
      rows.first,
      hasToken: (token ?? '').trim().isNotEmpty,
    );
  }

  Future<int?> activeAccountId() async {
    final configured = await settings.activeAccountId();
    if (configured != null && await _exists(configured)) return configured;
    final accounts = await listAccounts();
    for (final account in accounts) {
      if (account.hasToken) return account.id;
    }
    return accounts.isEmpty ? null : accounts.first.id;
  }

  Future<Account?> activeAccount() async {
    final id = await activeAccountId();
    if (id == null) return null;
    return getAccount(id);
  }

  Future<void> setActive(int accountId) async {
    await settings.setActiveAccountId(accountId);
  }

  Future<String?> tokenFor(int accountId) => tokens.read(accountId);

  Future<void> saveToken(int accountId, String token) async {
    await tokens.write(accountId, token);
    await db.update(
      'accounts',
      {'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  Future<void> saveWorkspace(
    int accountId, {
    required String hint,
    String? resolved,
  }) async {
    await db.update(
      'accounts',
      {
        'workspace_id': hint.isEmpty ? 'Default' : hint,
        if (resolved != null && resolved.isNotEmpty)
          'resolved_workspace_id': resolved,
        'updated_at': nowIso(),
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  /// Adds an account, or returns an existing account with the same token AND
  /// workspace. The same cookie used for a different workspace creates a new
  /// account row so their usage histories never mix.
  Future<Account> addAccount({
    required String token,
    required String workspaceId,
    String? name,
    bool setActive = true,
  }) {
    return _serialized(() async {
      final normalized = token.trim();
      final workspace = workspaceId.trim().isEmpty
          ? 'Default'
          : workspaceId.trim();
      final existingAccounts = await listAccounts();
      var tokenAlreadyExists = false;
      for (final account in existingAccounts) {
        final existingToken = await tokens.read(account.id);
        if (existingToken == null || existingToken.trim() != normalized) {
          continue;
        }
        tokenAlreadyExists = true;
        final existingWorkspace =
            account.resolvedWorkspaceId ?? account.workspaceHint;
        if (existingWorkspace != workspace) continue;
        // Same identity: refresh the workspace hint and optional name.
        await saveWorkspace(account.id, hint: workspace, resolved: workspace);
        if (name != null && name.trim().isNotEmpty) {
          await rename(account.id, name.trim());
        }
        if (setActive) await this.setActive(account.id);
        return (await getAccount(account.id))!;
      }
      // Fresh install / re-login of the only account: fill the seeded empty
      // row instead of leaving an unused "Default" account next to the real
      // one. This is only safe when there is no token yet.
      if (existingAccounts.length == 1 && !existingAccounts.single.hasToken) {
        final only = existingAccounts.single;
        await tokens.write(only.id, normalized);
        await saveWorkspace(only.id, hint: workspace, resolved: workspace);
        if (name != null && name.trim().isNotEmpty) {
          await rename(only.id, name.trim());
        }
        if (setActive) await this.setActive(only.id);
        return (await getAccount(only.id))!;
      }
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM accounts'),
          ) ??
          0;
      final now = nowIso();
      final trimmedName = (name ?? '').trim();
      final fallbackName = tokenAlreadyExists
          ? 'Workspace ${count + 1}'
          : 'User ${count + 1}';
      final id = await db.insert('accounts', {
        'name': trimmedName.isEmpty ? fallbackName : trimmedName,
        'workspace_id': workspace,
        'resolved_workspace_id': workspace == 'Default' ? null : workspace,
        'created_at': now,
        'updated_at': now,
      });
      try {
        await tokens.write(id, normalized);
        if (setActive) await this.setActive(id);
      } catch (_) {
        // A failed credential write must not leave an unusable account row.
        await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
        rethrow;
      }
      return (await getAccount(id))!;
    });
  }

  Future<bool> rename(int accountId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final safe = trimmed.length > 50 ? trimmed.substring(0, 50) : trimmed;
    final changed = await db.update(
      'accounts',
      {'name': safe, 'updated_at': nowIso()},
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return changed > 0;
  }

  Future<void> deleteAccount(int accountId) async {
    await db.transaction((txn) async {
      await txn.delete(
        'usage_records',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.delete(
        'usage_sync_state',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.delete('accounts', where: 'id = ?', whereArgs: [accountId]);
    });
    await tokens.delete(accountId);

    final active = await settings.activeAccountId();
    final remaining = await db.query(
      'accounts',
      columns: ['id'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (remaining.isEmpty) {
      final now = nowIso();
      final newId = await db.insert('accounts', {
        'name': 'Default',
        'workspace_id': 'Default',
        'created_at': now,
        'updated_at': now,
      });
      await settings.setActiveAccountId(newId);
    } else if (active == accountId || active == null) {
      await settings.setActiveAccountId(
        (remaining.first['id'] as num?)?.toInt(),
      );
    }
  }

  /// Desktop parity: sign out clears the token and that account's local data,
  /// but keeps the account row so it can be re-logged-in.
  Future<void> logoutAccount(int accountId) async {
    await tokens.delete(accountId);
    await db.transaction((txn) async {
      await txn.delete(
        'usage_records',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.delete(
        'usage_sync_state',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      await txn.update(
        'accounts',
        {'updated_at': nowIso()},
        where: 'id = ?',
        whereArgs: [accountId],
      );
    });
  }

  Future<bool> _exists(int accountId) async {
    final rows = await db.query(
      'accounts',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
