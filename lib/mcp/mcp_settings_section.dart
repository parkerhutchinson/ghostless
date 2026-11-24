import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'mcp_service.dart';

/// The server's entry in the `mcpServers` JSON that most AI agents read
/// their MCP servers from: not tied to any one agent.
String agentCommand(McpService mcp) =>
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'codename': {
          'type': 'http',
          'url': mcp.url,
          'headers': {'Authorization': 'Bearer ${mcp.token}'},
        },
      },
    });

/// Settings' MCP tab: turns the app's MCP server on or off, and shows
/// what an AI assistant needs to connect (address, token, the agent
/// command).
class McpSettingsSection extends StatefulWidget {
  const McpSettingsSection({super.key, required this.mcp});
  final McpService mcp;

  @override
  State<McpSettingsSection> createState() => _McpSettingsSectionState();
}

class _McpSettingsSectionState extends State<McpSettingsSection> {
  /// The token is hidden until asked for.
  bool _showToken = false;

  /// What was just copied, shown briefly by the buttons.
  String? _copied;

  McpService get _mcp => widget.mcp;

  Future<void> _copy(String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = what);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copied == what) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<McpStatus>(
    valueListenable: _mcp.status,
    builder: (context, status, _) {
      final scheme = Theme.of(context).colorScheme;
      final muted = TextStyle(fontSize: 13, color: context.colors.mutedText);
      final enabled = _mcp.enabled;
      Widget outlined(String label, IconData icon, VoidCallback onPressed) =>
          OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.text,
              side: BorderSide(color: context.colors.formBorder),
            ),
            icon: Icon(icon, size: 16),
            label: Text(label),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            'Let AI agents read and change your projects '
            'and tasks while the app is open, through MCP (Model Context '
            'Protocol). Only apps on this Mac can connect, and only with '
            'the token.',
            style: muted,
          ),
          // The switch: a checkbox row (no pill-shaped switches).
          InkWell(
            borderRadius: formRadius,
            onTap: () => _mcp.setEnabled(!enabled),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                spacing: 8,
                children: [
                  Checkbox(
                    value: enabled,
                    shape: formShape,
                    activeColor: scheme.primary,
                    checkColor: scheme.onPrimary,
                    side: BorderSide(
                      color: context.colors.mutedText,
                      width: 1.5,
                    ),
                    onChanged: (on) => _mcp.setEnabled(on ?? false),
                  ),
                  Text(
                    'Turn on the MCP server',
                    style: TextStyle(fontSize: 14, color: context.colors.text),
                  ),
                ],
              ),
            ),
          ),
          _statusLine(context, status),
          if (enabled) ...[
            _field(
              context,
              'Address',
              _mcp.url,
              copy: () => _copy('address', _mcp.url),
              copied: _copied == 'address',
            ),
            _field(
              context,
              'Token',
              _showToken ? _mcp.token : '•' * 24,
              copy: () => _copy('token', _mcp.token),
              copied: _copied == 'token',
              extra: IconButton(
                tooltip: _showToken ? 'Hide' : 'Show',
                iconSize: 16,
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(
                  _showToken ? Symbols.visibility_off : Symbols.visibility,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                outlined(
                  _copied == 'command' ? 'Copied' : 'Copy agent command',
                  _copied == 'command' ? Symbols.check : Symbols.terminal,
                  () => _copy('command', agentCommand(_mcp)),
                ),
                outlined('New token', Symbols.refresh, () async {
                  await _mcp.regenerateToken();
                  if (mounted) setState(() {});
                }),
              ],
            ),
            Text(
              'Paste it into your agent\'s MCP settings. A new token '
              'disconnects agents set up with the old one.',
              style: muted.copyWith(fontSize: 12),
            ),
          ],
        ],
      );
    },
  );

  Widget _statusLine(BuildContext context, McpStatus status) {
    final (icon, text, color) = switch (status) {
      McpRunning(:final port) => (
        Icons.circle,
        'Running on port $port',
        Colors.green.shade400,
      ),
      McpFailed(:final message) => (Icons.circle, message, Colors.red.shade300),
      McpOff() => (Icons.circle, 'Off', context.colors.mutedText),
    };
    return Row(
      spacing: 8,
      children: [
        Icon(icon, size: 8, color: color),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: context.colors.text),
          ),
        ),
      ],
    );
  }

  /// A labelled read-only value with a Copy button.
  Widget _field(
    BuildContext context,
    String label,
    String value, {
    required VoidCallback copy,
    required bool copied,
    Widget? extra,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.text)),
      Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          borderRadius: formRadius,
          border: Border.all(color: context.colors.formBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Menlo',
                  color: context.colors.text,
                ),
              ),
            ),
            ?extra,
            IconButton(
              tooltip: copied ? 'Copied' : 'Copy',
              iconSize: 16,
              onPressed: copy,
              icon: Icon(copied ? Symbols.check : Symbols.content_copy),
            ),
          ],
        ),
      ),
    ],
  );
}
