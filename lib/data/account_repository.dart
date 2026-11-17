import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models.dart';
import 'settings_repository.dart';
import 'token_store.dart';

class AccountRepository {
  AccountRepository({
    required this.db,
    required this.tokens,
    required this.settings,
  });

  final Database db;
  final TokenStore tokens;
  final SettingsRepository settings;

  Future<List<Account>> listAccounts() async {
    final rows = await db.query('accounts', orderBy: 'id ASC');
    final result = <Account>[];
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt() ?? 0;
      final token = await tokens.read(id);
      result.add(
        Account.fromDbMap(
          row,
          hasToken: (token ?? '').trim().isNotEmpty,
        ),
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

  /// Adds an account, or returns an existing account holding the same token.
  Future<Account> addAccount({
    required String token,
    required String workspaceId,
    String? name,
    bool setActive = true,
  }) async {
    final normalized = token.trim();
    final existingAccounts = await listAccounts();
    for (final account in existingAccounts) {
      final existing = await tokens.read(account.id);
      if (existing != null && existing.trim() == normalized) {
        await saveWorkspace(
          account.id,
          hint: workspaceId,
          resolved: workspaceId,
        );
        if (setActive) await this.setActive(account.id);
        return (await getAccount(account.id))!;
      }
    }
    // Fresh install / re-login of the only account: fill the seeded empty row
    // instead of leaving an unused "Default" account next to the real one.
    if (existingAccounts.length == 1 && !existingAccounts.single.hasToken) {
      final only = existingAccounts.single;
      await tokens.write(only.id, normalized);
      await saveWorkspace(only.id, hint: workspaceId, resolved: workspaceId);
      if (name != null && name.trim().isNotEmpty) {
        await rename(only.id, name.trim());
      }
      if (setActive) await this.setActive(only.id);
      return (await getAccount(only.id))!;
    }
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM accounts'),
        ) ??
        0;
    final now = nowIso();
    final id = await db.insert('accounts', {
      'name': (name ?? '').trim().isEmpty ? 'User ${count + 1}' : name!.trim(),
      'workspace_id': workspaceId.isEmpty ? 'Default' : workspaceId,
      'resolved_workspace_id': workspaceId.isEmpty ? null : workspaceId,
      'created_at': now,
      'updated_at': now,
    });
    await tokens.write(id, normalized);
    if (setActive) await this.setActive(id);
    return (await getAccount(id))!;
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
