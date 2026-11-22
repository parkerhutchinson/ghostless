import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';
import 'background.dart';
import 'settings_repository.dart';
import '../app_theme.dart';
import 'color_picker.dart';

/// The Settings modal. Changes apply right away.
Future<void> showSettingsDialog(
  BuildContext context,
  SettingsRepository settings, {
  SyncService? sync,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _SettingsDialog(settings: settings, sync: sync),
);

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings, this.sync});
  final SettingsRepository settings;

  /// The Sync section; left out when null (tests).
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: const Text('Settings'),
      content: SizedBox(
        width: 440,
        // Scrolls when the window is too short for every section.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              StreamBuilder<Background>(
                stream: settings.watchBackground(),
                initialData: settings.background,
                builder: (context, snap) => _BackgroundPicker(
                  settings: settings,
                  current: snap.requireData,
                ),
              ),
              StreamBuilder<Color>(
                stream: settings.watchAccent(),
                initialData: settings.accent,
                builder: (context, snap) => _AccentPicker(
                  settings: settings,
                  current: snap.requireData,
                ),
              ),
              if (sync case final sync?) ...[
                Divider(height: 8, color: context.colors.cardBorder),
                SyncSettingsSection(sync: sync),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({required this.settings, required this.current});
  final SettingsRepository settings;
  final Background current;

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
            _ImageTile(
              label: 'Mountains',
              image: const AssetImage(MountainsBackground.asset),
              selected: current is MountainsBackground,
              onTap: () => settings.setBackground(const MountainsBackground()),
            ),
            if (current is ImageBackground)
              _ImageTile(
                label: 'Your image',
                image: FileImage(settings.backgroundFile(current.fileName)),
                selected: true,
                onTap: () {},
              ),
            _ChooseImageTile(onTap: _pickImage),
          ],
        ),
        const SizedBox(height: 4),
        _ColorRow(
          label: 'Background color',
          presets: backgroundColors,
          // Nothing is selected while an image is the background.
          current: switch (current) {
            ColorBackground(:final color) => color,
            _ => null,
          },
          // The picker starts from the current color, or the default gray.
          pickerStart: current.baseColor,
          // Previews never delete a picked image: cancelling puts it back.
          onPreview: (c) => settings.previewBackground(ColorBackground(c)),
          onPicked: (c) {
            settings.setBackground(ColorBackground(c));
            settings.deleteUnusedBackgroundImages();
          },
          onCancel: () => settings.previewBackground(current),
        ),
      ],
    );
  }
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
    presets: accentColors,
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
          decoration: BoxDecoration(
            borderRadius: formRadius,
            border: Border.all(color: context.colors.cardBorder),
          ),
          child: Icon(Symbols.add, size: 16),
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
      fontWeight: FontWeight.w600,
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
            Text('Choose image…', style: TextStyle(fontSize: 12)),
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
