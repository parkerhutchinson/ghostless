import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../export/export_section.dart';
import '../mcp/mcp_service.dart';
import '../mcp/mcp_settings_section.dart';
import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';
import '../tasks/label_colors.dart';
import 'background.dart';
import 'settings_repository.dart';
import '../app_theme.dart';
import 'color_picker.dart';
import '../widgets/sliding_toggle.dart';
import '../files/arriving_file.dart';
import '../files/file_sync.dart';
import '../files/file_storage_section.dart';

/// The Settings modal. Changes apply right away.
Future<void> showSettingsDialog(
  BuildContext context,
  SettingsRepository settings, {
  SyncService? sync,
  ExportSources? export,
  McpService? mcp,
  FileSync? files,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _SettingsDialog(
    settings: settings,
    sync: sync,
    export: export,
    mcp: mcp,
    files: files,
  ),
);

/// The Settings window's height: the same on every tab.
const settingsDialogHeight = 550.0;

/// The Settings tabs.
enum _Tab { theme, data, export, mcp }

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    this.sync,
    this.export,
    this.mcp,
    this.files,
  });

  final FileSync? files;
  final SettingsRepository settings;

  /// The MCP tab; left out when null (tests).
  final McpService? mcp;

  /// The Export tab; left out when null (tests).
  final ExportSources? export;

  /// The Data tab (Sync); left out when null (tests).
  final SyncService? sync;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _Tab _tab = _Tab.theme;

  /// The tabs there's something to show in.
  List<_Tab> get _tabs => [
    _Tab.theme,
    if (widget.sync != null) _Tab.data,
    if (widget.export != null) _Tab.export,
    if (widget.mcp != null) _Tab.mcp,
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final theme = Theme.of(context);
    // A plain Dialog, not an AlertDialog (which sizes itself to what's in
    // it): always this tall, so switching tabs doesn't resize it. Padded
    // like an AlertDialog.
    return Dialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      child: SizedBox(
        width: 540 + 48,
        height: settingsDialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                'Settings',
                style:
                    theme.dialogTheme.titleTextStyle ??
                    theme.textTheme.headlineSmall,
              ),
              if (tabs.length > 1) _switcher(tabs),
              // The rest of the height; scrolls if a tab needs more.
              Expanded(
                child: _FadingScroll(
                  // A fresh scroll position per tab.
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    _Tab.theme => _theme(),
                    _Tab.data => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 32,
                      children: [
                        SyncSettingsSection(sync: widget.sync!),
                        if (widget.files case final files?)
                          FileStorageSection(files: files, sync: widget.sync!),
                      ],
                    ),
                    _Tab.export => ExportSection(sources: widget.export!),
                    _Tab.mcp => McpSettingsSection(mcp: widget.mcp!),
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Theme · Data · Export, across the top: styled like the Board/List
  /// switch.
  Widget _switcher(List<_Tab> tabs) => SlidingToggle<_Tab>(
    segments: [
      for (final t in tabs)
        ToggleSegment(
          value: t,
          icon: switch (t) {
            _Tab.theme => Symbols.palette,
            _Tab.data => Symbols.database,
            _Tab.export => Symbols.download,
            _Tab.mcp => Symbols.hub,
          },
          label: switch (t) {
            _Tab.theme => 'Theme',
            _Tab.data => 'Data',
            _Tab.export => 'Export',
            _Tab.mcp => 'MCP',
          },
        ),
    ],
    selected: _tab,
    onChanged: (t) => setState(() => _tab = t),
  );

  /// Background image, background color and accent.
  Widget _theme() {
    final settings = widget.settings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        StreamBuilder<Background?>(
          stream: settings.watchBackground(),
          initialData: settings.background,
          builder: (context, snap) =>
              _BackgroundPicker(settings: settings, current: snap.data),
        ),
        StreamBuilder<Color>(
          stream: settings.watchBackgroundColor(),
          initialData: settings.backgroundColor,
          builder: (context, snap) => _BackgroundColorPicker(
            settings: settings,
            current: snap.requireData,
          ),
        ),
        StreamBuilder<Color>(
          stream: settings.watchAccent(),
          initialData: settings.accent,
          builder: (context, snap) =>
              _AccentPicker(settings: settings, current: snap.requireData),
        ),
      ],
    );
  }
}

/// Scrolls [child] with its bottom edge always faded out. Padding as tall
/// as the fade comes after [child], so scrolled to the end, all of it
/// shows clear of the fade. Only the content fades: the scrollbar sits
/// over the fade, unfaded.
class _FadingScroll extends StatefulWidget {
  const _FadingScroll({super.key, required this.child});
  final Widget child;

  @override
  State<_FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<_FadingScroll> {
  static const _fade = 32.0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    child: ShaderMask(
      // Opaque, then fading to clear over the last [_fade] pixels.
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.black, Colors.black, Colors.transparent],
        stops: [0, 1 - _fade / rect.height.clamp(_fade, double.infinity), 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ScrollConfiguration(
        // The scrollbar is the one outside the fade, above.
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: _fade),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// The image behind the window. Only the picture changes: the colors
/// follow the background color below.
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({required this.settings, required this.current});
  final SettingsRepository settings;
  final Background? current;

  Future<void> _pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (file != null) await settings.setBackgroundImage(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final current = this.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const _Label('Background image'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _NoImageTile(
              selected: current == null,
              onTap: () => settings.setBackground(null),
            ),
            // The uploaded image, kept while No image is picked.
            if (settings.uploadedImage case final upload?)
              ArrivingFile(
                file: settings.backgroundFile(upload),
                builder: (context) => _ImageTile(
                  label: 'Your image',
                  image: FileImage(settings.backgroundFile(upload)),
                  selected: current == ImageBackground(upload),
                  onTap: () => settings.setBackground(ImageBackground(upload)),
                ),
              ),
            _ChooseImageTile(onTap: _pickImage),
          ],
        ),
      ],
    );
  }
}

/// The background color: shows when there's no image, and sets the app's
/// surfaces, borders and text either way.
class _BackgroundColorPicker extends StatelessWidget {
  const _BackgroundColorPicker({required this.settings, required this.current});
  final SettingsRepository settings;
  final Color current;

  @override
  Widget build(BuildContext context) => _ColorRow(
    label: 'Background color',
    presets: backgroundColors,
    current: current,
    pickerStart: current,
    onPreview: settings.setBackgroundColor,
    onPicked: settings.setBackgroundColor,
    onCancel: () => settings.setBackgroundColor(current),
  );
}

/// The accent color: the + button, the selected project, filled buttons
/// and highlights, app-wide.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.settings, required this.current});
  final SettingsRepository settings;
  final Color current;

  @override
  Widget build(BuildContext context) => _ColorRow(
    label: 'Accent color',
    // The label colors, around the color wheel.
    presets: [for (final i in labelPickerOrder) labelPalette[i]],
    current: current,
    pickerStart: current,
    onPreview: settings.setAccent,
    onPicked: settings.setAccent,
    onCancel: () => settings.setAccent(current),
  );
}

/// A labelled row of color swatches: the [presets], then the [current]
/// color if it's a custom one, then a + tile that opens the color picker.
/// The picker previews live through [onPreview], then [onPicked] keeps the
/// choice, or [onCancel] puts back what was there.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.presets,
    required this.current,
    required this.pickerStart,
    required this.onPreview,
    required this.onPicked,
    required this.onCancel,
  });
  final String label;
  final List<Color> presets;
  final Color? current;
  final Color pickerStart;
  final ValueChanged<Color> onPreview;
  final ValueChanged<Color> onPicked;
  final VoidCallback onCancel;

  bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  Future<void> _pick(BuildContext context) async {
    final picked = await showColorPicker(
      context,
      title: label,
      initial: pickerStart,
      onChanged: onPreview,
    );
    picked == null ? onCancel() : onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final current = this.current;
    final custom = current != null && !presets.any((p) => _same(p, current));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _Label(label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in presets)
              _ColorSwatch(
                color: color,
                selected: current != null && _same(current, color),
                onTap: () => onPicked(color),
              ),
            if (custom)
              _ColorSwatch(
                color: current,
                selected: true,
                // Opens the picker on it, to adjust it.
                onTap: () => _pick(context),
              ),
            _CustomColorTile(onTap: () => _pick(context)),
          ],
        ),
      ],
    );
  }
}

/// The + at the end of a color row: pick any color.
class _CustomColorTile extends StatelessWidget {
  const _CustomColorTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Custom color',
    child: Semantics(
      label: 'Custom color',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: formRadius,
        child: Container(
          width: 30,
          height: 30,
          // The accent, like the app's other highlights.
          decoration: BoxDecoration(
            borderRadius: formRadius,
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Icon(
            Symbols.add,
            size: 16,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: context.colors.text,
    ),
  );
}

/// Outline shown around the selected choice.
BoxBorder _outline(BuildContext context, bool selected) => Border.all(
  color: selected ? context.colors.text : context.colors.cardBorder,
  width: selected ? 2 : 1,
);

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.label,
    required this.image,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final ImageProvider image;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: formRadius,
          child: Container(
            width: 120,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: formRadius,
              border: _outline(context, selected),
              image: DecorationImage(image: image, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}

/// "No image": just the background color.
class _NoImageTile extends StatelessWidget {
  const _NoImageTile({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'No image',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: formRadius,
        child: Container(
          width: 120,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: formRadius,
            border: _outline(context, selected),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 4,
            children: [
              Icon(
                Symbols.hide_image,
                size: 20,
                color: context.colors.mutedText,
              ),
              Text(
                'No image',
                style: TextStyle(fontSize: 12, color: context.colors.mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChooseImageTile extends StatelessWidget {
  const _ChooseImageTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 76,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.mutedText,
          side: BorderSide(color: context.colors.cardBorder),
          shape: formShape,
          padding: EdgeInsets.zero,
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Icon(Symbols.add_photo_alternate, size: 20),
            Text('Upload image', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Color #${color.toARGB32().toRadixString(16).substring(2)}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: formRadius,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: formRadius,
            border: _outline(context, selected),
          ),
          child: selected
              ? Icon(Symbols.check, size: 16, color: contrastOn(color))
              : null,
        ),
      ),
    );
  }
}
