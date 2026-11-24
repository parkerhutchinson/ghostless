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

### Icons

Use Material Symbols (`Symbols.*` from `material_symbols_icons`), never
`Icons.*`: the theme sets a lighter stroke weight (300) that only the
Symbols font supports. The one exception is `Icons.circle`, solid dots
such as the unread marker (Symbols' circle is an outline).

### Fades never cover scrollbars

Wherever a scrolling list fades out (a `ShaderMask`, e.g. `BottomFade`),
the scrollbar must not fade with it. A scrollable's automatic scrollbar
is drawn inside it, so it ends up under the mask. Always:

- turn the automatic one off around the scrollable:
  `ScrollConfiguration.of(context).copyWith(scrollbars: false)`, and
- put an explicit `Scrollbar(controller: …)` **outside** the
  `ShaderMask`, sharing the list's `ScrollController`.

Examples: the board columns (`task_board.dart`), the list view
(`tasks_page.dart`), Settings and the search results.

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
- Tasks point at a profile with `Task.assigneeId` (null = unassigned; an
  id with no matching profile also shows as unassigned). Widgets look
  profiles up through `ProfilesScope.maybeOf(context)`, which sits above
  the navigator so dialogs see it; `AssigneeAvatar` draws the avatar.

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
