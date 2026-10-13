import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/api/local_a1111_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/models/server.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/onboarding_prefs.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  static const _pageCount = 5;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingPrefsProvider.notifier).markWizardCompleted();
    if (mounted) context.go('/sessions');
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NeedHelpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [AppColors.gradientDarkStart, AppColors.gradientDarkEnd]
                : [AppColors.gradientLightStart, AppColors.gradientLightEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassTokens.spacingLg,
                  vertical: GlassTokens.spacingSm,
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _showHelp,
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Need Help'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (p) => setState(() => _currentPage = p),
                  children: [
                    const _WelcomePage(),
                    const _WhatIsA1111Page(),
                    _LocalNetworkPage(onHelp: _showHelp),
                    _ServerSetupPage(onHelp: _showHelp, onSaved: _next),
                    const _AllSetPage(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GlassTokens.spacingLg,
                  GlassTokens.spacingMd,
                  GlassTokens.spacingLg,
                  GlassTokens.spacingXl,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: List.generate(
                        _pageCount,
                        (i) => Container(
                          width: i == _currentPage ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _next,
                      child: Text(_currentPage < _pageCount - 1
                          ? 'Next'
                          : 'Get Started'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassTokens.radiusXl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/icon/app_icon.png',
                    fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: GlassTokens.spacingXxl),
          Text('Welcome to\nA1111 Mini',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: GlassTokens.spacingLg),
          Text(
            'Your complete Stable Diffusion companion.\nGenerate stunning AI images from your phone.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
        ],
      ),
    );
  }
}

class _WhatIsA1111Page extends StatelessWidget {
  const _WhatIsA1111Page();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.computer, size: 64, color: AppColors.primary),
          const SizedBox(height: GlassTokens.spacingXxl),
          Text('What is Automatic1111?',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: GlassTokens.spacingLg),
          Text(
            'Automatic1111 (also called Stable Diffusion WebUI) is a popular '
            'open-source interface for running Stable Diffusion on your computer.\n\n'
            'This app connects to your A1111 server over your local network so '
            'you can generate images from your iPhone or iPad.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _LocalNetworkPage extends ConsumerStatefulWidget {
  final VoidCallback onHelp;
  const _LocalNetworkPage({required this.onHelp});

  @override
  ConsumerState<_LocalNetworkPage> createState() => _LocalNetworkPageState();
}

class _LocalNetworkPageState extends ConsumerState<_LocalNetworkPage> {
  bool _pinging = false;
  String? _pingResult;

  Future<void> _triggerPermission() async {
    setState(() {
      _pinging = true;
      _pingResult = null;
    });
    final client = LocalA1111Client(host: '192.168.1.1', port: 7860);
    try {
      await client.testConnection().timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                const ConnectionStatus(connected: false, error: 'timeout'),
          );
    } catch (_) {
      // expected
    } finally {
      client.dispose();
      if (mounted) {
        setState(() {
          _pinging = false;
          _pingResult =
              'Done. If iOS asked for Local Network access, tap Allow.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi_tethering,
              size: 56, color: AppColors.primary),
          const SizedBox(height: GlassTokens.spacingXl),
          Text('Allow Local Network',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: GlassTokens.spacingLg),
          Text(
            'iOS needs your permission to talk to devices on your Wi-Fi. '
            'Tap the button below — if a system dialog appears, choose Allow.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: GlassTokens.spacingXl),
          ElevatedButton.icon(
            onPressed: _pinging ? null : _triggerPermission,
            icon: _pinging
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find),
            label: Text(_pinging ? 'Checking…' : 'Trigger Network Prompt'),
          ),
          if (_pingResult != null) ...[
            const SizedBox(height: GlassTokens.spacingMd),
            Text(_pingResult!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: GlassTokens.spacingMd),
          TextButton.icon(
            onPressed: widget.onHelp,
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text('How does this work?'),
          ),
        ],
      ),
    );
  }
}

class _ServerSetupPage extends ConsumerStatefulWidget {
  final VoidCallback onHelp;
  final VoidCallback onSaved;
  const _ServerSetupPage({required this.onHelp, required this.onSaved});

  @override
  ConsumerState<_ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<_ServerSetupPage> {
  final _name = TextEditingController(text: 'My PC');
  final _host = TextEditingController();
  final _port = TextEditingController(text: '7860');
  bool _testing = false;
  bool _saving = false;
  ConnectionStatus? _result;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(_port.text.trim()) ?? 7860;
    setState(() {
      _testing = true;
      _result = null;
    });
    final client = LocalA1111Client(host: host, port: port);
    try {
      final r = await client.testConnection();
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) {
        setState(() => _result =
            ConnectionStatus(connected: false, error: e.toString()));
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final host = _host.text.trim();
    if (name.isEmpty || host.isEmpty) return;
    setState(() => _saving = true);
    final port = int.tryParse(_port.text.trim()) ?? 7860;
    final server = Server(
      id: const Uuid().v4(),
      name: name,
      host: host,
      port: port,
      isActive: false,
      createdAt: DateTime.now(),
    );
    final db = await ref.read(databaseProvider.future);
    await db.insert('servers', server.toMap());
    ref.read(activeServerProvider.notifier).setActive(server);
    ref.invalidate(serversListProvider);
    if (mounted) {
      setState(() => _saving = false);
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: GlassTokens.spacingXl),
          const Icon(Icons.dns, size: 48, color: AppColors.primary),
          const SizedBox(height: GlassTokens.spacingMd),
          Text('Add Your Server',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: GlassTokens.spacingSm),
          Text(
            'Optional — you can also add servers later from the Servers tab.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
          const SizedBox(height: GlassTokens.spacingXl),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. My PC',
            ),
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Host (IP or URL)',
              hintText: '192.168.1.10  or  http://my-pc.local',
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          TextField(
            controller: _port,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '7860',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          if (_result != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: (_result!.connected
                        ? AppColors.success
                        : AppColors.error)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _result!.connected
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: _result!.connected
                        ? AppColors.success
                        : AppColors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _result!.connected
                          ? 'Connected${_result!.currentModel != null ? " • ${_result!.currentModel}" : ""}'
                          : 'Failed: ${_result!.error ?? "unknown"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_testing ? 'Testing…' : 'Test'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: GlassTokens.spacingSm),
          TextButton.icon(
            onPressed: widget.onHelp,
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text('How do I find my IP?'),
          ),
        ],
      ),
    );
  }
}

class _AllSetPage extends StatelessWidget {
  const _AllSetPage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.sparkles,
              size: 56, color: AppColors.primary),
          const SizedBox(height: GlassTokens.spacingXl),
          Text("You're all set",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: GlassTokens.spacingLg),
          Text(
            "Tap Get Started to begin generating. You can add or change "
            "servers anytime from the Servers tab.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _NeedHelpSheet extends StatelessWidget {
  const _NeedHelpSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          GlassTokens.spacingLg,
          0,
          GlassTokens.spacingLg,
          GlassTokens.spacingXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connecting to A1111',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: GlassTokens.spacingMd),
            const _HelpStep(
              n: '1',
              title: 'Run A1111 with API enabled',
              body:
                  'Add the flags --api --listen to your webui-user launcher. '
                  '--listen makes the server reachable from other devices on '
                  'your network.',
            ),
            const _HelpStep(
              n: '2',
              title: 'Same Wi-Fi network',
              body:
                  'Your iPhone/iPad must be on the same Wi-Fi as the computer '
                  'running A1111. Hotspots and guest networks usually block '
                  'device-to-device traffic.',
            ),
            const _HelpStep(
              n: '3',
              title: "Find your computer's IP",
              body: 'On macOS: System Settings → Network → Wi-Fi → Details — '
                  'look for "IP address" (e.g. 192.168.1.10).\n\n'
                  'On Windows: open Command Prompt and run `ipconfig`. Look '
                  'for the IPv4 Address (e.g. 192.168.1.10).',
            ),
            const _HelpStep(
              n: '4',
              title: 'Use IP or URL',
              body: 'In the Host field you can enter either:\n'
                  '  • An IP: 192.168.1.10\n'
                  '  • A hostname: my-pc.local\n'
                  '  • A full URL: http://my-pc.local:7860\n\n'
                  'Default A1111 port is 7860.',
            ),
            const _HelpStep(
              n: '5',
              title: 'iOS Local Network permission',
              body:
                  'iOS shows a one-time prompt the first time the app touches '
                  'a device on your Wi-Fi. If you tapped Don\'t Allow, you '
                  'can re-enable it in iOS Settings → A1111 Mini → Local '
                  'Network.',
            ),
            const _HelpStep(
              n: '?',
              title: 'Still stuck?',
              body:
                  'Open Feature Requests from the side menu and submit a bug '
                  'report — include your OS, A1111 version, and what you tried.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  final String n;
  final String title;
  final String body;
  const _HelpStep(
      {required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(n,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
