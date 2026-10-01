import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opengym/data/api_client.dart';

void main() {
  group('normalizeServerUrl', () {
    test('accepts https origins and normalises them', () {
      expect(normalizeServerUrl('https://OpenGym.Example.workers.dev/'), 'https://opengym.example.workers.dev');
      expect(normalizeServerUrl('  opengym.example.com  '), 'https://opengym.example.com');
      expect(normalizeServerUrl('https://gym.example.com:8443'), 'https://gym.example.com:8443');
    });

    test('reduces a pasted connector URL to the origin', () {
      expect(normalizeServerUrl('https://gym.example.com/mcp'), 'https://gym.example.com');
    });

    test('allows plain http only for local development', () {
      expect(normalizeServerUrl('http://localhost:8787'), 'http://localhost:8787');
      expect(normalizeServerUrl('http://127.0.0.1:8787/'), 'http://127.0.0.1:8787');
      expect(normalizeServerUrl('http://10.0.2.2:8787'), 'http://10.0.2.2:8787');
      expect(() => normalizeServerUrl('http://gym.example.com'), throwsFormatException);
      expect(() => normalizeServerUrl('ftp://gym.example.com'), throwsFormatException);
      expect(() => normalizeServerUrl(''), throwsFormatException);
    });
  });

  group('ApiClient', () {
    late List<http.Request> requests;
    ApiClient client(
      Future<http.Response> Function(http.Request r) handler, {
      String? token = 'tok',
      Duration? timeout,
    }) {
      requests = [];
      return ApiClient(
        baseUrl: 'https://gym.example.com',
        token: token,
        timeout: timeout,
        timeZone: () async => 'Europe/Madrid',
        httpClient: MockClient((r) {
          requests.add(r);
          return handler(r);
        }),
      );
    }

    http.Response json(int status, Object body) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    test('sends the bearer token, X-Timezone and JSON', () async {
      final api = client((_) async => json(200, {'seq': 3, 'epoch': 9, 'serverTime': 1, 'hasMore': false}));
      final res = await api.push({'since': 0, 'workouts': []});
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://gym.example.com/api/sync');
      expect(r.headers['Authorization'], 'Bearer tok');
      expect(r.headers['X-Timezone'], 'Europe/Madrid');
      expect(r.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(r.body), {'since': 0, 'workouts': []});
      expect(res.seq, 3);
      expect(res.epoch, 9);
    });

    test('pull is a GET with since', () async {
      final api = client((_) async => json(200, {'seq': 0, 'epoch': 1, 'serverTime': 1}));
      await api.pull(120);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters['since'], '120');
      expect(requests.single.headers.containsKey('Content-Type'), isFalse);
    });

    test('a 2xx sync answer without the counters is a server error, never seq 0 / epoch 0', () async {
      for (final body in [
        http.Response('<html>Sign in</html>', 200, headers: {'content-type': 'text/html'}),
        http.Response('', 200),
        json(200, {'docs': []}),
      ]) {
        final api = client((_) async => body);
        await expectLater(api.pull(5), throwsA(isA<ServerException>()));
        await expectLater(api.push({'since': 5}), throwsA(isA<ServerException>()));
      }
    });

    test('login sends no token and returns the new one', () async {
      final api = client((_) async => json(200, {'token': 'new', 'deviceId': 'd1'}), token: null);
      final res = await api.login(password: 'pw', deviceName: 'Mi Android');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(requests.single.body), {'password': 'pw', 'deviceName': 'Mi Android'});
      expect(res.token, 'new');
      expect(res.deviceId, 'd1');
    });

    test('maps statuses to typed errors with the server message', () async {
      Future<void> expectError<T extends ApiException>(int status, Map<String, Object?> body, [String? message]) async {
        final api = client((_) async => json(status, body));
        await expectLater(api.pull(0), throwsA(isA<T>().having((e) => e.message, 'message', message ?? isNotEmpty)));
      }

      await expectError<UnauthorizedException>(401, {'error': 'No autorizado'}, 'No autorizado');
      await expectError<ConflictException>(409, {
        'error': 'Ya resuelta',
        'proposal': {'id': 'p1'},
      }, 'Ya resuelta');
      await expectError<RateLimitedException>(429, {});
      await expectError<ServerException>(500, {'error': 'Servidor mal configurado'}, 'Servidor mal configurado');
      await expectError<RequestException>(415, {});
    });

    test('a 409 keeps the body (the server proposal)', () async {
      final api = client(
        (_) async => json(409, {
          'error': 'x',
          'proposal': {'id': 'p1', 'status': 'applied'},
        }),
      );
      try {
        await api.resolveProposal('p1', {'outcome': 'applied'});
        fail('expected a conflict');
      } on ConflictException catch (e) {
        expect(e.body['proposal'], {'id': 'p1', 'status': 'applied'});
      }
    });

    test('network failures and timeouts are OfflineException', () async {
      final api = client((_) async => throw http.ClientException('no route'));
      await expectLater(api.pull(0), throwsA(isA<OfflineException>()));
      final slow = client((_) => Completer<http.Response>().future, timeout: const Duration(milliseconds: 20));
      await expectLater(slow.pull(0), throwsA(isA<OfflineException>()));
    });

    test('devices accepts a bare list or {devices}', () async {
      final device = {'id': 'd1', 'name': 'Pixel', 'createdAt': 1, 'lastSeenAt': 2, 'current': true};
      expect((await client((_) async => json(200, [device])).devices()).single.current, isTrue);
      expect(
        (await client(
          (_) async => json(200, {
            'devices': [device],
          }),
        ).devices()).single.name,
        'Pixel',
      );
    });

    test('resolve and revert post to the proposal routes', () async {
      final api = client(
        (_) async => json(200, {
          'proposal': {'id': 'p 1', 'kind': 'plan', 'status': 'applied'},
          'docs': [
            {
              'key': 'plan',
              'data': {'routines': []},
              'updatedAt': 5,
              'seq': 9,
            },
          ],
        }),
      );
      final res = await api.resolveProposal('p 1', {'outcome': 'applied'});
      expect(requests.single.url.path, '/api/proposals/p%201/resolve');
      expect(res.proposal.status, 'applied');
      expect(res.docs.single.seq, 9);
      await api.revertProposal('p 1', {'docs': []});
      expect(requests.last.url.path, '/api/proposals/p%201/revert');
    });
  });
}
