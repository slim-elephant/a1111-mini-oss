import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uuid/uuid.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/generation_backend.dart';
import '../../../core/models/server.dart';
import '../../../core/on_device/apple_ml_downloader.dart';
import '../../../core/on_device/apple_ml_models.dart';
import '../../../core/api/comfyui_client.dart';
import '../../../core/api/local_a1111_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/remote/remote_access.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/adaptive_scaffold.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/platform_icon.dart';

Future<ConnectionStatus> _testServerConnection(
  WidgetRef ref,
  Server server,
) async {
  // Same gate as connectionStatusProvider: don't probe a relay we can't use.
  if (server.isRemote && ref.read(enabledRemoteAccessProvider) == null) {
    return const ConnectionStatus(
      connected: false,
      error: kRelayUnsupportedMessage,
    );
  }
  if (server.provider == GenerationBackend.comfyui) {
    final client = ComfyUiClient(
      host: server.host,
      port: server.port,
      authToken: server.authToken,
      backendHeader: server.provider.id,
    );
    try {
      return await client.testConnection();
    } finally {
      client.dispose();
    }
  }
  final client = LocalA1111Client(
    host: server.host,
    port: server.port,
    authToken: server.authToken,
    backendHeader: server.provider.id,
  );
  try {
    return await client.testConnection();
  } finally {
    client.dispose();
  }
}

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversListProvider);
    final remote = ref.watch(enabledRemoteAccessProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Servers',

                actions: [
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'Setup Guide',
                    onPressed: () => _showSetupGuide(context, remote: remote != null),
                  ),
                  if (remote != null)
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Pair with Connect',
                      onPressed: () => _pairWithConnect(context, ref, remote),
                    ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showServerEditor(context, ref),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
              sliver: SliverToBoxAdapter(
                child: Text(
                  remote != null
                      ? 'Local LAN servers, or pair LM Mini Connect for remote access'
                      : 'A1111 / Forge or ComfyUI on your local network',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: GlassTokens.spacingLg)),
            servers.when(
              data: (list) {
                if (list.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dns_outlined, size: 64,
                            color: AppColors.primary.withValues(alpha: 0.4)),
                          const SizedBox(height: GlassTokens.spacingLg),
                          Text('No servers configured', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: GlassTokens.spacingSm),
                          Text('Add an A1111 or ComfyUI server to start generating',
                            style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: GlassTokens.spacingXl),
                          ElevatedButton.icon(
                            onPressed: () => _showServerEditor(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Server'),
                          ),
                          if (remote != null) ...[
                            const SizedBox(height: GlassTokens.spacingMd),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _pairWithConnect(context, ref, remote),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Pair with Connect'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _ServerCard(
                        key: ValueKey(list[index].id),
                        server: list[index],
                        onTap: () => _showServerEditor(context, ref, server: list[index]),
                        onActivate: () async {
                          await ref
                              .read(activeServerProvider.notifier)
                              .setActive(list[index]);
                          ref.invalidate(serversListProvider);
                        },
                        onDelete: () => _deleteServer(context, ref, list[index]),
                      ),
                      childCount: list.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
            ),
            // Help section removed - now accessible via ? icon
          ],
        ),
      ),
    );
  }

  void _showSetupGuide(BuildContext context, {required bool remote}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.help_outline, color: AppColors.primary, size: 24),
                  const SizedBox(width: 10),
                  Text('Setup Guide', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 20),
              const _HelpStep(number: '1', text: 'Install Automatic1111 / Forge (--api, port 7860) or ComfyUI (port 8188) on your computer'),
              const _HelpStep(number: '2', text: 'A1111: start with --api.\nComfyUI: start normally and save the workflows you want to use.'),
              const _HelpStep(number: '3', text: 'Find your computer\'s IP address (e.g., 192.168.1.100)'),
              const _HelpStep(number: '4', text: 'Add the server above. Choose the matching provider and port (7860 or 8188)'),
              const _HelpStep(number: '5', text: 'For ComfyUI, pick a saved workflow in Settings → Providers'),
              _HelpStep(
                number: '6',
                text: remote
                    ? 'On the same Wi‑Fi, use your computer IP. Away from home, tap Pair with Connect and scan the QR in LM Mini Connect.'
                    : 'Your phone and computer must be on the same Wi‑Fi. Start A1111 or ComfyUI with --listen so other devices can reach it.',
              ),
              if (remote) ...[
                const SizedBox(height: 16),
                Text(
                  'Tip: Connect must be running with the A1111 (7860) or ComfyUI (8188) address filled in. Remote traffic uses your private relay.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pairWithConnect(
    BuildContext context,
    WidgetRef ref,
    RemoteAccess remote,
  ) async {
    final paired = await remote.pair(context);
    if (paired == null || paired.isEmpty) return;
    final db = await ref.read(databaseProvider.future);
    for (final server in paired) {
      await db.insert('servers', server.toMap());
    }
    // Let Connect finish the pairing host-status round-trip before the
    // server card and chat both probe ComfyUI / A1111 through the relay.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await ref.read(activeServerProvider.notifier).setActive(paired.first);
    ref.invalidate(serversListProvider);
    if (context.mounted) {
      final names = paired.map((s) => s.name).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired $names')),
      );
    }
  }

  void _showServerEditor(BuildContext context, WidgetRef ref, {Server? server}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ServerEditorSheet(
        server: server,
        onSave: (s) async {
          final db = await ref.read(databaseProvider.future);
          if (server != null) {
            // Probes write last_connected_at; keep theirs, not the
            // editor's possibly older copy.
            final row = s.toMap()..remove('last_connected_at');
            await db.update('servers', row, where: 'id = ?', whereArgs: [s.id]);
            // Clients hold the old host/port/token until the active copy
            // is replaced.
            if (ref.read(activeServerProvider)?.id == s.id) {
              if (ref.read(activeProviderProvider).requiresRemoteServer) {
                await ref.read(activeServerProvider.notifier).setActive(s);
              } else {
                ref.read(activeServerProvider.notifier).refreshIfActive(s);
              }
            }
          } else {
            await db.insert('servers', s.toMap());
            final count = (await db.query('servers')).length;
            final sameProvider = await db.query(
              'servers',
              where: 'provider = ?',
              whereArgs: [s.provider.id],
            );
            if (count == 1 ||
                (sameProvider.length == 1 &&
                    ref.read(activeProviderProvider) == s.provider)) {
              await ref.read(activeServerProvider.notifier).setActive(s);
            }
          }
          ref.invalidate(serversListProvider);
        },
        onDelete: server == null
            ? null
            : () async {
                Navigator.pop(context);
                await _deleteServer(context, ref, server);
              },
      ),
    );
  }

  Future<void> _deleteServer(BuildContext context, WidgetRef ref, Server server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Delete "${server.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await ref.read(databaseProvider.future);
      await db.delete('servers', where: 'id = ?', whereArgs: [server.id]);
      if (server.isActive) {
        final remaining = await db.query(
          'servers',
          where: 'provider = ?',
          whereArgs: [server.provider.id],
          orderBy: 'last_connected_at DESC, created_at DESC',
        );
        if (remaining.isNotEmpty) {
          await ref
              .read(activeServerProvider.notifier)
              .setActive(Server.fromMap(remaining.first));
        } else {
          await ref.read(activeServerProvider.notifier).clear();
        }
      }
      await _leaveEmptyBackend(ref);
      ref.invalidate(serversListProvider);
    }
  }

  /// After deleting the last server of the selected backend, move to one
  /// that can still generate. With nothing usable the backend stays and its
  /// status reads "No server configured".
  Future<void> _leaveEmptyBackend(WidgetRef ref) async {
    final backend = ref.read(activeProviderProvider);
    if (!backend.requiresRemoteServer) return;
    final db = await ref.read(databaseProvider.future);
    final same = await db.query(
      'servers',
      where: 'provider = ?',
      whereArgs: [backend.id],
      limit: 1,
    );
    if (same.isNotEmpty) return;
    final other = await db.query(
      'servers',
      orderBy: 'last_connected_at DESC, created_at DESC',
      limit: 1,
    );
    if (other.isNotEmpty) {
      await ref
          .read(activeProviderProvider.notifier)
          .set(Server.fromMap(other.first).provider);
      return;
    }
    final model =
        AppleMlCatalog.byId(ref.read(selectedAppleMlModelIdProvider));
    if (model != null && await AppleMlDownloader().isInstalled(model)) {
      await ref
          .read(activeProviderProvider.notifier)
          .set(GenerationBackend.appleMl);
    }
  }
}

class _ServerCard extends ConsumerStatefulWidget {
  final Server server;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const _ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  ConsumerState<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<_ServerCard> {
  ConnectionStatus? _status;
  bool _testing = true;
  DateTime? _lastConnectedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _testConnection(initial: true);
    });
  }

  @override
  void didUpdateWidget(covariant _ServerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.baseUrl != widget.server.baseUrl ||
        oldWidget.server.authToken != widget.server.authToken ||
        oldWidget.server.provider != widget.server.provider) {
      _testConnection();
    }
  }

  Future<void> _testConnection({bool initial = false}) async {
    if (initial) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
    } else if (mounted) {
      setState(() => _testing = true);
    }
    try {
      final server = widget.server;
      final status = await _testServerConnection(ref, server);
      DateTime? connectedAt;
      if (status.connected) {
        final db = await ref.read(databaseProvider.future);
        connectedAt = await markServerConnected(db, server.id);
      }
      if (mounted) {
        setState(() {
          _status = status;
          _testing = false;
          if (connectedAt != null) _lastConnectedAt = connectedAt;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _status = ConnectionStatus(connected: false, error: 'Test failed: $e');
        _testing = false;
      });
    }
  }

  /// "Checked just now" after a good probe, otherwise when it last worked.
  String? get _checkedLabel {
    final at = _lastConnectedAt ?? widget.server.lastConnectedAt;
    if (at == null) return null;
    final ago = DateTime.now().difference(at) < const Duration(minutes: 1)
        ? 'just now'
        : timeago.format(at);
    return _status?.connected == true ? 'Checked $ago' : 'Last connected $ago';
  }

  @override
  Widget build(BuildContext context) {
    // A remembered server isn't in use while another backend is selected.
    final isActive = widget.server.isActive &&
        ref.watch(activeProviderProvider) == widget.server.provider;
    final checked = _testing ? null : _checkedLabel;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: GlassTokens.spacingMd),
      onTap: widget.onTap,
      onLongPress: widget.onDelete,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
            ),
            child: _testing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.dns, color: _statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.server.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.server.provider.label} · ${widget.server.displayAddress}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (widget.server.isRemote)
                      const StatusBadge(
                        label: 'Remote',
                        color: AppColors.primary,
                        icon: Icons.cloud,
                      ),
                    if (isActive)
                      const StatusBadge(
                        label: 'Active',
                        color: AppColors.success,
                        icon: Icons.check_circle,
                      ),
                  ],
                ),
                if (_status != null &&
                    _status!.connected &&
                    _status!.currentModel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Model: ${_status!.currentModel}',
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_status?.connected == true && _status!.warning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _status!.warning!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.warning),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_status != null &&
                    !_status!.connected &&
                    _status!.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _status!.error!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.error),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (checked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      checked,
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Server actions',
            padding: EdgeInsets.zero,
            onSelected: (value) {
              switch (value) {
                case 'activate':
                  widget.onActivate();
                case 'test':
                  _testConnection();
                case 'delete':
                  widget.onDelete();
              }
            },
            itemBuilder: (context) => [
              if (!isActive)
                const PopupMenuItem(
                  value: 'activate',
                  child: Text('Set as active'),
                ),
              const PopupMenuItem(
                value: 'test',
                child: Text('Test connection'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    if (_testing) return AppColors.warning;
    if (_status == null) return AppColors.textSecondaryLight;
    if (!_status!.connected) return AppColors.error;
    return _status!.warning != null ? AppColors.warning : AppColors.success;
  }
}

class _ServerEditorSheet extends ConsumerStatefulWidget {
  final Server? server;
  final Future<void> Function(Server) onSave;
  final Future<void> Function()? onDelete;

  const _ServerEditorSheet({
    this.server,
    required this.onSave,
    this.onDelete,
  });

  @override
  ConsumerState<_ServerEditorSheet> createState() => _ServerEditorSheetState();
}

class _ServerEditorSheetState extends ConsumerState<_ServerEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  late GenerationBackend _provider;
  bool _testing = false;
  bool _obscureToken = true;
  ConnectionStatus? _testResult;

  @override
  void initState() {
    super.initState();
    _provider = widget.server?.provider ?? GenerationBackend.a1111;
    _nameController = TextEditingController(text: widget.server?.name ?? '');
    _hostController = TextEditingController(text: widget.server?.host ?? '');
    _portController = TextEditingController(
      text: '${widget.server?.port ?? _provider.defaultPort}',
    );
    _tokenController = TextEditingController(text: widget.server?.authToken ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(enabledRemoteAccessProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        MediaQuery.of(context).viewInsets.bottom + GlassTokens.spacingLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.server != null ? 'Edit Server' : 'Add Server',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: GlassTokens.spacingLg),
            DropdownButtonFormField<GenerationBackend>(
              value: _provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: GenerationBackend.values
                  .where((p) => p.requiresRemoteServer)
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text('${p.label} — ${p.subtitle}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _provider = value;
                  if (widget.server == null) {
                    _portController.text = '${value.defaultPort}';
                  }
                });
              },
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Server Name',
                hintText: 'My PC',
              ),
              autofocus: widget.server == null,
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _hostController,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Host / URL',
                hintText: remote?.hostHint ?? '192.168.1.100',
                alignLabelWithHint: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '7860',
              ),
              keyboardType: TextInputType.number,
            ),
            if (remote != null) ...[
              const SizedBox(height: GlassTokens.spacingMd),
              TextField(
                controller: _tokenController,
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                minLines: _obscureToken ? 1 : 2,
                maxLines: _obscureToken ? 1 : 3,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Connect token (optional)',
                  hintText: '64-character token from the Connect QR',
                  helperText: remote.tokenHelper(_tokenController.text.trim()),
                  alignLabelWithHint: true,
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? 'Show token' : 'Hide token',
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                    icon: PlatformIcon(
                      material: _obscureToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      cupertino: _obscureToken
                          ? CupertinoIcons.eye
                          : CupertinoIcons.eye_slash,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: GlassTokens.spacingLg),
            // Test connection
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find, size: 18),
                label: Text(_testing ? 'Testing...' : 'Test Connection'),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _testResultColor == AppColors.success
                        ? Icons.check_circle
                        : _testResultColor == AppColors.warning
                            ? Icons.warning_amber_rounded
                            : Icons.error,
                    color: _testResultColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _testResultText,
                      style: TextStyle(color: _testResultColor, fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (!_testResult!.connected && remote != null) ...[
                const SizedBox(height: GlassTokens.spacingMd),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : () => _rescanConnectQr(remote),
                    icon: const PlatformIcon(
                      material: Icons.qr_code_scanner,
                      cupertino: CupertinoIcons.qrcode_viewfinder,
                    ),
                    label: const Text('Rescan Connect QR'),
                  ),
                ),
              ],
            ],
            const SizedBox(height: GlassTokens.spacingXl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(widget.server != null ? 'Save Changes' : 'Add Server'),
              ),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: GlassTokens.spacingSm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => widget.onDelete!(),
                  icon: const PlatformIcon(
                    material: Icons.delete_outline,
                    cupertino: CupertinoIcons.delete,
                    color: AppColors.error,
                  ),
                  label: const Text(
                    'Delete Server',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ),
            ],
            const SizedBox(height: GlassTokens.spacingMd),
          ],
        ),
      ),
    );
  }

  Color get _testResultColor {
    final r = _testResult!;
    if (!r.connected) return AppColors.error;
    return r.warning != null ? AppColors.warning : AppColors.success;
  }

  String get _testResultText {
    final r = _testResult!;
    if (!r.connected) return r.error ?? 'Connection failed';
    if (r.warning != null) return r.warning!;
    return r.currentModel != null
        ? 'Connected! Model: ${r.currentModel}'
        : 'Connected!';
  }

  Future<void> _rescanConnectQr(RemoteAccess remote) async {
    final pairing = await remote.scanQr(context);
    if (!mounted || pairing == null) return;
    setState(() {
      _hostController.text = pairing.url;
      _tokenController.text = pairing.token;
      _portController.text = '${_provider.defaultPort}';
      _obscureToken = false;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _provider == GenerationBackend.comfyui
            ? 'Remote ComfyUI'
            : 'Remote A1111';
      }
      _testResult = null;
    });
    _hostController.selection = const TextSelection.collapsed(offset: 0);
    _tokenController.selection = const TextSelection.collapsed(offset: 0);
    await _testConnection();
  }

  Future<void> _testConnection() async {
    final rawHost = _hostController.text.trim();
    final token = _tokenController.text.trim();
    final remote = ref.read(enabledRemoteAccessProvider);
    final canonical = remote?.canonicalizeUrl(rawHost);
    final host = canonical ?? rawHost;
    if (canonical != null && canonical != rawHost) {
      _hostController.text = canonical;
    }
    final hint = remote?.fieldHint(host, token);
    if (hint != null) {
      setState(() {
        _testResult = ConnectionStatus(connected: false, error: hint);
        _testing = false;
      });
      return;
    }
    final port = int.tryParse(_portController.text.trim()) ??
        _provider.defaultPort;
    if (host.isEmpty) return;

    setState(() { _testing = true; _testResult = null; });
    try {
      final result = await _testServerConnection(
        ref,
        Server(
          id: widget.server?.id ?? 'temp',
          name: 'temp',
          host: host,
          port: port,
          provider: _provider,
          authToken: token.isEmpty ? null : token,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) setState(() { _testResult = result; _testing = false; });
    } catch (e) {
      if (mounted) setState(() {
        _testResult = ConnectionStatus(connected: false, error: e.toString());
        _testing = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final rawHost = _hostController.text.trim();
    final remote = ref.read(enabledRemoteAccessProvider);
    final host = remote?.canonicalizeUrl(rawHost) ?? rawHost;
    final port = int.tryParse(_portController.text.trim()) ?? _provider.defaultPort;
    if (name.isEmpty || host.isEmpty) return;

    final token = _tokenController.text.trim();
    final server = Server(
      id: widget.server?.id ?? const Uuid().v4(),
      name: name,
      host: host,
      port: port,
      provider: _provider,
      authToken: token.isEmpty ? null : token,
      isActive: widget.server?.isActive ?? false,
      lastConnectedAt: widget.server?.lastConnectedAt,
      createdAt: widget.server?.createdAt ?? DateTime.now(),
    );
    if (server.isRemote && remote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remote relay servers aren’t supported in this version. '
              'Use your computer’s local IP on the same Wi‑Fi.'),
        ),
      );
      return;
    }

    await widget.onSave(server);
    if (mounted) Navigator.pop(context);
  }
}

class _HelpStep extends StatelessWidget {
  final String number;
  final String text;

  const _HelpStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
