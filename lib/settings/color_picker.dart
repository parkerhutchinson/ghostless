import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../widgets/selected_text.dart';

/// Reads a typed hex color: "#1E272B", "1e272b" or the short "#abc". Spaces
/// around it are ignored. Anything else gives null.
Color? parseHexColor(String input) {
  var hex = input.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// "#1E272B": the color's hex code, uppercase, without alpha.
String hexOf(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Opens the color picker on [initial]. [onChanged] is called as the color
/// changes, so the app can preview it live. Returns the chosen color, or
/// null when cancelled (Cancel, Escape, clicking outside), in which case
/// the caller puts back what was there.
Future<Color?> showColorPicker(
  BuildContext context, {
  required String title,
  required Color initial,
  required ValueChanged<Color> onChanged,
}) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _ColorPickerDialog(
      title: title,
      initial: initial,
      onChanged: onChanged,
    ),
  );
}

const _pickerWidth = 260.0;

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initial,
    required this.onChanged,
  });
  final String title;
  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  // Kept as HSV so dragging to black or gray doesn't lose the hue.
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = AppTextController(text: hexOf(widget.initial));
  final _hexFocus = FocusNode();

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv, {bool fromHex = false}) {
    setState(() => _hsv = hsv);
    if (!fromHex) _hex.text = hexOf(_color);
    widget.onChanged(_color);
  }

  void _typed(String text) {
    final color = parseHexColor(text);
    if (color == null) return;
    var hsv = HSVColor.fromColor(color);
    // A gray has no hue of its own; keep the current one on the bar.
    if (hsv.saturation == 0) hsv = hsv.withHue(_hsv.hue);
    _set(hsv, fromHex: true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: _pickerWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 14,
          children: [
            _SaturationValueBox(
              hsv: _hsv,
              onChanged: (s, v) => _set(_hsv.withSaturation(s).withValue(v)),
            ),
            _HueBar(hue: _hsv.hue, onChanged: (h) => _set(_hsv.withHue(h))),
            Row(
              spacing: 10,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: formRadius,
                    border: Border.all(color: context.colors.formBorder),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    focusNode: _hexFocus,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 14),
                    inputFormatters: [LengthLimitingTextInputFormatter(7)],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Hex',
                      labelStyle: TextStyle(color: context.colors.mutedText),
                      contentPadding: const EdgeInsets.all(12),
                      enabledBorder: context.colors.fieldBorder,
                      border: context.colors.fieldBorder,
                    ),
                    onChanged: _typed,
                    onSubmitted: (_) => Navigator.pop(context, _color),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

/// Drag a point anywhere in it: left to right is saturation (gray to full
/// color), top to bottom is brightness (full to black).
class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  static const _height = 170.0;

  void _at(Offset p) => onChanged(
    (p.dx / _pickerWidth).clamp(0.0, 1.0),
    1 - (p.dy / _height).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    final pure = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return GestureDetector(
      onPanDown: (d) => _at(d.localPosition),
      onPanUpdate: (d) => _at(d.localPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: SizedBox(
          width: _pickerWidth,
          height: _height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: formRadius,
                    gradient: LinearGradient(colors: [Colors.white, pure]),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: formRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hsv.saturation * _pickerWidth - 7,
                top: (1 - hsv.value) * _height - 7,
                child: const _Handle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hue: red through the rainbow and back to red, left to right.
class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  static const _height = 14.0;

  void _at(Offset p) =>
      onChanged((p.dx / _pickerWidth).clamp(0.0, 1.0) * 359.9);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _at(d.localPosition),
      onPanUpdate: (d) => _at(d.localPosition),
      child: SizedBox(
        width: _pickerWidth,
        height: _height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: formRadius,
                  gradient: LinearGradient(
                    colors: [
                      for (var h = 0; h <= 360; h += 60)
                        HSVColor.fromAHSV(1, h % 360, 1, 1).toColor(),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: hue / 360 * _pickerWidth - 7,
              top: 0,
              child: const _Handle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ring marking the picked point. A circle by design (like the color
/// dots), so it's not a 4px square.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
      ),
    ),
  );
}
