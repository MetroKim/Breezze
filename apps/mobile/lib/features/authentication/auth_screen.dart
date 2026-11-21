import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

/// Auth screen — login + register in one premium glass card, wired to
/// the real backend session controller.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _mfaCode = TextEditingController();
  bool _registerMode = false;
  bool _mfaBusy = false;
  String? _mfaError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _mfaCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(authSessionProvider.notifier);
    if (_registerMode) {
      await controller.register(
        _email.text.trim(),
        _password.text,
        displayName: _displayName.text.trim().isEmpty
            ? null
            : _displayName.text.trim(),
      );
    } else {
      await controller.login(_email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authSessionProvider);
    final busy = auth is AuthSigningIn;
    final error = auth is AuthError ? auth.code : null;

    if (auth is AuthMfaRequired) return _buildMfaRequired(context, auth);
    if (auth is AuthMfaRecoveryCodes) return _buildRecoveryCodes(context, auth);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BzRibbonLogo(width: 120, color: theme.bzText1),
                  const SizedBox(height: 12),
                  Text(
                    _registerMode ? 'Create your account' : 'Welcome back',
                    style: theme.textTheme.displayMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Free. Every platform. One line.',
                    style: TextStyle(fontSize: BzType.body, color: theme.bzText2),
                  ),
                  const SizedBox(height: 32),
                  BzGlassContainer(
                    radius: BzRadius.card,
                    blur: 32,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_registerMode) ...[
                            _field(
                              controller: _displayName,
                              hint: 'Display name',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _field(
                            controller: _email,
                            hint: 'Email',
                            icon: Icons.mail_outline,
                            keyboard: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _password,
                            hint: 'Password',
                            icon: Icons.lock_outline,
                            obscure: true,
                          ),
                          const SizedBox(height: 20),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                _errorText(error),
                                style: TextStyle(
                                    fontSize: BzType.footnote,
                                    color: theme.bzError),
                              ),
                            ),
                          _SubmitButton(
                            label: _registerMode ? 'Sign up' : 'Log in',
                            busy: busy,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _registerMode = !_registerMode),
                    child: Text(
                      _registerMode
                          ? 'Have an account? Log in'
                          : 'New here? Create an account',
                      style: TextStyle(color: theme.bzText2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _runMfa(Future<void> Function() action) async {
    setState(() {
      _mfaBusy = true;
      _mfaError = null;
    });
    try {
      await action();
    } on BreezzeApiException catch (error) {
      if (mounted) setState(() => _mfaError = error.code);
    } catch (_) {
      if (mounted) setState(() => _mfaError = 'NETWORK_ERROR');
    } finally {
      if (mounted) setState(() => _mfaBusy = false);
    }
  }

  Widget _buildMfaRequired(BuildContext context, AuthMfaRequired auth) {
    final theme = Theme.of(context);
    final controller = ref.read(authSessionProvider.notifier);
    final setupStarted = auth.provisioningUri != null && auth.secret != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BzRibbonLogo(width: 104, color: theme.bzText1),
                  const SizedBox(height: 20),
                  Text(
                    auth.setupRequired ? 'Secure your administrator account' : 'Two-factor verification',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.setupRequired
                        ? 'Set up an authenticator before accessing administrator tools.'
                        : 'Enter the current code from your authenticator app, or use a recovery code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.bzText2),
                  ),
                  const SizedBox(height: 24),
                  BzGlassContainer(
                    radius: BzRadius.card,
                    blur: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (auth.setupRequired && !setupStarted) ...[
                            Text('Confirm your password to begin MFA enrollment.',
                                style: TextStyle(color: theme.bzText2)),
                            const SizedBox(height: 12),
                            _field(
                              controller: _password,
                              hint: 'Current password',
                              icon: Icons.lock_outline,
                              obscure: true,
                            ),
                            const SizedBox(height: 16),
                            _SubmitButton(
                              label: 'Set up authenticator',
                              busy: _mfaBusy,
                              onPressed: () => _runMfa(
                                () => controller.beginMfaSetup(_password.text),
                              ),
                            ),
                          ] else ...[
                            if (setupStarted) ...[
                              Text('Add this account to your authenticator app.',
                                  style: TextStyle(color: theme.bzText2)),
                              const SizedBox(height: 10),
                              SelectableText(auth.secret!,
                                  style: TextStyle(
                                    color: theme.bzText1,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  )),
                              const SizedBox(height: 8),
                              SelectableText(auth.provisioningUri!,
                                  style: TextStyle(fontSize: 11, color: theme.bzText2)),
                              const SizedBox(height: 16),
                            ],
                            _field(
                              controller: _mfaCode,
                              hint: '6-digit code or recovery code',
                              icon: Icons.verified_user_outlined,
                              keyboard: TextInputType.text,
                            ),
                            const SizedBox(height: 16),
                            _SubmitButton(
                              label: auth.setupRequired ? 'Verify and enable MFA' : 'Verify and continue',
                              busy: _mfaBusy,
                              onPressed: () => _runMfa(
                                () => auth.setupRequired
                                    ? controller.verifyMfaSetup(_mfaCode.text.trim())
                                    : controller.verifyMfa(_mfaCode.text.trim()),
                              ),
                            ),
                          ],
                          if (_mfaError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _mfaError == 'MFA_CODE_REPLAYED'
                                  ? 'That code has already been used. Wait for the next code.'
                                  : _mfaError == 'INVALID_CREDENTIALS'
                                      ? 'Password confirmation failed.'
                                      : 'Verification failed. Check the code and try again.',
                              style: TextStyle(color: theme.bzError),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _mfaBusy
                        ? null
                        : () => controller.signOut(),
                    child: Text('Sign out', style: TextStyle(color: theme.bzText2)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryCodes(BuildContext context, AuthMfaRecoveryCodes auth) {
    final theme = Theme.of(context);
    final controller = ref.read(authSessionProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BzRibbonLogo(width: 104, color: theme.bzText1),
                  const SizedBox(height: 20),
                  Text('Save your recovery codes',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Each code works once if you lose access to your authenticator. They will not be shown again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.bzText2),
                  ),
                  const SizedBox(height: 20),
                  BzGlassContainer(
                    radius: BzRadius.card,
                    blur: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: SelectableText(
                        auth.codes.join('\n'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.bzText1,
                          fontWeight: FontWeight.w700,
                          height: 1.8,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SubmitButton(
                    label: 'I have saved my codes',
                    busy: false,
                    onPressed: controller.completeMfaEnrollment,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(String code) {
    switch (code) {
      case 'EMAIL_TAKEN':
        return 'That email is already registered.';
      case 'INVALID_CREDENTIALS':
        return 'Wrong email or password.';
      case 'NETWORK_ERROR':
        return 'Cannot reach Breezze. Check your connection.';
      default:
        return 'Something went wrong. Try again.';
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: theme.bzSurface1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BzRadius.input),
          borderSide: BorderSide(color: theme.bzSeparator),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: theme.bzText1,
          borderRadius: BorderRadius.circular(BzRadius.button),
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.bzBackground,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: BzType.subheadline,
                    fontWeight: FontWeight.w600,
                    color: theme.bzBackground,
                  ),
                ),
        ),
      ),
    );
  }
}
