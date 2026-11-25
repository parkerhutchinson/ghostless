# codename

## Design rules

### Rounded corners: one radius everywhere

Every rounded corner in the app uses the same radius: **4px**, defined once as
`formRadius` / `formShape` in `lib/app_theme.dart`. This applies to every
feature, existing and new:

- buttons, toggles (e.g. the Board/List switcher), the floating + button
- inputs, dropdowns and their menus, chips, tags and labels
- empty-state boxes
- tiles and swatches (images, colors), sidebar rows, menu buttons

Rules:

- Use `formRadius` / `formShape` (or rely on the theme from `buildAppTheme()`).
  Never hard-code another radius such as `BorderRadius.circular(8)`.
- No pill (stadium) shapes for anything.
- To change the corner radius, change `formRadius` only, so everything stays
  in step.
- Icon-only buttons (+, ✕, ⋯, arrows) use it too: their hover and press
  highlight is a 4px rounded square, never a circle (set app-wide via
  `iconButtonTheme`).
- Exceptions: things that are truly circular by design (the done checkbox,
  avatars) stay circles. A project's color mark is a 4px rounded square
  (`ProjectIcon` in `lib/projects/project_logo.dart`), with its logo on
  it when it has one.
- One exception: a whole board column being dragged (its drag feedback
  and the drop highlight) uses a slightly rounder **6px**
  (`containerRadius` / `containerShape`), because 4px looks too sharp at
  that size. Columns have no background panel: cards sit straight on the
  background. Dialogs and everything else stay at 4px.
- Task cards (and the empty slot a dragged card leaves) are square: no
  radius.
- The list view's table is square (no radius): the header box, each
  group's box and the row hover highlight. The chips inside rows (due
  date, tags, projects) keep 4px.
- The Activity page is square too, styled like the list view: each
  day's rows boxed together on the card shade, with no radius anywhere
  on it (rows, the day count, the time box, the dismiss button).

- The project dashboard (`lib/projects/project_dashboard.dart`, the
  header toggle's third view) is square too: its tiles sit on the card
  shade with no radius, packed edge to edge in each section (no gaps,
  one shared border line between neighbours), right under the heading. Its section headings look
  exactly like board column headings (frosted, 14/w600
  title, count chip, 26px button). The description is read only there;
  it's written in the project dialog. Its numbers come from
  `projectStats` (`project_stats.dart`, unit tested), never worked out
  in widgets.

### Form fields: one height

Every boxed one-line field is the same height, **36px**
(`formFieldHeight` in `lib/tasks/form_buttons.dart`): text inputs,
select boxes, and selects showing a pick (the Column picker, the
Assignee search, the due date and time, Reminder). Set it with
`InputDecoration(constraints: formFieldConstraints)`, never with
padding alone: padding, fonts and the Mac's compact density all change
a field's natural height. Dropdown items stay on one line (`maxLines:
1`, ellipsis) so a long choice can't make the box taller.

### Colors: everything follows the background color

Surfaces, borders and hover shades are never hard-coded. They come from
`context.colors` (`AppColors` in `lib/app_theme.dart`), which is worked out
from the background color picked in Settings. A background image is only
drawn over that color; it never changes the colors: darker sections mix in black, borders and hover
fills mix in white. Use `context.colors.surface`, `.column`, `.card`,
`.cardBorder`, `.formBorder`, `.fieldBorder`, `.hover`, `.divider`, etc.
Highlights (buttons, the selected project) use the accent from Settings:
`Theme.of(context).colorScheme.primary`.

Text colors follow it too, since the background can be light (even white):
never hard-code `Colors.white` or a gray for text, icons or outlines. Use
`context.colors.text`, `.mutedText` and `.placeholder`. On an accent fill
use `colorScheme.onPrimary`, which is the near-black `accentText`
(#141414) whatever the accent, white only on an extremely dark one
(`onAccentColor`), and on any other fill (a swatch) use
`contrastOn(fill)`.

Labels and icons are `.text` (white): section headings, the Settings
button, table headers, due date and project chips. `.mutedText` is only
for inactive or secondary things: completed tasks, counts, descriptions,
empty-state hints.

### Text selection: black on white

Selected text in every text field is black on a white highlight,
whatever the theme (`selectionFill` / `selectedTextColor` in
`lib/widgets/selected_text.dart`). Flutter can't recolor selected text
from the theme, so the controller does it: use `AppTextController`, never
a plain `TextEditingController`. A controller with its own
`buildTextSpan` (e.g. `RichTextController`) passes its spans through
`withSelectedText`.

### Icons

Use Material Symbols (`Symbols.*` from `material_symbols_icons`), never
`Icons.*`: the theme sets a lighter stroke weight (300) that only the
Symbols font supports. The one exception is `Icons.circle`, solid dots
such as the unread marker (Symbols' circle is an outline).

### Every page's bottom fades out

Every view or page that scrolls down to the bottom of the window fades
out at the bottom (`BottomFade`, in `lib/widgets/bottom_fade.dart`),
like the board columns, the list view, Activity and the dashboard. This
applies to every new view, without being asked. For a plain scrolling
page, use `BottomFadeScrollView`, which also keeps the scrollbar out of
the fade (see below). Leave room at the end (`bottomFadeHeight`, or
`fabClearance` where the New task button is) so the last content can
scroll clear of the fade.

### Fades never cover scrollbars

Wherever a scrolling list fades out (a `ShaderMask`, e.g. `BottomFade`),
the scrollbar must not fade with it. A scrollable's automatic scrollbar
is drawn inside it, so it ends up under the mask. Always:

- turn the automatic one off around the scrollable:
  `ScrollConfiguration.of(context).copyWith(scrollbars: false)`, and
- put an explicit `Scrollbar(controller: …)` **outside** the
  `ShaderMask`, sharing the list's `ScrollController`.

Examples: the board columns (`task_board.dart`), the list view
(`tasks_page.dart`), Settings, the search results and the dashboard
(through `BottomFadeScrollView`).

### Scrollbars never jitter

A lazy list (`ListView`, `SliverList`) only lays out the items near the
screen and guesses the height of the rest. When items differ in height,
the guess (and so the scrollbar thumb) changes as it scrolls: the thumb
jitters. This has come up twice. So:

- Lists of items that vary in height (board columns: cards with images,
  labels, subtasks) lay everything out: a `SingleChildScrollView` with a
  `Column`, the column in a `RepaintBoundary` (and each item in one) so
  scrolling doesn't repaint every item.
- Long lists that must stay lazy (the list view) make every item
  nearly the same height: one row per item, not one item per group.
- Check with the real data: measure `maxScrollExtent` while scrolling;
  it shouldn't change.

## Profiles

Each person using the app has a profile (`lib/profiles/`, collection
`profiles`, synced): first and last name, a photo, their own theme, and a
personal project. Which profile is using this Mac is kept locally
(`ui/session`).

- Theme settings (accent, background) belong to the current profile:
  `SettingsRepository` reads and writes `Profile.theme`, so switching
  profiles switches the theme. Don't store per-person settings anywhere
  else.
- A personal project is a `Project` with `ownerId` set to its profile. Use
  `visibleProjects(projects, profileId)` wherever projects are listed: it
  hides other profiles' personal projects. Personal projects can't be
  edited at all (no rename, color, logo or delete): the sidebar shows
  no edit button for them.
- The avatar (`ProfileAvatar`) is a circle by design, like the color dots.
- Favorite (starred) projects belong to the profile too:
  `Profile.favoriteProjects`, in the order starred, set with
  `ProfileRepository.setFavorite`. The sidebar lists them under
  Favorites (via `favoriteProjects()`, which skips deleted and personal
  ones), and they stay under Projects as well.
- Tasks point at a profile with `Task.assigneeId` (null = unassigned; an
  id with no matching profile also shows as unassigned). Widgets look
  profiles up through `ProfilesScope.maybeOf(context)`, which sits above
  the navigator so dialogs see it; `AssigneeAvatar` draws the avatar.

## Comments

Tasks have comments (`lib/comments/`, collection `comments`, synced),
kept apart from the task record so people commenting at once don't
overwrite each other. They're posted straight away, not with the task
form's Save.

- A comment's body is Markdown with paragraphs, **bold** and links only:
  the editor offers just those (`RichTextEditor(tools: commentTools)`),
  and `CommentRepository.add` strips anything else (`commentMarkdown`).
- Each comment tells the task's assignee (unless they wrote it): an
  `ActivityKind.commented` activity with a short `excerpt`.
- The task form finds the store through `CommentsScope` (above the
  navigator, like `ProfilesScope`); without one it has no comments.
- Rich text shown read only (comments, a project's description) uses
  `RichTextView`: drawn like the editor, links open on click.

## Reminders

A task can remind its assignee before it's due (`Task.reminder`,
minutes before; null for none; only with a due date). They're **local**
macOS notifications (`flutter_local_notifications`), scheduled with the
system so they go off even when the app is closed: no server, no push.

- Which reminders to schedule, when and what they say is worked out by
  `plannedReminders` (`lib/reminders/reminders.dart`, unit tested): only
  the current profile's assigned tasks, not checked off, still to come,
  soonest first, at most 60 (macOS keeps 64). A task due any time that
  day counts as due at 9 AM.
- `ReminderService` keeps macOS's schedule in step with it whenever
  tasks, projects or the profile change. Clicking a notification opens
  the task on its origin board.
- Permission is asked the first time a reminder is picked in the task
  form (`RemindersScope`), not at launch.

## Sync database (Supabase)

The Postgres tables the app syncs with are created by the migrations in
`supabase/migrations/` (Supabase CLI format: `<timestamp>_<name>.sql`).
They mirror `appSchema` (`lib/sync/app_schema.dart`), and
`test/supabase_migrations_test.dart` fails when the two drift.

- When a model gains a synced field (anything added to `appSchema`), add
  a **new** migration file with `alter table ... add column if not
  exists`; never edit one that has been applied.
- Columns are named exactly as the app's fields (camelCase, quoted).
  Lists and objects are `jsonb`, dates and times `timestamptz`, and
  `dueDate`/`dueTime` stay `text`. Everything but `id` is nullable.
- Every table has `id text primary key`, `updated_at timestamptz` (written
  by the app: no trigger may overwrite it, or last-write-wins breaks) and
  `deleted_at timestamptz` (soft deletes, so deletes sync).
- Row Level Security is on with no policies, so Supabase's public API
  can't touch the tables; the app connects directly as `postgres`.
- Apply with `supabase link --project-ref <ref>` then `supabase db push`,
  or paste the file into the dashboard's SQL editor. In the app, use the
  direct connection or the **session** pooler (port 5432) with SSL on,
  not the transaction pooler (6543).

## Orgs (in progress)

Businesses are kept apart by orgs, enforced in the database
(`supabase/migrations/*_orgs.sql`), never only by the app.

- Everyone signs in (Supabase Auth, email + 6-digit code). Each account
  has one **personal space** (an org of kind `personal`, just them, plan
  `free`) and at most one **business org** (kind `business`), as
  `owner`, `admin` or `member` (`org_members`).
- Every synced record has an `"orgId"`. Row Level Security gives each
  person only their orgs' records; inside an org, other people's
  personal projects (and their tasks and comments) and other people's
  Activity stay hidden.
- Orgs, memberships, invites and claimed email domains change only
  through the `public.*` functions (`ensure_personal_space`,
  `create_business_org`, `join_org`, `invite_member`, `change_role`,
  `remove_member`, ...), which check the caller's role; clients can't
  write those tables.
- Where a licensed org's data lives (`org_connections`) is the
  owner's alone; each member's own database login
  (`member_credentials`) is readable by that member and the owner.
- Files in the hosted bucket (`codename`) live under `<orgId>/...`;
  members reach their own orgs' folders only.
- The rules are tested against a **test** Supabase project by
  `test/supabase/orgs_rls_test.dart` (skipped without
  `SUPABASE_TEST_*` settings, kept in the git-ignored `.env.test`).
  Change a rule, run it.

## Files online (Supabase Storage)

Records only hold file names; the files themselves (task images and
attachments, profile photos, background images) go to a private
Supabase Storage bucket (`files`, made by the `*_file_storage.sql`
migration), connected in Settings › Data › Files (`lib/files/`).

- `FileSync` sends this Mac's files up, fetches other Macs', and deletes
  online what's deleted here. Paths are `tasks/<file>`,
  `profiles/<file>`, `backgrounds/<file>`. Files never change once
  written (a new image is a new name), so each is sent and fetched once;
  what's been sent is kept in the local `file_sync` collection (not
  synced).
- A new kind of file a record refers to must be added to the `files:`
  list in `main.dart`, and its repository must report deletions
  (`onFileDeleted`).
- Show a local file through `ArrivingFile` (`lib/files/arriving_file.dart`),
  never a bare `Image.file`/`FileImage`: it rebuilds the image when the
  file arrives from storage (an image widget doesn't retry by itself).
- The app uses the project's secret key (kept on the Mac, like the
  database password); the bucket has no policies, so nothing else can
  read it.

## MCP server

The app can run an MCP server for AI assistants (`lib/mcp/`), switched on
in Settings › MCP. It listens on 127.0.0.1 only (default port 7429, path
`/mcp`, Streamable HTTP, JSON responses, no SSE) and needs the bearer
token shown in Settings. The switch, port and token are kept on this Mac
(`ui/mcp`, not synced).

- Tools (`McpTools`) go through the same repositories as the screens, so
  changes appear live, record activity and sync. Never write the store
  directly from a tool.
- Tools act as the current profile and only see `visibleProjects`.
- A tool's mistake (unknown task, bad date) throws `McpToolError`: it's
  returned to the assistant as `isError`, not a protocol error.
- When a task or project gains a field worth reading or setting, add it
  to the tools' JSON and schemas.
- `get_task` lists a task's comments; `add_comment` adds one as the
  current profile.
- Files (card images, attachments) come in as base64 `data`, a `url`
  or a `path` (`lib/mcp/mcp_files.dart`), checked by their first bytes,
  not their names. The app is sandboxed, so a path usually can't be read:
  agents should send data or a url.

## Before shipping: compliance reminder

When the user talks about shipping, releasing, distributing or
publishing the app (App Store, notarizing, a public download, a hosted
sync service), stop and remind them of this checklist first, and offer
to make any changes it needs. None of it is done yet.

- **Privacy law (GDPR, UK GDPR, CCPA and the like):** applies if the
  app collects personal data that leaves the device (profiles' names
  and photos, analytics, crash reports). Needs a privacy policy and a
  lawful basis; collect as little as possible.
- **Apple distribution:** outside the App Store, a Developer ID
  signature and notarization; on it, privacy "nutrition labels", a
  privacy policy link and App Review. The bundle ID is still
  `com.example.codename`: change it before shipping.
- **Encryption export:** App Store Connect asks. Standard HTTPS/TLS is
  usually exempt, but it still has to be declared.
- **Open-source licences:** check the Flutter packages' and bundled
  fonts' licences, and ship their notices.
- **Accessibility:** not usually required by law for a small app, but
  government and enterprise buyers may ask for a VPAT/WCAG statement.

SOC 2 isn't required: it becomes relevant only with a hosted service
that stores customers' data, or enterprise customers who ask for it.
This is not legal advice; suggest a lawyer before a public launch.
