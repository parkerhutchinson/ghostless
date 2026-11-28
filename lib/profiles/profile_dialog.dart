import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'profile.dart';
import 'profile_avatar.dart';
import 'profile_repository.dart';
import '../account/account_service.dart';
import '../widgets/selected_text.dart';
import '../widgets/watched.dart';

/// The Profile modal, opened from the avatar at the bottom of the sidebar:
/// your photo, name and details, and the account you're signed in with
/// (and signing out). Each Mac has one signed-in person: there's no
/// switching between profiles.
Future<void> showProfileDialog(
  BuildContext context,
  ProfileRepository profiles, {
  AccountService? accounts,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _ProfileDialog(profiles: profiles, accounts: accounts),
);

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profiles, this.accounts});
  final ProfileRepository profiles;
  final AccountService? accounts;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  ProfileRepository get _repo => widget.profiles;
  late final Profile _profile = _repo.current!;
  late final _name = AppTextController(text: _profile.name);

  late final _department = AppTextController(text: _profile.department);
  late final _jobTitle = AppTextController(text: _profile.jobTitle);
  late final _description = AppTextController(text: _profile.description);

  @override
  void dispose() {
    _name.dispose();
    _department.dispose();
    _jobTitle.dispose();
    _description.dispose();
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

  Future<void> _signOut() async {
    final accounts = widget.accounts;
    if (accounts == null) return;
    Navigator.pop(context);
    await accounts.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      // Their role at the right, level with the title.
      title: Row(
        children: [
          // Bold, like a project's header.
          const Expanded(
            child: Text(
              'Profile',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.accounts?.account case final account?)
            ValueListenableBuilder(
              valueListenable: account,
              builder: (context, value, _) => switch (value?.role) {
                final role? => Text(
                  roleLabel(role),
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.mutedText,
                  ),
                ),
                null => const SizedBox.shrink(),
              },
            ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Watched<List<Profile>>(
          watch: _repo.watch,
          current: _repo.all,
          builder: (context, all) {
            final me =
                all.where((p) => p.id == _profile.id).firstOrNull ?? _profile;
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
                  if (widget.accounts?.account.value case final account?) ...[
                    Divider(height: 8, color: context.colors.cardBorder),
                    _Label('Account'),
                    Row(
                      spacing: 10,
                      children: [
                        Icon(
                          Symbols.mail,
                          size: 18,
                          color: context.colors.mutedText,
                        ),
                        Expanded(
                          child: Text(
                            account.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _signOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.text,
                            side: BorderSide(color: context.colors.formBorder),
                          ),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
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
