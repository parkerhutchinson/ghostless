import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../layout.dart';
import '../tasks/form_buttons.dart';
import '../widgets/selected_text.dart';
import 'account_service.dart';
import 'auth_backend.dart';
import 'code_boxes.dart';
import 'hosted_service.dart';

/// TEMPORARY: true while the sign-in animation is worked on, so pressing
/// "Email me a code" over and over sends nothing. Remove when it's done.
const _skipSendingCodes = true;

/// The app's front door while nobody's signed in: an email, then the
/// 6-digit code emailed to it. No passwords.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.accounts});
  final AccountService accounts;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = AppTextController();
  final _code = AppTextController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  /// Where the code was sent; null while asking for the email.
  String? _sentTo;
  bool _busy = false;
  String? _problem;

  /// Seconds until another code can be sent.
  int _wait = 0;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    // The last account that signed in here, to save typing it again.
    _email.text = widget.accounts.owner?.email ?? '';
    // Once it's laid out (focusing it before then asserts).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      // TEMPORARY (sign-in animation work): no email is sent. Put
      // sending back once the animation's done.
      if (_skipSendingCodes) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } else {
        await widget.accounts.sendCode(email);
      }
      if (!mounted) return;
      setState(() {
        _sentTo = email.toLowerCase();
        _code.clear();
      });
      _startWait();
      _codeFocus.requestFocus();
    } on AuthProblem catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final sentTo = _sentTo;
    final code = _code.text.trim();
    if (_busy || sentTo == null || code.length < HostedService.codeLength) {
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      // Signed in: the app replaces this page.
      await widget.accounts.verifyCode(sentTo, code);
    } on AuthProblem catch (e) {
      if (!mounted) return;
      setState(() => _problem = e.message);
      _code.clear();
      _codeFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startWait() {
    _countdown?.cancel();
    setState(() => _wait = 30);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  void _changeEmail() {
    _countdown?.cancel();
    setState(() {
      _sentTo = null;
      _problem = null;
      _wait = 0;
    });
    _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sentTo = _sentTo;
    final muted = TextStyle(fontSize: 13, color: colors.mutedText, height: 1.4);
    // The small links under the code: quieter than the button.
    final linkStyle = TextButton.styleFrom(
      foregroundColor: colors.mutedText,
      disabledForegroundColor: colors.placeholder,
      side: BorderSide(color: colors.formBorder),
      shape: formShape,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
    );
    return Padding(
      // Clear of the title bar strip (it drags the window).
      padding: const EdgeInsets.only(top: titleBarHeight),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: formRadius,
                border: Border.all(color: colors.cardBorder),
              ),
              // The card grows or shrinks to the step's height.
              child: AnimatedSize(
                duration: _stepDuration,
                curve: _stepCurve,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepSwitcher(
                      step: sentTo == null,
                      child: Padding(
                        key: ValueKey(sentTo == null),
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 16,
                          children: [
                            Text(
                              sentTo == null ? 'Sign in' : 'Check your email',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: colors.text,
                              ),
                            ),
                            Text(
                              sentTo == null
                                  ? 'Enter your email and we’ll send you a code. '
                                        'New here? This makes your account.'
                                  : 'Enter the ${HostedService.codeLength}-digit code '
                                        'we sent to $sentTo.',
                              style: muted,
                            ),
                            // Extra room above and below the field.
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: sentTo == null
                                  ? _field(
                                      controller: _email,
                                      focus: _emailFocus,
                                      hint: 'you@example.com',
                                      keyboard: TextInputType.emailAddress,
                                      onSubmitted: _sendCode,
                                    )
                                  : CodeBoxes(
                                      controller: _code,
                                      focus: _codeFocus,
                                      length: HostedService.codeLength,
                                      enabled: !_busy,
                                      onChanged: (text) {
                                        if (_problem != null) {
                                          setState(() => _problem = null);
                                        }
                                        // The whole code typed (or pasted): sign in
                                        // without a click.
                                        if (text.length ==
                                            HostedService.codeLength) {
                                          _verify();
                                        }
                                      },
                                      onSubmitted: _verify,
                                    ),
                            ),
                            if (_problem case final problem?)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 8,
                                children: [
                                  Icon(
                                    Symbols.error,
                                    size: 16,
                                    color: Colors.red.shade300,
                                  ),
                                  Expanded(
                                    child: Text(
                                      problem,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: colors.text,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            SizedBox(
                              height: formFieldHeight,
                              child: FilledButton(
                                style: formButtonStyle,
                                onPressed: _busy
                                    ? null
                                    : sentTo == null
                                    ? _sendCode
                                    : _verify,
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        sentTo == null
                                            ? 'Email me a code'
                                            : 'Sign in',
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _FooterSwitcher(
                      child: sentTo == null
                          ? const SizedBox(
                              key: ValueKey('none'),
                              width: double.infinity,
                            )
                          // A lighter band across the card's foot.
                          : ColoredBox(
                              key: const ValueKey('links'),
                              color: colors.card,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                                child: Row(
                                  spacing: 8,
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        style: linkStyle,
                                        onPressed: _busy ? null : _changeEmail,
                                        child: const Text(
                                          'Change email',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        style: linkStyle,
                                        onPressed: _busy || _wait > 0
                                            ? null
                                            : _sendCode,
                                        child: Text(
                                          _wait > 0
                                              ? 'Resend in ${_wait}s'
                                              : 'Resend code',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String hint,
    required TextInputType keyboard,
    required VoidCallback onSubmitted,
  }) {
    final style = TextStyle(fontSize: 13.5, color: context.colors.text);
    return TextField(
      controller: controller,
      focusNode: focus,
      enabled: !_busy,
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: false,
      textAlignVertical: TextAlignVertical.center,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      style: style,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: style.copyWith(color: context.colors.placeholder),
        // One height for every one-line field (CLAUDE.md).
        constraints: formFieldConstraints,
        contentPadding: const EdgeInsets.all(12),
        enabledBorder: context.colors.fieldBorder,
        disabledBorder: context.colors.fieldBorder,
        border: context.colors.fieldBorder,
      ),
      onChanged: (_) {
        if (_problem != null) setState(() => _problem = null);
      },
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

const _stepDuration = Duration(milliseconds: 420);
const _stepCurve = Curves.easeOutCubic;

/// How far below its place the new step's form starts, in pixels.
const _incomingRise = 100.0;

/// Moves from one step's form to the next: the old one slides up and out
/// while the new one slides up into its place.
class _StepSwitcher extends StatelessWidget {
  const _StepSwitcher({required this.step, required this.child});

  /// Which step is showing (the child's key): true for the email, false
  /// for the code. Onwards to the code, forms move up; back to the email,
  /// everything runs in reverse and they move down.
  final bool step;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _stepDuration,
    // The new step decides the height (the card animates to it); the old
    // one lies over the top while it leaves.
    layoutBuilder: (current, previous) => Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final old in previous)
          Positioned(left: 0, top: 0, right: 0, child: old),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) {
      // Compare the values: ValueKey<bool> never equals ValueKey<Object>.
      final incoming = (child.key as ValueKey?)?.value == step;
      // 1 moving onwards (up), -1 going back (down).
      final direction = step ? -1.0 : 1.0;
      // The old form goes first: out over the first 60%. The new one
      // follows: in over the last 75%.
      // (Outgoing, the animation runs backwards, 1 to 0.)
      final timed = CurvedAnimation(
        parent: animation,
        curve: incoming
            ? const Interval(0.25, 1, curve: _stepCurve)
            : const Interval(0.4, 1, curve: Curves.easeInCubic),
      );
      if (incoming) {
        // Starts 100px below where it lands (above, going back), closing
        // to 0 as it fades in.
        return FadeTransition(
          opacity: timed,
          child: AnimatedBuilder(
            animation: timed,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, direction * _incomingRise * (1 - timed.value)),
              child: child,
            ),
            child: child,
          ),
        );
      }
      return FadeTransition(
        opacity: timed,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, -0.35 * direction),
            end: Offset.zero,
          ).animate(timed),
          child: child,
        ),
      );
    },
    child: child,
  );
}

/// The band of links at the card's foot: slides up into view from the
/// card's bottom edge as the card grows (and back down when it goes).
class _FooterSwitcher extends StatelessWidget {
  const _FooterSwitcher({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _stepDuration,
    switchInCurve: _stepCurve,
    // Leaving, the animation runs backwards: the flipped curve makes it
    // move straight away (the same curve would hold still, then drop).
    switchOutCurve: _stepCurve.flipped,
    // The leaving band takes no room, so the card shrinks while it slides
    // out (not after); the card's edge clips it.
    layoutBuilder: (current, previous) => Stack(
      clipBehavior: Clip.none,
      children: [
        for (final old in previous)
          Positioned(left: 0, top: 0, right: 0, child: old),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => ClipRect(
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );
}
