# supabase_release_notes

Supabase source for [`release_notes_gate`](https://pub.dev/packages/release_notes_gate). Works with hosted and self-hosted Supabase.

Keep one row per app release in a table. The app shows "what's new" after an update, an "update available" summary, or the full changelog, with the `release_notes_gate` timeline UI. This package adds one class, `SupabaseReleaseNotesSource`, and re-exports the core, so one import is enough.

## Setup

1. Initialise Supabase in your app with [`supabase_flutter`](https://pub.dev/packages/supabase_flutter).
2. Add the dependency:

```yaml
dependencies:
  supabase_release_notes: ^0.1.0
```

3. Create the table:

```sql
create table public.release_notes (
  version      text primary key,
  date         date,
  title        jsonb,
  url          text,
  download_url text,
  platforms    text[],
  sections     jsonb,
  markdown     text,
  published    boolean not null default true,
  created_at   timestamptz not null default now()
);

alter table public.release_notes enable row level security;

create policy "release notes are public"
  on public.release_notes for select
  using (published);
```

Writes stay with the service role: insert rows from the dashboard, a CI step or an admin script.

## Row shape

| Column | Type | Notes |
|---|---|---|
| `version` | text | `2.2.0` or `v2.2.0`. |
| `date` | date | Release day. |
| `title` | jsonb | Optional headline: a string, or a map of locale → text with a `default` key. |
| `url` | text | Optional release page. |
| `download_url` | text | Optional direct download. |
| `platforms` | text[] | Optional: `android`, `ios`, `web`, `windows`, `macos`, `linux`. Null means all. |
| `sections` | jsonb | See below. |
| `markdown` | text | Alternative to `sections`: the body in changelog Markdown. |
| `published` | boolean | Filter on it with a query. |

`sections` as a map of kind to items:

```json
{
  "features": [
    "Dark mode",
    {"text": {"default": "Face ID sign-in", "ar": "تسجيل الدخول ببصمة الوجه"}, "platforms": ["ios"]},
    {"text": "Faster sync", "scope": "Sync"}
  ],
  "fixes": ["Crash on start"],
  "performance": ["Faster startup"],
  "Notes": [{"text": "Android 7 is no longer supported.", "note": true}]
}
```

Kinds: `features`, `fixes`, `improvements`, `performance`. Any other key is a custom section that keeps its name. An item is a string, or an object with `text`, optional `scope`, optional `platforms`, and `note: true` for prose that is not counted.

Insert example:

```sql
insert into public.release_notes (version, date, sections) values (
  '2.2.0', '2026-10-25',
  '{"features": ["Dark mode"], "fixes": ["Crash on start"]}'
);
```

## Usage

```dart
import 'package:supabase_release_notes/supabase_release_notes.dart';

final controller = ReleaseNotesController(
  source: SupabaseReleaseNotesSource(
    client: Supabase.instance.client,
    query: (q) => q.eq('published', true),
  ),
);

MaterialApp(
  home: ReleaseNotesGate(controller: controller, appName: 'Your app', child: const HomePage()),
);
```

Several apps in one project: add an `app` column and filter on it with `(q) => q.eq('app', 'my-app')`, or use one table per app with `table: 'my_app_releases'`.

## Everything else

Triggers, platform filter, theming, strings, callbacks, caching and the widgets are documented in [`release_notes_gate`](https://pub.dev/packages/release_notes_gate).

## Development

The repository carries a `pubspec_overrides.yaml` that points `release_notes_gate` at a sibling checkout. Clone both packages side by side, or delete that file to resolve from pub.dev.

## License

MIT
