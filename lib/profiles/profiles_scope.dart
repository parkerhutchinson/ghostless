import 'dart:io';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../widgets/left_menu_button.dart';

import 'profile.dart';
import 'profile_avatar.dart';
import 'profile_repository.dart';

/// Every profile, for widgets anywhere in the app (task cards, the list,
/// the task form) to show assignees. Sits above the app's navigator, so
/// dialogs see it too.
class ProfilesScope extends InheritedWidget {
  const ProfilesScope({
    super.key,
    required this.profiles,
    required this.imageOf,
    required super.child,
  });

  /// Keeps [child] supplied with [repo]'s profiles as they change.
  static Widget watching(ProfileRepository repo, {required Widget child}) =>
      StreamBuilder<List<Profile>>(
        stream: repo.watch(),
        initialData: repo.all(),
        builder: (context, snap) => ProfilesScope(
          profiles: snap.requireData,
          imageOf: (p) => switch (p.imageFile) {
            final name? => repo.imageFile(name),
            null => null,
          },
          child: child,
        ),
      );

  /// Oldest first.
  final List<Profile> profiles;

  /// A profile's photo file, or null when it has none.
  final File? Function(Profile) imageOf;

  /// Null outside a scope (e.g. in tests that don't set one up).
  static ProfilesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfilesScope>();

  /// The profile with [id], if it exists.
  Profile? find(String? id) =>
      id == null ? null : profiles.where((p) => p.id == id).firstOrNull;

  @override
  bool updateShouldNotify(ProfilesScope old) => old.profiles != profiles;
}

/// The avatar of the profile a task is assigned to, with their name on
/// hover. Nothing when [assigneeId] is null or names no profile.
class AssigneeAvatar extends StatelessWidget {
  const AssigneeAvatar({super.key, required this.assigneeId, this.size = 20});

  final String? assigneeId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = ProfilesScope.maybeOf(context);
    final profile = scope?.find(assigneeId);
    if (scope == null || profile == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'Assigned to ${profile.displayName}',
      child: ProfileAvatar(
        profile: profile,
        image: scope.imageOf(profile),
        size: size,
      ),
    );
  }
}

/// An empty profile picture: assigned to nobody (or to a profile that's
/// gone).
class UnassignedAvatar extends StatelessWidget {
  const UnassignedAvatar({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    // The glyph's circle fills only 20/24 of its box: scaled up so the
    // circle itself is [size], like the done checkbox.
    child: OverflowBox(
      maxWidth: size * 1.2,
      maxHeight: size * 1.2,
      child: Icon(
        Symbols.account_circle,
        size: size * 1.2,
        color: context.colors.placeholder,
      ),
    ),
  );
}

/// The assignee's avatar as a button (a blank profile icon when nobody's
/// assigned) that opens a menu of every profile to assign the task to.
/// Without [onChanged] it's just the avatar.
class AssigneeButton extends StatelessWidget {
  const AssigneeButton({
    super.key,
    required this.assigneeId,
    required this.onChanged,
    this.size = 20,
  });

  final String? assigneeId;

  /// The picked profile's id, or null for Unassigned.
  final ValueChanged<String?>? onChanged;
  final double size;

  /// Menu value for Unassigned (a null value would mean "dismissed").
  static const _nobody = '';

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final scope = ProfilesScope.maybeOf(context);
    if (onChanged == null || scope == null) {
      return AssigneeAvatar(assigneeId: assigneeId, size: size);
    }
    final current = scope.find(assigneeId);
    return LeftMenuButton<String>(
      tooltip: current == null
          ? 'Assign'
          : 'Assigned to ${current.displayName}',
      padding: const EdgeInsets.all(2),
      style: IconButton.styleFrom(
        minimumSize: Size.square(size + 4),
        fixedSize: Size.square(size + 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: current == null
          ? UnassignedAvatar(size: size)
          : ProfileAvatar(
              profile: current,
              image: scope.imageOf(current),
              size: size,
            ),
      constraints: const BoxConstraints(minWidth: 200),
      onSelected: (id) => onChanged(id == _nobody ? null : id),
      itemBuilder: (context) => [
        _item(
          context,
          value: _nobody,
          selected: current == null,
          leading: Icon(
            Symbols.person_off,
            size: 18,
            color: context.colors.mutedText,
          ),
          label: 'Unassigned',
        ),
        for (final p in scope.profiles)
          _item(
            context,
            value: p.id,
            selected: p.id == current?.id,
            leading: ProfileAvatar(
              profile: p,
              image: scope.imageOf(p),
              size: 20,
            ),
            label: p.displayName,
          ),
      ],
    );
  }

  PopupMenuItem<String> _item(
    BuildContext context, {
    required String value,
    required bool selected,
    required Widget leading,
    required String label,
  }) => PopupMenuItem(
    value: value,
    height: 36,
    child: Row(
      spacing: 10,
      children: [
        leading,
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (selected) Icon(Symbols.check, size: 16, color: context.colors.text),
      ],
    ),
  );
}
