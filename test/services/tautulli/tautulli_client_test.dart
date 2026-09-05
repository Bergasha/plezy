import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/tautulli/tautulli_client.dart';

void main() {
  http.Response activityResponse(Map<String, dynamic> data, {String result = 'success', String? message}) =>
      http.Response(
        jsonEncode({
          'response': {'result': result, 'message': message, 'data': data},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('parses real-shaped get_activity sessions into TautulliSession models', () async {
    final client = TautulliClient(
      baseUrl: 'http://tautulli.example.com:8181',
      apiKey: 'secret',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v2');
        expect(request.url.queryParameters['apikey'], 'secret');
        expect(request.url.queryParameters['cmd'], 'get_activity');
        return activityResponse({
          'sessions': [
            {
              'session_key': '1',
              'friendly_name': 'Alice',
              'title': 'The Pilot',
              'grandparent_title': 'Some Show',
              'media_type': 'episode',
              'state': 'playing',
              'progress_percent': '42',
              'transcode_decision': 'transcode',
              'bandwidth': '4200',
              'quality_profile': '1080p',
            },
            {
              'session_key': '2',
              'friendly_name': 'Bob',
              'title': 'A Movie',
              'media_type': 'movie',
              'state': 'paused',
              'progress_percent': 10,
              'transcode_decision': 'direct play',
              'bandwidth': 8000,
            },
          ],
        });
      }),
    );
    addTearDown(client.dispose);

    final sessions = await client.getActivity();

    expect(sessions, hasLength(2));
    expect(sessions[0].friendlyName, 'Alice');
    expect(sessions[0].displayTitle, 'Some Show - The Pilot');
    expect(sessions[0].progressPercent, 42);
    expect(sessions[0].transcodeDecision, 'transcode');
    expect(sessions[0].bandwidthKbps, 4200);
    expect(sessions[1].displayTitle, 'A Movie');
    expect(sessions[1].grandparentTitle, isNull);
    expect(sessions[1].bandwidthKbps, 8000);
  });

  test('returns an empty list when there are no active sessions', () async {
    final client = TautulliClient(
      baseUrl: 'http://tautulli.example.com:8181',
      apiKey: 'secret',
      httpClient: MockClient((_) async => activityResponse({'sessions': []})),
    );
    addTearDown(client.dispose);

    expect(await client.getActivity(), isEmpty);
  });

  test('throws when Tautulli reports a non-success result', () async {
    final client = TautulliClient(
      baseUrl: 'http://tautulli.example.com:8181',
      apiKey: 'wrong',
      httpClient: MockClient((_) async => activityResponse({}, result: 'error', message: 'Invalid apikey')),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.getActivity(),
      throwsA(isA<TautulliApiException>().having((e) => e.message, 'message', 'Invalid apikey')),
    );
  });

  test('throws on a non-2xx HTTP response', () async {
    final client = TautulliClient(
      baseUrl: 'http://tautulli.example.com:8181',
      apiKey: 'secret',
      httpClient: MockClient((_) async => http.Response('server error', 500)),
    );
    addTearDown(client.dispose);

    await expectLater(client.getActivity(), throwsA(isA<TautulliApiException>()));
  });

  test('preserves a path prefix for a reverse-proxied Tautulli instance', () async {
    final client = TautulliClient(
      baseUrl: 'https://media.example.com/tautulli',
      apiKey: 'secret',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/tautulli/api/v2');
        return activityResponse({'sessions': []});
      }),
    );
    addTearDown(client.dispose);

    await client.getActivity();
  });
}
