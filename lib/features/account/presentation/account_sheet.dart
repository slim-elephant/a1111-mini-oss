import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/auth/auth_service.dart';
import 'profile_avatar.dart';

Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _AccountSheet(),
  );
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet();

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  bool _busy = false;
  bool _showEmail = false;

  Future<void> _attempt(Future<void> Function(AuthService auth) action) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(authServiceProvider));
    } on AuthFailure catch (e) {
      if (!e.message.contains('cancelled')) _snack(e.message);
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final signedIn = user != null && !user.isAnonymous;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        MediaQuery.of(context).viewInsets.bottom + GlassTokens.spacingLg,
      ),
      child: SingleChildScrollView(
        child: AbsorbPointer(
          absorbing: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: ProfileAvatar(user: user, size: 72)),
              const SizedBox(height: GlassTokens.spacingMd),
              if (signedIn)
                ..._signedIn(user)
              else
                ..._signedOut(),
              if (_busy) ...[
                const SizedBox(height: GlassTokens.spacingMd),
                const Center(child: CircularProgressIndicator.adaptive()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _signedIn(User user) {
    final theme = Theme.of(context);
    final providers = user.providerData
        .map((p) => _providerName(p.providerId))
        .toSet()
        .join(', ');
    return [
      Text(
        user.displayName?.isNotEmpty == true
            ? user.displayName!
            : (user.email ?? 'Signed in'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      if (user.email != null && user.displayName?.isNotEmpty == true)
        Text(user.email!,
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
      if (providers.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Signed in with $providers',
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: GlassTokens.spacingXl),
      OutlinedButton.icon(
        icon: const Icon(CupertinoIcons.square_arrow_right),
        label: const Text('Sign Out'),
        onPressed: () => _attempt((auth) async {
          await auth.signOut();
          if (mounted) Navigator.pop(context);
        }),
      ),
      const SizedBox(height: GlassTokens.spacingSm),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
        onPressed: _confirmDelete,
        child: const Text('Delete Account'),
      ),
    ];
  }

  List<Widget> _signedOut() {
    final theme = Theme.of(context);
    return [
      Text('Sign in',
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Optional. Keeps your feature-request votes and account when you '
        'reinstall or switch devices. Your images stay on this device.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: GlassTokens.spacingLg),
      _ProviderButton(
        icon: Icons.apple,
        label: 'Continue with Apple',
        dark: true,
        onPressed: () => _attempt((auth) async {
          await auth.signInWithApple();
          _closeIfSignedIn();
        }),
      ),
      const SizedBox(height: GlassTokens.spacingSm),
      _ProviderButton(
        icon: Icons.g_mobiledata,
        label: 'Continue with Google',
        onPressed: () => _attempt((auth) async {
          await auth.signInWithGoogle();
          _closeIfSignedIn();
        }),
      ),
      const SizedBox(height: GlassTokens.spacingSm),
      if (!_showEmail)
        _ProviderButton(
          icon: CupertinoIcons.mail,
          label: 'Continue with Email',
          onPressed: () => setState(() => _showEmail = true),
        )
      else
        _EmailForm(
          onSubmit: (email, password, create) => _attempt((auth) async {
            if (create) {
              await auth.createEmailAccount(email, password);
            } else {
              await auth.signInWithEmail(email, password);
            }
            _closeIfSignedIn();
          }),
          onReset: (email) => _attempt((auth) async {
            await auth.sendPasswordReset(email);
            _snack('Password reset email sent to $email');
          }),
        ),
    ];
  }

  void _closeIfSignedIn() {
    final user = ref.read(authServiceProvider).currentUser;
    if (mounted && user != null && !user.isAnonymous) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and your feature-request '
          'activity. Images, sessions and servers on this device are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _attempt((auth) async {
      await auth.deleteAccount();
      if (mounted) Navigator.pop(context);
      _snack('Account deleted');
    });
  }

  static String _providerName(String id) {
    switch (id) {
      case 'apple.com':
        return 'Apple';
      case 'google.com':
        return 'Google';
      case 'password':
        return 'Email';
      default:
        return id;
    }
  }
}

class _ProviderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dark;
  final VoidCallback onPressed;

  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    // Apple's guideline: black button in light mode, white in dark mode.
    final inverted = dark && isDarkTheme;
    return SizedBox(
      height: 48,
      child: dark
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: inverted ? Colors.white : Colors.black,
                foregroundColor: inverted ? Colors.black : Colors.white,
              ),
              icon: Icon(icon, size: 22),
              label: Text(label),
              onPressed: onPressed,
            )
          : OutlinedButton.icon(
              icon: Icon(icon, size: 22),
              label: Text(label),
              onPressed: onPressed,
            ),
    );
  }
}

class _EmailForm extends StatefulWidget {
  final void Function(String email, String password, bool create) onSubmit;
  final void Function(String email) onReset;

  const _EmailForm({required this.onSubmit, required this.onReset});

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          autofocus: true,
        ),
        const SizedBox(height: GlassTokens.spacingSm),
        TextField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          autofillHints: [
            _create ? AutofillHints.newPassword : AutofillHints.password,
          ],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: GlassTokens.spacingMd),
        FilledButton(
          onPressed: _submit,
          child: Text(_create ? 'Create Account' : 'Sign In'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _create = !_create),
              child: Text(_create ? 'I have an account' : 'Create account'),
            ),
            if (!_create)
              TextButton(
                onPressed: () {
                  final email = _email.text.trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter your email first')),
                    );
                    return;
                  }
                  widget.onReset(email);
                },
                child: const Text('Forgot password?'),
              ),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    widget.onSubmit(email, password, _create);
  }
}
