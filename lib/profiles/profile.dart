import 'package:material_ui/material_ui.dart' show StringCharacters;

/// A person using the app (collection `profiles`, synced). Several people
/// may share one company account; each has a profile with a name, a photo,
/// their own theme, and a personal project for tasks outside the company's
/// shared projects.
final class Profile {
  const Profile({
    required this.id,
    this.name = '',
    this.department = '',
    this.jobTitle = '',
    this.description = '',
    this.imageFile,
    this.personalProjectId,
    this.theme = const {},
    this.favoriteProjects = const [],
    required this.createdAt,
  });

  /// The projects they've starred, in the order starred: listed under
  /// Favorites in their sidebar. Theirs alone, like the theme.
  final List<String> favoriteProjects;

  bool isFavorite(String projectId) => favoriteProjects.contains(projectId);

  final String id;

  /// Their full name, as typed ("Ada Lovelace").
  final String name;

  /// Their department or team ("Engineering").
  final String department;

  /// Their job title ("Lead engineer").
  final String jobTitle;

  /// A few words about them.
  final String description;

  /// The photo's file name in the app's profile image folder (see
  /// [ProfileRepository.imageFile]), or null for none.
  final String? imageFile;

  /// Their personal project ([Project.ownerId] is this profile's id).
  final String? personalProjectId;

  /// Their theme: the Settings values (accent, background), as stored by
  /// [SettingsRepository]. Empty means the defaults.
  final Map<String, Object?> theme;

  final DateTime createdAt;

  /// The name, trimmed; empty with no name.
  String get fullName => name.trim();

  /// The name to show: [fullName], or a stand-in while it has none.
  String get displayName => fullName.isEmpty ? 'Unnamed profile' : fullName;

  /// "AL": first letters of the first and last word of the name (one with
  /// a single word; empty with no name).
  String get initials {
    final words = fullName.split(RegExp(r'\s+'));
    if (words.first.isEmpty) return '';
    return [
      words.first,
      if (words.length > 1) words.last,
    ].map((w) => w.characters.first).join().toUpperCase();
  }

  Profile copyWith({
    String? name,
    String? department,
    String? jobTitle,
    String? description,
    // Object? so null can mean "remove it"; omitted keeps it.
    Object? imageFile = _keep,
    String? personalProjectId,
    Map<String, Object?>? theme,
    List<String>? favoriteProjects,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    department: department ?? this.department,
    jobTitle: jobTitle ?? this.jobTitle,
    description: description ?? this.description,
    imageFile: imageFile == _keep ? this.imageFile : imageFile as String?,
    personalProjectId: personalProjectId ?? this.personalProjectId,
    theme: theme ?? this.theme,
    favoriteProjects: favoriteProjects ?? this.favoriteProjects,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'department': department,
    'jobTitle': jobTitle,
    'description': description,
    'imageFile': imageFile,
    'personalProjectId': personalProjectId,
    'theme': theme,
    'favoriteProjects': favoriteProjects,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Tolerant of missing fields, like the other records.
  factory Profile.fromJson(String id, Map<String, Object?> json) => Profile(
    id: id,
    // Older profiles stored a first and last name separately.
    name:
        json['name'] as String? ??
        '${json['firstName'] as String? ?? ''} '
                '${json['lastName'] as String? ?? ''}'
            .trim(),
    department: json['department'] as String? ?? '',
    jobTitle: json['jobTitle'] as String? ?? '',
    description: json['description'] as String? ?? '',
    imageFile: json['imageFile'] as String?,
    personalProjectId: json['personalProjectId'] as String?,
    theme: switch (json['theme']) {
      final Map stored => {
        for (final MapEntry(:key, :value) in stored.entries)
          if (key is String) key: value,
      },
      _ => const {},
    },
    favoriteProjects: [
      ...?(json['favoriteProjects'] as List?)?.whereType<String>(),
    ],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

const _keep = Object();
