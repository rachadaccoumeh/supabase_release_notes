import 'package:release_notes_gate/release_notes_gate.dart';
import 'package:supabase/supabase.dart';

/// Narrows the query, for example to one app or to published rows only.
typedef SupabaseQueryBuilder =
    PostgrestFilterBuilder<PostgrestList> Function(
      PostgrestFilterBuilder<PostgrestList> query,
    );

/// Release notes from a Supabase table, one row per release in the
/// `ReleaseNoteJson` shape:
///
/// ```sql
/// create table release_notes (
///   version      text primary key,
///   date         date,
///   title        jsonb,
///   url          text,
///   download_url text,
///   platforms    text[],
///   sections     jsonb,
///   markdown     text,
///   published    boolean not null default true
/// );
/// ```
///
/// Works with hosted and self-hosted Supabase alike: it only needs a
/// `SupabaseClient`, which `supabase_flutter` gives you as
/// `Supabase.instance.client`.
class SupabaseReleaseNotesSource extends ReleaseNotesSource {
  /// Creates a source over [table].
  ///
  /// [query] narrows the rows, for example `(q) => q.eq('published', true)`.
  /// [columns] is the PostgREST select list; `*` by default.
  /// [defaultLocale] names the fallback language of text maps without a
  /// `default` key.
  SupabaseReleaseNotesSource({
    required this.client,
    this.table = 'release_notes',
    this.columns = '*',
    this.query,
    this.limit,
    this.parser = const ChangelogParser(),
    this.defaultLocale = 'en',
  });

  /// The Supabase client.
  final SupabaseClient client;

  /// The table that holds one row per release.
  final String table;

  /// The columns to select.
  final String columns;

  /// Narrows the rows. Null reads the whole table.
  final SupabaseQueryBuilder? query;

  /// At most this many rows. Null reads all.
  final int? limit;

  /// Parses a `markdown` column into sections.
  final ChangelogParser parser;

  /// Fallback language of text maps without a `default` key.
  final String defaultLocale;

  @override
  Future<List<ReleaseNote>> fetch() async {
    final PostgrestList rows;
    try {
      var builder = client.from(table).select(columns);
      if (query != null) builder = query!(builder);
      rows = limit == null ? await builder : await builder.limit(limit!);
    } on PostgrestException catch (error) {
      throw ReleaseNotesException(
        error.message,
        kind: ReleaseNotesErrorKind.http,
        statusCode: int.tryParse(error.code ?? ''),
        cause: error,
      );
    } catch (error) {
      throw ReleaseNotesException(
        'Supabase read failed',
        kind: ReleaseNotesErrorKind.network,
        cause: error,
      );
    }
    return decodeRows(rows);
  }

  /// Turns rows into notes, newest first. Rows without a usable version are
  /// skipped.
  List<ReleaseNote> decodeRows(Iterable<Map<String, dynamic>> rows) =>
      rows
          .map(
            (row) => ReleaseNoteJson.decode(
              row.cast<String, Object?>(),
              parser: parser,
              defaultLocale: defaultLocale,
            ),
          )
          .whereType<ReleaseNote>()
          .toList(growable: false)
          .newestFirst;
}
