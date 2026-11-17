import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/opencode_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const Map<String, Object?> _goStatus = {
  'subscriberUserId': 'acc_01KXDVHYS30679FFKQ113J8FWY',
  'product': 'go',
  'useBalance': false,
  'access': {
    'startsAt': '2026-09-26T12:06:25.000Z',
    'endsAt': '2026-10-26T12:06:25.000Z',
    'cancelAtPeriodEnd': false,
    'meters': {
      'fiveHour': {
        'startsAt': '2026-09-26T12:27:01.804Z',
        'resetsAt': '2026-09-26T17:27:01.804Z',
        'limitMicroCents': '1200000000',
        'usedMicroCents': '7632295',
      },
      'week': {
        'startsAt': '2026-09-21T00:00:00.000Z',
        'resetsAt': '2026-09-28T00:00:00.000Z',
        'limitMicroCents': '3000000000',
        'usedMicroCents': '7632295',
      },
      'month': {
        'limitMicroCents': '6000000000',
        'usedMicroCents': '7632295',
      },
    },
  },
};

const Map<String, Object?> _requestLogs = {
  'items': [
    {
      'id': 'c34d84dc-d6e8-4d09-8a48-55d636a772d2',
      'startedAt': 1790427391447,
      'category': 'inference',
      'product': 'go',
      'sessionID': '1e2a34d4-f057-45bd-8f0f-21c05481fa00',
      'serviceAPIKeyID': 'sk_01M3ESWS60E7J9STN1MHFQPYRM',
      'model': 'deepseek-v4.1-flash',
      'provider': 'opencode',
      'inputTokens': 2480,
      'outputTokens': 1273,
      'reasoningTokens': 629,
      'cacheReadTokens': 130944,
      'cacheWriteTokens': 0,
      'cost': 0.00152863,
    },
    {
      'id': '287fbd65-0000-0000-0000-000000000000',
      'startedAt': 1790427749237,
      'category': 'api',
      'serviceAPIKeyID': null,
      'model': null,
      'inputTokens': 0,
      'cost': 0,
    },
    {
      'id': '9d42a3c0-20b4-4354-9bfe-82d7a2f36058',
      'startedAt': 1790427740000,
      'category': 'inference',
      'product': 'go',
      'sessionID': '',
      'serviceAPIKeyID': 'sk_01M3ESWS60E7J9STN1MHFQPYRM',
      'model': 'kimi-k3',
      'provider': 'opencode',
      'inputTokens': 100,
      'outputTokens': 20,
      'reasoningTokens': 0,
      'cacheReadTokens': 0,
      'cacheWriteTokens': 4096,
      'cost': '0.0000387',
    },
  ],
  'nextCursor': '{"v":2,"kind":"list","until":1790427382939}',
  'until': 1790427382939,
  'retentionDays': 30,
};

void main() {
  group('cookie normalization', () {
    test('bare token gets the session cookie name', () {
      expect(
        OpenCodeApi.buildCookieHeader('st_abc'),
        '__Host-console_session=st_abc',
      );
    });

    test('full cookie / legacy auth / Cookie: prefix pass through', () {
      expect(
        OpenCodeApi.buildCookieHeader('__Host-console_session=st_abc'),
        '__Host-console_session=st_abc',
      );
      expect(OpenCodeApi.buildCookieHeader('auth=Fe26.2'), 'auth=Fe26.2');
      expect(
        OpenCodeApi.buildCookieHeader('a=1; auth=Fe26.2; b=2'),
        'auth=Fe26.2',
      );
      expect(
        OpenCodeApi.buildCookieHeader('Cookie: a=1; __Host-console_session=st_x'),
        '__Host-console_session=st_x',
      );
    });

    test('extractSessionCookie finds HttpOnly session pair', () {
      expect(
        OpenCodeApi.extractSessionCookie(
          'foo=1; __Host-console_session=st_x; bar=2',
        ),
        '__Host-console_session=st_x',
      );
      expect(OpenCodeApi.extractSessionCookie('foo=1'), isNull);
    });
  });

  group('quota parsing', () {
    test('parses the three windows with desktop parity', () {
      final now = DateTime.utc(2026, 9, 26, 12, 56, 25);
      final windows = OpenCodeApi.parseGoStatus(_goStatus, now: now);
      expect(windows, hasLength(3));
      expect(windows[0].label, '5h Rolling');
      expect(windows[0].used, 0.64);
      expect(windows[0].remaining, 99.36);
      expect(windows[0].resetInSec, 16236);
      expect(windows[1].label, 'Weekly');
      expect(windows[1].used, 0.25);
      expect(windows[2].label, 'Monthly');
      expect(windows[2].used, 0.13);
      expect(
        windows[2].resetAt?.toIso8601String(),
        '2026-10-26T12:06:25.000Z',
      );
      expect(windows[2].resetInSec, 2589000);
    });

    test('empty payloads produce no windows', () {
      expect(OpenCodeApi.parseGoStatus(null), isEmpty);
      expect(OpenCodeApi.parseGoStatus(const {}), isEmpty);
      expect(
        OpenCodeApi.parseGoStatus(const {
          'access': {'meters': <String, Object?>{}},
        }),
        isEmpty,
      );
    });
  });

  group('request log parsing', () {
    test('skips incomplete and non-inference items', () {
      final page = OpenCodeApi.parseRequestLogs({
        'items': [
          {'id': '', 'startedAt': 1, 'category': 'inference'},
          {'id': 'a', 'category': 'inference'},
          {'id': 'b', 'startedAt': 1, 'category': 'api'},
          {'id': 'c', 'startedAt': 1, 'category': 'inference', 'model': 'm'},
        ],
      });
      expect(page.records.map((record) => record.usgId), ['c']);
    });

    test('filters api calls, parses string cost and cache-write column', () {
      final page = OpenCodeApi.parseRequestLogs(_requestLogs);
      expect(page.records, hasLength(2));
      expect(page.retentionDays, 30);
      expect(page.nextCursor, contains('until'));
      final first = page.records.first;
      expect(first.model, 'deepseek-v4.1-flash');
      expect(first.inputTokens, 2480);
      expect(first.outputTokens, 1273);
      expect(first.reasoningTokens, 629);
      expect(first.cacheReadTokens, 130944);
      expect(first.cacheWrite5mTokens, 0);
      expect(first.costRaw, 152863);
      expect(first.costUsd, closeTo(0.00152863, 1e-12));
      expect(first.sessionId, startsWith('1e2a'));
      expect(first.plan, 'go');
      final second = page.records.last;
      expect(second.costRaw, 3870);
      expect(second.costUsd, closeTo(0.0000387, 1e-12));
      expect(second.cacheWrite5mTokens, 4096);
      expect(second.cacheWrite1hTokens, 0);
      expect(second.sessionId, isEmpty);
    });
  });

  group('HTTP client', () {
    test('sends Cookie and x-org-id, parses /orgs list', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/console/api/orgs');
        expect(request.headers['Cookie'], '__Host-console_session=st_test');
        return http.Response(
          jsonEncode([
            {'id': 'wrk_abc', 'name': 'Main'},
            {'id': 'wrk_def', 'name': 'Team'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = OpenCodeApi(client: client);
      final refs = await api.fetchWorkspaceRefs('st_test');
      expect(refs, hasLength(2));
      expect(refs.first.id, 'wrk_abc');
      expect(await api.resolveWorkspaceId('Team', 'st_test'), 'wrk_def');
      api.close();
    });

    test('401 becomes AuthException without retry', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('unauthorized', 401);
      });
      final api = OpenCodeApi(client: client);
      await expectLater(
        api.fetchUsagePage('st_test', 'wrk_abc'),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 1);
      api.close();
    });

    test('usage page sends limit/since/cursor and parses records', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/console/api/request-logs');
        expect(request.url.queryParameters['limit'], '100');
        expect(request.url.queryParameters['since'], '123');
        expect(request.url.queryParameters['cursor'], 'c0');
        expect(
          request.headers['x-org-id'] ?? request.headers['X-Org-Id'],
          'wrk_abc',
        );
        return http.Response(jsonEncode(_requestLogs), 200);
      });
      final api = OpenCodeApi(client: client);
      final page = await api.fetchUsagePage(
        'st_test',
        'wrk_abc',
        cursor: 'c0',
        sinceMs: 123,
      );
      expect(page.records, hasLength(2));
      api.close();
    });
  });
}
