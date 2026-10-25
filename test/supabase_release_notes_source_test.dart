import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:supabase_release_notes/supabase_release_notes.dart';

final rows = [
  {
    'version': '1.0.0',
    'date': '2026-01-10',
    'published': true,
    'sections': {
      'features': ['First release'],
    },
  },
  {
    'version': 'v1.1.0',
    'date': '2026-02-01',
    'published': true,
    'platforms': ['android', 'ios'],
    'sections': {
      'features': [
        'Dark mode',
        {
          'text': {'default': 'Face ID', 'ar': 'بصمة الوجه'},
          'platforms': ['ios'],
        },
      ],
      'fixes': ['Crash on start'],
    },
  },
  {
    'version': '1.2.0',
    'published': false,
    'markdown': '### Features\n* Unpublished thing',
  },
  {'id': 7},
];

void main() {
  late List<Uri> requests;

  SupabaseClient client({int status = 200, Object? body}) {
    requests = [];
    return SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        requests.add(request.url);
        // The anon key travels as the apikey header on every request.
        expect(request.headers['apikey'], 'anon-key');
        final filtered =
            request.url.queryParameters['published'] == 'eq.true'
                ? rows.where((row) => row['published'] == true).toList()
                : rows;
        return http.Response(
          jsonEncode(body ?? filtered),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  }

  test(
    'reads the table newest first and skips rows without a version',
    () async {
      final source = SupabaseReleaseNotesSource(client: client());
      final notes = await source.fetch();
      expect(notes.map((n) => n.version.normalized), [
        '1.2.0',
        '1.1.0',
        '1.0.0',
      ]);
      expect(notes.last.date, DateTime(2026, 1, 10));
      expect(notes[1].platforms, {
        ReleasePlatform.android,
        ReleasePlatform.ios,
      });
      expect(notes[1].counts, {
        ReleaseSectionKind.features: 2,
        ReleaseSectionKind.fixes: 1,
      });
      expect(
        notes[1].sections.first.items[1].text.resolve(const Locale('ar')),
        'بصمة الوجه',
      );
      expect(
        notes.first.sections.single.items.single.text.text,
        'Unpublished thing',
      );
      expect(requests.single.path, '/rest/v1/release_notes');
      expect(requests.single.queryParameters['select'], '*');
    },
  );

  test('a query narrows the rows and limit is sent', () async {
    final source = SupabaseReleaseNotesSource(
      client: client(),
      table: 'app_releases',
      query: (q) => q.eq('published', true),
      limit: 20,
    );
    final notes = await source.fetch();
    expect(notes.map((n) => n.version.normalized), ['1.1.0', '1.0.0']);
    expect(requests.single.path, '/rest/v1/app_releases');
    expect(requests.single.queryParameters['published'], 'eq.true');
    expect(requests.single.queryParameters['limit'], '20');
  });

  test('turns a PostgREST error into ReleaseNotesException', () async {
    final source = SupabaseReleaseNotesSource(
      client: client(
        status: 401,
        body: {'message': 'JWT expired', 'code': '401'},
      ),
    );
    await expectLater(
      source.fetch(),
      throwsA(
        isA<ReleaseNotesException>().having(
          (e) => e.message,
          'message',
          'JWT expired',
        ),
      ),
    );
  });

  test('works with the controller', () async {
    final controller = ReleaseNotesController(
      source: SupabaseReleaseNotesSource(
        client: client(),
        query: (q) => q.eq('published', true),
      ),
      config: const ReleaseNotesConfig(platformFilter: PlatformFilter.none),
      seenStore: MemorySeenVersionStore(ReleaseVersion.parse('1.0.0')),
      cache: MemoryReleaseNotesCache(),
      installedVersionLoader: () async => '1.1.0',
    );
    final decision = await controller.check();
    expect(decision.shouldShow, isTrue);
    expect(decision.notes.single.version.normalized, '1.1.0');
  });
}
