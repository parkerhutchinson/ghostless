import '../tasks/rich_text/rich_text_model.dart';

/// A comment on a task (collection `comments`, synced): who wrote it, when,
/// and what it says. Kept apart from the task, so people commenting at
/// once on different Macs don't overwrite each other.
final class Comment {
  const Comment({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String taskId;

  /// The profile that wrote it.
  final String authorId;

  /// What it says, in Markdown: paragraphs, bold and links only (see
  /// [commentMarkdown]).
  final String body;

  final DateTime createdAt;

  /// The body as plain text, on one line: for an activity's preview.
  String get plainText =>
      RichTextModel.fromMarkdown(body).text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'authorId': authorId,
    'body': body,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Null for a record this version can't read (no task or author).
  static Comment? fromJson(String id, Map<String, Object?> json) {
    final task = json['taskId'], author = json['authorId'];
    if (task is! String || author is! String) return null;
    return Comment(
      id: id,
      taskId: task,
      authorId: author,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// A comment's Markdown with anything but paragraphs, bold and links taken
/// out (kept as plain text): headings, italics, strikethrough, lists.
/// Comments typed in the app can only have those; this holds for ones that
/// arrive another way (an assistant, another version of the app).
String commentMarkdown(String markdown) {
  final model = RichTextModel.fromMarkdown(markdown);
  // List items become plain lines (last first, so the earlier starts
  // stay put).
  for (final start in model.lineStarts.reversed) {
    final end = model.text.indexOf('\n', start);
    final line = model.text.substring(start, end == -1 ? null : end);
    if (listPrefixOf(line) case final p?) {
      model.replace(start, start + p.length, '');
    }
  }
  model
    ..headings = [for (final _ in model.headings) 0]
    ..marks = [
      for (final m in model.marks)
        if (m.type == MarkType.bold || m.type == MarkType.link) m,
    ];
  return model.toMarkdown().trim();
}
