import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'profile.dart';
import 'profile_avatar.dart';
import 'profile_repository.dart';
import '../widgets/selected_text.dart';

/// The Profile modal, opened from the avatar at the bottom of the sidebar:
/// the current profile's photo and name, and the other profiles on this
/// Mac to switch to (or a new one to create).
Future<void> showProfileDialog(
  BuildContext context,
  ProfileRepository profiles,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _ProfileDialog(profiles: profiles),
);

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profiles});
  final ProfileRepository profiles;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  ProfileRepository get _repo => widget.profiles;
  late final Profile _profile = _repo.current!;
  late final _name = AppTextController(text: _profile.name);

  /// The other profiles' list, which scrolls once it's [_othersMaxHeight]
  /// tall.
  final _othersScroll = ScrollController();
  static const _othersMaxHeight = 2.5 * 44.0;
  late final _department = AppTextController(text: _profile.department);
  late final _jobTitle = AppTextController(text: _profile.jobTitle);
  late final _description = AppTextController(text: _profile.description);

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    _jobTitle.dispose();
    _description.dispose();
    _othersScroll.dispose();
    super.dispose();
  }

  /// Saves the text fields (the photo is saved as soon as it's picked).
  void _save() {
    final latest = _repo.get(_profile.id) ?? _profile;
    _repo.save(
      latest.copyWith(
        name: _name.text.trim(),
        department: _department.text.trim(),
        jobTitle: _jobTitle.text.trim(),
        description: _description.text.trim(),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _pickPhoto() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (file == null) return;
    await _repo.setImage(_profile.id, file.path);
  }

  void _switchTo(Profile other) {
    _repo.switchTo(other.id);
    Navigator.pop(context);
  }

  Future<void> _newProfile() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewProfileDialog(),
    );
    if (name == null || !mounted) return;
    _repo.create(name: name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: const Text('Profile'),
      content: SizedBox(
        width: 400,
        child: StreamBuilder<List<Profile>>(
          stream: _repo.watch(),
          initialData: _repo.all(),
          builder: (context, snap) {
            final all = snap.requireData;
            final me =
                all.where((p) => p.id == _profile.id).firstOrNull ?? _profile;
            final others = all.where((p) => p.id != me.id).toList();
            // Scrolls when the window is too short for the whole form.
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  _photoRow(me),
                  _field(_name, 'Full name', autofocus: true),
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(child: _field(_department, 'Department / team')),
                      Expanded(child: _field(_jobTitle, 'Job title')),
                    ],
                  ),
                  _field(_description, 'Description', multiline: true),
                  Divider(height: 8, color: context.colors.cardBorder),
                  _Label('Switch profile'),
                  if (others.isEmpty)
                    Text(
                      'No other profiles yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.mutedText,
                      ),
                    ),
                  if (others.isNotEmpty) _otherProfiles(others),
                  OutlinedButton.icon(
                    onPressed: _newProfile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.text,
                      side: BorderSide(color: context.colors.formBorder),
                    ),
                    icon: Icon(Symbols.person_add, size: 18),
                    label: const Text('New profile'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _photoRow(Profile me) => Row(
    spacing: 16,
    children: [
      ProfileAvatar(
        profile: me,
        image: me.imageFile == null ? null : _repo.imageFile(me.imageFile!),
        size: 64,
      ),
      OutlinedButton(
        onPressed: _pickPhoto,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.text,
          side: BorderSide(color: context.colors.formBorder),
        ),
        child: Text(me.imageFile == null ? 'Upload photo' : 'Replace photo'),
      ),
      if (me.imageFile != null)
        TextButton(
          onPressed: () => _repo.removeImage(me.id),
          child: const Text('Remove'),
        ),
    ],
  );

  /// A text field with its label above it, like the task form's (not
  /// inside the box). Enter saves, except in a [multiline] one, where it
  /// starts a new line.
  Widget _field(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    bool multiline = false,
  }) => _Labeled(
    label,
    TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 6 : 1,
      keyboardType: multiline ? TextInputType.multiline : null,
      style: const TextStyle(fontSize: 13.5),
      decoration: _fieldDecoration(context),
      onSubmitted: multiline ? null : (_) => _save(),
    ),
  );

  /// The other profiles, in a box at most [_othersMaxHeight] tall that
  /// scrolls past that, its scrollbar always showing so it's clear there's
  /// more. (The dialog's own scroll is for a window too short for it.)
  Widget _otherProfiles(List<Profile> others) => Container(
    constraints: const BoxConstraints(maxHeight: _othersMaxHeight),
    decoration: BoxDecoration(
      border: Border.all(color: context.colors.cardBorder),
      borderRadius: formRadius,
    ),
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _othersScroll,
        thumbVisibility: true,
        child: ListView(
          controller: _othersScroll,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(10, 2, 14, 2),
          children: [for (final p in others) _otherProfile(p)],
        ),
      ),
    ),
  );

  Widget _otherProfile(Profile p) => Row(
    spacing: 10,
    children: [
      ProfileAvatar(
        profile: p,
        image: p.imageFile == null ? null : _repo.imageFile(p.imageFile!),
      ),
      Expanded(
        child: Text(
          p.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5),
        ),
      ),
      TextButton(onPressed: () => _switchTo(p), child: const Text('Switch')),
    ],
  );
}

/// Asks for a new profile's name.
class _NewProfileDialog extends StatefulWidget {
  const _NewProfileDialog();

  @override
  State<_NewProfileDialog> createState() => _NewProfileDialogState();
}

class _NewProfileDialogState extends State<_NewProfileDialog> {
  final _name = AppTextController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canCreate => _name.text.trim().isNotEmpty;

  void _create() {
    if (!_canCreate) return;
    Navigator.pop(context, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: const Text('New profile'),
      content: SizedBox(
        width: 360,
        child: _Labeled(
          'Full name',
          TextField(
            controller: _name,
            autofocus: true,
            decoration: _fieldDecoration(context),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canCreate ? _create : null,
          child: const Text('Create and switch'),
        ),
      ],
    );
  }
}

/// A profile field's box: a plain outlined input, no label inside it (the
/// label goes above: [_Labeled]).
InputDecoration _fieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  contentPadding: const EdgeInsets.all(12),
  enabledBorder: context.colors.fieldBorder,
  border: context.colors.fieldBorder,
);

/// [field] with its [label] above it, as on the task form.
class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.field);
  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [_Label(label), field],
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
