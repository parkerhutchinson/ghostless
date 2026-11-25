import 'dart:convert';
import 'dart:io';

import 'mcp_tools.dart' show McpToolError;

/// The most a card image or attachment from a tool can be.
const maxMcpFileBytes = 20 * 1024 * 1024;

/// A file an AI assistant gave a tool (a card image or an attachment),
/// read and checked: what it is comes from its contents, not its name.
typedef McpFile = ({List<int> bytes, String name, String extension});

/// The JSON Schema of a file argument: its contents (base64), a web
/// address, or a path on this Mac.
Map<String, Object?> mcpFileSchema(
  String description, {
  bool allowPdf = false,
}) => {
  'type': 'object',
  'description':
      '$description Give exactly one of data, url or path. PNG, JPEG, GIF, '
      'WebP or HEIC${allowPdf ? ', or PDF' : ''}; at most '
      '${maxMcpFileBytes ~/ (1024 * 1024)} MB.',
  'properties': {
    'data': {
      'type': 'string',
      'description': 'The file\'s contents, base64 (a data: URL works too).',
    },
    'url': {
      'type': 'string',
      'description': 'An http(s) address to download it from.',
    },
    'path': {
      'type': 'string',
      'description':
          'A file on this Mac. The app is sandboxed and usually can\'t read '
          'paths it wasn\'t given in a file dialog: prefer data or url.',
    },
    'name': {
      'type': 'string',
      'description':
          'The name it\'s shown with (an attachment\'s); taken from the url '
          'or path if left out.',
    },
  },
};

/// Reads the file [spec] describes (see [mcpFileSchema]). With
/// [allowPdf] false, only images. Throws [McpToolError] for anything
/// wrong with it, so the assistant can fix the call.
Future<McpFile> readMcpFile(
  Object? spec, {
  required String argument,
  bool allowPdf = false,
  HttpClient Function() httpClient = HttpClient.new,
}) async {
  if (spec is! Map) {
    throw McpToolError('$argument must be an object with data, url or path.');
  }
  final given = [
    for (final key in ['data', 'url', 'path'])
      if (spec[key] case final String v when v.trim().isNotEmpty) key,
  ];
  if (given.length != 1) {
    throw McpToolError('$argument needs exactly one of data, url or path.');
  }
  final source = given.single;
  final value = (spec[source] as String).trim();
  final List<int> bytes;
  String? fromName;
  switch (source) {
    case 'data':
      bytes = _decodeBase64(value, argument);
    case 'url':
      bytes = await _download(value, argument, httpClient());
      fromName = _lastSegment(Uri.tryParse(value)?.path ?? '');
    default:
      bytes = await _readPath(value, argument);
      fromName = _lastSegment(value);
  }
  if (bytes.isEmpty) throw McpToolError('$argument is empty.');
  if (bytes.length > maxMcpFileBytes) {
    throw McpToolError(
      '$argument is too big: at most '
      '${maxMcpFileBytes ~/ (1024 * 1024)} MB.',
    );
  }
  final extension = sniffExtension(bytes);
  if (extension == null || (extension == 'pdf' && !allowPdf)) {
    throw McpToolError(
      '$argument isn\'t a PNG, JPEG, GIF, WebP or HEIC image'
      '${allowPdf ? ' or a PDF' : ''}.',
    );
  }
  var name = switch (spec['name']) {
    final String n when n.trim().isNotEmpty => n.trim(),
    _ => fromName ?? '',
  };
  if (name.isEmpty) name = extension == 'pdf' ? 'document' : 'image';
  // Named for what it is.
  if (!name.toLowerCase().endsWith('.$extension') &&
      !(extension == 'jpg' && name.toLowerCase().endsWith('.jpeg'))) {
    final dot = name.lastIndexOf('.');
    name = '${dot > 0 ? name.substring(0, dot) : name}.$extension';
  }
  return (bytes: bytes, name: name, extension: extension);
}

/// What a file is, from its first bytes: its extension, or null for
/// anything but an image or a PDF.
String? sniffExtension(List<int> b) {
  bool at(int offset, List<int> sig) =>
      b.length >= offset + sig.length &&
      [for (var i = 0; i < sig.length; i++) b[offset + i] == sig[i]]
          .every((x) => x);
  List<int> ascii(String s) => s.codeUnits;
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (at(0, ascii('GIF8'))) return 'gif';
  if (at(0, ascii('RIFF')) && at(8, ascii('WEBP'))) return 'webp';
  if (at(0, ascii('%PDF'))) return 'pdf';
  if (at(4, ascii('ftyp')) &&
      ['heic', 'heix', 'heif', 'mif1', 'msf1'].any((t) => at(8, ascii(t)))) {
    return 'heic';
  }
  return null;
}

List<int> _decodeBase64(String value, String argument) {
  // A data: URL: just what's after the comma.
  final comma = value.startsWith('data:') ? value.indexOf(',') : -1;
  final data = (comma == -1 ? value : value.substring(comma + 1)).replaceAll(
    RegExp(r'\s'),
    '',
  );
  try {
    return base64.decode(base64.normalize(data));
  } on FormatException {
    throw McpToolError('$argument data isn\'t valid base64.');
  }
}

Future<List<int>> _download(
  String url,
  String argument,
  HttpClient client,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    throw McpToolError('$argument url must be an http or https address.');
  }
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw McpToolError(
        'Couldn\'t download $argument: the server answered '
        '${response.statusCode}.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > maxMcpFileBytes) {
        throw McpToolError(
          '$argument is too big: at most '
          '${maxMcpFileBytes ~/ (1024 * 1024)} MB.',
        );
      }
    }
    return bytes;
  } on McpToolError {
    rethrow;
  } on Exception catch (e) {
    throw McpToolError('Couldn\'t download $argument: $e');
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _readPath(String path, String argument) async {
  try {
    final file = File(path);
    if (await file.length() > maxMcpFileBytes) {
      throw McpToolError(
        '$argument is too big: at most '
        '${maxMcpFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return await file.readAsBytes();
  } on FileSystemException {
    throw McpToolError(
      'Couldn\'t read $argument at "$path". The app is sandboxed by macOS '
      'and can only open files picked in it: send the file\'s contents as '
      'data (base64) or a url instead.',
    );
  }
}

String? _lastSegment(String path) {
  final i = path.lastIndexOf('/');
  var name = i == -1 ? path : path.substring(i + 1);
  try {
    name = Uri.decodeComponent(name);
  } on ArgumentError {
    // Not %-encoded after all: as is.
  }
  return name.isEmpty ? null : name;
}
