import 'dart:io';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app/theme/app_colors.dart';
import '../../../config/admin_config.dart';
import '../../../core/firebase/firebase_status.dart';
import '../../../core/analytics/app_analytics.dart';
import '../../../shared/widgets/platform_icon.dart';
import 'package:timeago/timeago.dart' as timeago;


Future<String?> _currentDeviceId() async {
  final info = DeviceInfoPlugin();
  try {
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.identifierForVendor;
    }
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id;
    }
  } catch (_) {
    return null;
  }
  return null;
}

// ── Status helpers ────────────────────────────────────────────────
enum TicketStatus {
  open,
  inProgress,
  planned,
  completed,
  declined;

  String get label {
    switch (this) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.inProgress:
        return 'In Progress';
      case TicketStatus.planned:
        return 'Planned';
      case TicketStatus.completed:
        return 'Completed';
      case TicketStatus.declined:
        return 'Declined';
    }
  }

  Color get color {
    switch (this) {
      case TicketStatus.open:
        return AppColors.primary;
      case TicketStatus.inProgress:
        return AppColors.warning;
      case TicketStatus.planned:
        return const Color(0xFF8B5CF6);
      case TicketStatus.completed:
        return AppColors.success;
      case TicketStatus.declined:
        return AppColors.error;
    }
  }

  static TicketStatus fromString(String s) {
    return TicketStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => TicketStatus.open,
    );
  }
}

enum RequestCategory {
  feature,
  bug,
  improvement;

  String get label {
    switch (this) {
      case RequestCategory.feature:
        return 'Feature';
      case RequestCategory.bug:
        return 'Bug';
      case RequestCategory.improvement:
        return 'Improvement';
    }
  }

  Color get color {
    switch (this) {
      case RequestCategory.feature:
        return AppColors.primary;
      case RequestCategory.bug:
        return AppColors.error;
      case RequestCategory.improvement:
        return AppColors.success;
    }
  }

  static RequestCategory fromString(String? s) {
    if (s == null) return RequestCategory.feature;
    return RequestCategory.values.firstWhere(
      (e) => e.name == s,
      orElse: () => RequestCategory.feature,
    );
  }
}

// ── Firestore refs ────────────────────────────────────────────────
CollectionReference get _requestsCol =>
    FirebaseFirestore.instance.collection('feature_requests');

// ── Screen ────────────────────────────────────────────────────────

class FeatureRequestsScreen extends ConsumerStatefulWidget {
  const FeatureRequestsScreen({super.key});

  @override
  ConsumerState<FeatureRequestsScreen> createState() => _FeatureRequestsScreenState();
}

class _FeatureRequestsScreenState extends ConsumerState<FeatureRequestsScreen> {
  String _sortBy = 'votes'; // 'votes' | 'newest'
  String? _deviceId;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _resolveAdminByDeviceId();
  }

  Future<void> _resolveAdminByDeviceId() async {
    if (!firebaseReady) return;
    final id = await _currentDeviceId();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('🔑 FeatureRequest Device ID: $id');
    if (!mounted) return;
    setState(() {
      _deviceId = id;
      _isAdmin = (id != null && adminDeviceIds.contains(id)) ||
          (uid != null && adminUids.contains(uid));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feature Requests')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Feature requests need a Firebase project. '
              'Add GoogleService-Info.plist to enable them (see README).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
      backgroundColor: isDark ? AppColors.gradientDarkStart : AppColors.gradientLightStart,
      appBar: AppBar(
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Feature Requests',
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          labelColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          unselectedLabelColor:
              isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          tabs: const [
            Tab(text: 'Feature Requests'),
            Tab(text: 'My Requests'),
            Tab(text: 'Completed'),
          ],
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: PlatformIcon(
            material: Icons.arrow_back,
            cupertino: CupertinoIcons.back,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/sessions');
            }
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: PlatformIcon(
              material: Icons.sort,
              cupertino: CupertinoIcons.arrow_up_arrow_down,
              size: 22,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
            tooltip: 'Sort',
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'votes', child: Text('Most Voted')),
              PopupMenuItem(value: 'newest', child: Text('Newest')),
            ],
          ),
          IconButton(
            icon: PlatformIcon(
              material: Icons.add_circle_outline,
              cupertino: CupertinoIcons.add_circled,
              size: 24,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
            tooltip: 'New Request',
            onPressed: () => _showNewRequestSheet(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
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
          child: StreamBuilder<QuerySnapshot>(
            stream: _sortBy == 'votes'
                ? _requestsCol.orderBy('vote_count', descending: true).snapshots()
                : _requestsCol.orderBy('created_at', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final errorText = '${snapshot.error}';
                final isPermissionDenied =
                    errorText.toLowerCase().contains('permission-denied');
                if (isPermissionDenied) {
                  return _PermissionDeniedView(uid: uid);
                }
                return Center(child: Text('Error: $errorText'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              final myDocs = uid == null
                  ? const <QueryDocumentSnapshot>[]
                  : docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return data['author_uid'] == uid;
                    }).toList();
              final completedDocs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['status'] as String?) == TicketStatus.completed.name;
              }).toList();
              final activeDocs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['status'] as String?) != TicketStatus.completed.name;
              }).toList();

              return TabBarView(
                children: [
                  _buildRequestList(activeDocs, uid),
                  _buildRequestList(myDocs, uid, emptyText: 'You have not created any requests yet'),
                  _buildRequestList(completedDocs, uid, emptyText: 'No completed requests yet'),
                ],
              );
            },
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildRequestList(
    List<QueryDocumentSnapshot> docs,
    String? uid, {
    String? emptyText,
  }) {
    if (docs.isEmpty) {
      return _EmptyView(message: emptyText);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: docs.length,
      itemBuilder: (context, i) => _RequestCard(
        doc: docs[i],
        uid: uid,
        isAdmin: _isAdmin,
        deviceId: _deviceId,
      ),
    );
  }

  void _showNewRequestSheet(BuildContext context) {
    final nameC = TextEditingController();
    final titleC = TextEditingController();
    final descC = TextEditingController();
    RequestCategory selectedCategory = RequestCategory.feature;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Text('New Feature Request',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    if (!_isAdmin) ...[
                      TextField(
                        controller: nameC,
                        decoration: const InputDecoration(
                          labelText: 'Your Name (optional)',
                          hintText: 'How should we call you?',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 14),
                    ],
                    DropdownButtonFormField<RequestCategory>(
                      value: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: RequestCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => selectedCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Short description of your idea',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      autofocus: true,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descC,
                      decoration: const InputDecoration(
                        labelText: 'Details (optional)',
                        hintText: 'Describe that in detail...',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        final title = titleC.text.trim();
                        if (title.isEmpty) return;
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sign-in is required to submit a request.'),
                              ),
                            );
                          }
                          return;
                        }
                        try {
                          await _requestsCol.add({
                            'title': title,
                            'description': descC.text.trim(),
                            'author_name': nameC.text.trim(),
                            'status': TicketStatus.open.name,
                            'category': selectedCategory.name,
                            'author_uid': uid,
                            'author_device_id': _deviceId,
                            'vote_count': 1,
                            'voters': [uid],
                            'created_at': FieldValue.serverTimestamp(),
                            'admin_response': null,
                            'admin_response_uid': null,
                            'admin_response_updated_at': null,
                          });
                          AppAnalytics.instance.logAction('feature_request_created');
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not submit request: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Submit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final String? uid;
  const _PermissionDeniedView({required this.uid});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.glassBorderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 28),
              const SizedBox(height: 10),
              Text(
                'Firestore denied access to feature requests.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Update your Firestore rules to allow authenticated reads on feature_requests.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Current UID: ${uid ?? 'Not signed in'}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty view ────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final String? message;
  const _EmptyView({this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformIcon(
            material: Icons.lightbulb_outline,
            cupertino: CupertinoIcons.lightbulb,
            size: 64,
            color: AppColors.primary.withValues(alpha: isDark ? 0.55 : 0.4),
          ),
          const SizedBox(height: 16),
          Text('No feature requests yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
            Text(message ?? 'Tap + to submit the first idea!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  )),
        ],
      ),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String? uid;
  final bool isAdmin;
  final String? deviceId;

  const _RequestCard({
    required this.doc,
    required this.uid,
    required this.isAdmin,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = TicketStatus.fromString(data['status'] ?? 'open');
    final category = RequestCategory.fromString(data['category'] as String?);
    final voters = List<String>.from(data['voters'] ?? []);
    final hasVoted = uid != null && voters.contains(uid);
    final voteCount = data['vote_count'] ?? 0;
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
    final adminResponse = data['admin_response'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.white).withValues(alpha: isDark ? 0.08 : 0.70),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.glassBorderDark : AppColors.borderLight.withValues(alpha: 0.4),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openDetail(context, doc),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Vote column
                    _VoteButton(
                      count: voteCount,
                      hasVoted: hasVoted,
                      onTap: () => _toggleVote(doc.id, voters, hasVoted),
                    ),
                    const SizedBox(width: 14),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: status.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: status.color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: category.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  category.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: category.color,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                (data['author_name'] as String?)?.isNotEmpty == true ? (data['author_name'] as String) : 'User',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                ),
                              ),
                              if (createdAt != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '•',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight).withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  timeago.format(createdAt),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['title'] ?? '',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((data['description'] as String?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              data['description'],
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (adminResponse != null && adminResponse.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.admin_panel_settings, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      adminResponse,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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

  void _toggleVote(String docId, List<String> voters, bool hasVoted) {
    if (uid == null) return;
    if (hasVoted) {
      _requestsCol.doc(docId).update({
        'voters': FieldValue.arrayRemove([uid]),
        'vote_count': FieldValue.increment(-1),
      });
      AppAnalytics.instance.logAction('feature_request_vote_removed');
    } else {
      _requestsCol.doc(docId).update({
        'voters': FieldValue.arrayUnion([uid!]),
        'vote_count': FieldValue.increment(1),
      });
      AppAnalytics.instance.logAction('feature_request_voted');
    }
  }

  void _openDetail(BuildContext context, QueryDocumentSnapshot doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RequestDetailScreen(
          docId: doc.id,
          isAdmin: isAdmin,
          deviceId: deviceId,
        ),
      ),
    );
  }
}

// ── Vote button ───────────────────────────────────────────────────

class _VoteButton extends StatelessWidget {
  final int count;
  final bool hasVoted;
  final VoidCallback onTap;

  const _VoteButton({required this.count, required this.hasVoted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: hasVoted
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasVoted ? AppColors.primary.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(
              hasVoted ? Icons.keyboard_arrow_up_rounded : Icons.arrow_upward_rounded,
              size: 22,
              color: hasVoted ? AppColors.primary : Colors.grey,
            ),
            Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: hasVoted ? AppColors.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail screen ─────────────────────────────────────────────────

class _RequestDetailScreen extends StatefulWidget {
  final String docId;
  final bool isAdmin;
  final String? deviceId;
  const _RequestDetailScreen({
    required this.docId,
    required this.isAdmin,
    required this.deviceId,
  });

  @override
  State<_RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<_RequestDetailScreen> {
  final _commentC = TextEditingController();
  final _commentNameC = TextEditingController();

  @override
  void dispose() {
    _commentC.dispose();
    _commentNameC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAdmin = widget.isAdmin;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Feature Request',
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        ),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Admin Actions',
              onSelected: (val) async {
                if (val == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Delete Request?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _requestsCol.doc(widget.docId).delete();
                    if (mounted) Navigator.pop(context);
                  }
                } else {
                  // Change status
                  _requestsCol.doc(widget.docId).update({'status': val});
                  AppAnalytics.instance.logAction('feature_request_status_changed',
                      parameters: {'status': val});
                }
              },
              itemBuilder: (_) => [
                ...TicketStatus.values.map(
                  (s) => PopupMenuItem(value: s.name, child: Text('Status: ${s.label}')),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Request', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _requestsCol.doc(widget.docId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() as Map<String, dynamic>;
          final status = TicketStatus.fromString(data['status'] ?? 'open');
          final category = RequestCategory.fromString(data['category'] as String?);
          final voters = List<String>.from(data['voters'] ?? []);
          final hasVoted = uid != null && voters.contains(uid);
          final voteCount = data['vote_count'] ?? 0;
          final createdAt = (data['created_at'] as Timestamp?)?.toDate();
          final adminResponse = data['admin_response'] as String?;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Status + votes row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: status.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(status.label,
                              style: TextStyle(fontWeight: FontWeight.w600, color: status.color)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: category.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(category.label,
                              style: TextStyle(fontWeight: FontWeight.w600, color: category.color)),
                        ),
                        const Spacer(),
                        _VoteButton(
                          count: voteCount,
                          hasVoted: hasVoted,
                          onTap: () {
                            if (uid == null) return;
                            if (hasVoted) {
                              _requestsCol.doc(widget.docId).update({
                                'voters': FieldValue.arrayRemove([uid]),
                                'vote_count': FieldValue.increment(-1),
                              });
                            } else {
                              _requestsCol.doc(widget.docId).update({
                                'voters': FieldValue.arrayUnion([uid]),
                                'vote_count': FieldValue.increment(1),
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Title
                    Text(data['title'] ?? '',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text((data['author_name'] as String?)?.isNotEmpty == true ? (data['author_name'] as String) : 'User',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                )),
                        const SizedBox(width: 8),
                        if (createdAt != null) ...[
                          Text('•',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight).withValues(alpha: 0.5),
                                  )),
                          const SizedBox(width: 8),
                          Text(timeago.format(createdAt),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  )),
                        ],
                      ],
                    ),
                    if ((data['description'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      Text(data['description'],
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                    // Admin response
                    if (adminResponse != null && adminResponse.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.admin_panel_settings, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text('Official Response',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600, color: AppColors.primary)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(adminResponse, style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                    // Admin: add/edit response
                    if (isAdmin) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => _showAdminResponseDialog(context, adminResponse),
                        icon: const Icon(Icons.reply, size: 18),
                        label: Text(adminResponse != null ? 'Edit Response' : 'Add Response'),
                      ),
                    ],
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text('Comments',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 12),
                    // Comments stream
                    StreamBuilder<QuerySnapshot>(
                      stream: _requestsCol
                          .doc(widget.docId)
                          .collection('comments')
                          .orderBy('created_at', descending: false)
                          .snapshots(),
                      builder: (context, commentSnap) {
                        if (!commentSnap.hasData) return const SizedBox.shrink();
                        final comments = commentSnap.data!.docs;
                        if (comments.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text('No comments yet',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondaryLight,
                                      )),
                            ),
                          );
                        }
                        return Column(
                          children: comments
                              .map((c) => _CommentTile(
                                    requestId: widget.docId,
                                    commentId: c.id,
                                    data: c.data() as Map<String, dynamic>,
                                    currentUid: uid,
                                    canModerate: isAdmin,
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Comment input bar
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 10, 8, 10 + MediaQuery.of(context).viewPadding.bottom),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, right: 8),
                        child: TextField(
                          controller: _commentNameC,
                          decoration: InputDecoration(
                            hintText: 'Your name (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.withValues(alpha: 0.08),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          textCapitalization: TextCapitalization.words,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentC,
                            decoration: InputDecoration(
                              hintText: 'Add a comment...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.grey.withValues(alpha: 0.1),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.send_rounded),
                          color: AppColors.primary,
                          onPressed: () => _postComment(uid),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _postComment(String? uid) async {
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in is required to comment.')),
        );
      }
      return;
    }
    final text = _commentC.text.trim();
    if (text.isEmpty) return;
    try {
      await _requestsCol.doc(widget.docId).collection('comments').add({
        'text': text,
        'author_name': _commentNameC.text.trim(),
        'author_uid': uid,
        'author_device_id': widget.deviceId,
        'is_admin': widget.isAdmin,
        'created_at': FieldValue.serverTimestamp(),
      });
      AppAnalytics.instance.logAction('feature_request_comment_posted',
          parameters: {'is_admin': widget.isAdmin ? 1 : 0});
      _commentC.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post comment: $e')),
        );
      }
    }
  }

  void _showAdminResponseDialog(BuildContext context, String? current) {
    final c = TextEditingController(text: current ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Official Response'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: 'Type your official response...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              _requestsCol.doc(widget.docId).update({
                'admin_response': c.text.trim(),
                'admin_response_uid': FirebaseAuth.instance.currentUser?.uid,
                'admin_response_updated_at': FieldValue.serverTimestamp(),
              });
              AppAnalytics.instance.logAction('feature_request_official_reply_saved');
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Comment tile ──────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final String requestId;
  final String commentId;
  final Map<String, dynamic> data;
  final String? currentUid;
  final bool canModerate;
  const _CommentTile({
    required this.requestId,
    required this.commentId,
    required this.data,
    required this.currentUid,
    required this.canModerate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = data['is_admin'] == true;
    final isMine = currentUid != null && data['author_uid'] == currentUid;
    final canDelete = isMine || canModerate;
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAdmin
              ? AppColors.primary.withValues(alpha: 0.06)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(14),
          border: isAdmin ? Border.all(color: AppColors.primary.withValues(alpha: 0.15)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isAdmin) ...[
                  Icon(Icons.admin_panel_settings, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Admin',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ] else
                  Text((data['author_name'] as String?)?.isNotEmpty == true ? data['author_name'] : 'User',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                const Spacer(),
                if (createdAt != null)
                  Text(timeago.format(createdAt),
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: AppColors.error,
                    visualDensity: VisualDensity.compact,
                    tooltip: isMine ? 'Delete your comment' : 'Delete comment',
                    onPressed: () async {
                      await _requestsCol
                          .doc(requestId)
                          .collection('comments')
                          .doc(commentId)
                          .delete();
                      AppAnalytics.instance.logAction('feature_request_comment_deleted',
                          parameters: {'as_admin': canModerate && !isMine ? 1 : 0});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(data['text'] ?? '', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
