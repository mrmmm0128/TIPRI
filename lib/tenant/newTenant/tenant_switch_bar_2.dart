// lib/tenant/store_detail/tenant_switch_drawer.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TenantSwitchDrawer extends StatefulWidget {
  const TenantSwitchDrawer({
    super.key,
    this.currentTenantId,
    this.currentTenantName,
    this.title,
    this.showCloseButton = true,
    this.onChangedEx,
    this.onCreateTenant,
    this.onOpenOnboarding,
  });

  final String? currentTenantId;
  final String? currentTenantName;
  final Widget? title;
  final bool showCloseButton;

  /// (tenantId, tenantName, ownerUid, invited)
  final void Function(String id, String? name, String ownerUid, bool invited)?
  onChangedEx;

  /// ドロワー下部の CTA: 新規作成
  final Future<void> Function()? onCreateTenant;

  /// ドロワー下部の CTA: 再開/登録状況（現在の店舗に対して）
  final Future<void> Function(
    String tenantId,
    String? tenantName,
    String ownerUid,
  )?
  onOpenOnboarding;

  @override
  State<TenantSwitchDrawer> createState() => _TenantSwitchDrawerState();
}

class _TenantSwitchDrawerState extends State<TenantSwitchDrawer> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final v = _searchCtrl.text.trim();
      if (v != _q) setState(() => _q = v);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- Firestore: 自分がオーナーの店舗 ---
  Stream<List<_TenantRow>> _ownedTenantsStream(String uid) {
    final col = FirebaseFirestore.instance.collection(uid);

    // invited をサーバー側で除外（!= を使うときは documentId で orderBy が必須）
    final q = col
        .where(FieldPath.documentId, isNotEqualTo: 'invited')
        .orderBy(FieldPath.documentId);

    return q.snapshots().map((snap) {
      final rows = snap.docs.map((d) {
        final m = d.data();
        final name = (m['name'] as String?)?.trim();
        final members = (m['memberUids'] as List?)?.cast<String>() ?? const [];
        return _TenantRow(
          id: d.id,
          name: (name == null || name.isEmpty) ? d.id : name,
          ownerUid: uid,
          invited: false,
          memberUids: members,
        );
      }).toList();

      return rows;
    });
  }

  // --- Firestore: 招待（他オーナー）の店舗（/<uid>/invited 経由） ---
  Stream<List<_TenantRow>> _invitedTenantsStream(String uid) {
    final invitedRef = FirebaseFirestore.instance
        .collection(uid)
        .doc('invited');

    // ここで自前のコントローラを作って、インデックス → 各実体ドキュメントの購読を束ねる
    final controller = StreamController<List<_TenantRow>>();

    // 現在アクティブな購読（ownerUid/tenantId ごと）
    final Map<
      String,
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
    >
    subs = {};
    // 最新の結果セット
    final Map<String, _TenantRow> rows = {};

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? indexSub;

    void emit() {
      final list = rows.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      controller.add(list);
    }

    indexSub = invitedRef.snapshots().listen((doc) {
      final map = (doc.data()?['tenants'] as Map<String, dynamic>?) ?? {};
      final should = <String>{};

      map.forEach((tenantId, v) {
        final ownerUid = (v is Map ? v['ownerUid'] : null)?.toString() ?? '';
        if (ownerUid.isEmpty) return;
        final key = '$ownerUid/$tenantId';
        should.add(key);

        if (subs.containsKey(key)) return;

        // 各オーナー配下の実体ドキュメントを購読
        subs[key] = FirebaseFirestore.instance
            .collection(ownerUid)
            .doc(tenantId as String)
            .snapshots()
            .listen((ds) {
              if (ds.exists) {
                final m = ds.data() ?? {};
                final name = (m['name'] as String?)?.trim();
                final members =
                    (m['memberUids'] as List?)?.cast<String>() ?? const [];
                rows[key] = _TenantRow(
                  id: ds.id,
                  name: (name == null || name.isEmpty) ? ds.id : name,
                  ownerUid: ownerUid,
                  invited: ownerUid != uid, // 自分オーナーなら false
                  memberUids: members,
                );
              } else {
                rows.remove(key);
              }
              emit();
            });
      });

      // いらなくなった購読を解除
      for (final key in subs.keys.where((k) => !should.contains(k)).toList()) {
        subs.remove(key)?.cancel();
        rows.remove(key);
      }
      emit();
    });

    // 呼び出し側がキャンセルしたら後始末
    controller.onCancel = () async {
      await indexSub?.cancel();
      for (final s in subs.values) {
        await s.cancel();
      }
      subs.clear();
    };

    return controller.stream;
  }

  void _select(_TenantRow t) {
    // 呼び出し側に通知（新API→旧API の順で）
    widget.onChangedEx?.call(t.id, t.name, t.ownerUid, t.invited);

    // Drawer を閉じる
    Navigator.of(context).maybePop();
  }

  Future<String> _resolveOwnerUid(String tenantId) async {
    try {
      final idx = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tenantId)
          .get();
      final uid = (idx.data()?['uid'] as String?);
      return uid ?? FirebaseAuth.instance.currentUser!.uid;
    } catch (_) {
      return FirebaseAuth.instance.currentUser!.uid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Drawer(child: Center(child: Text('ログインが必要です')));
    }

    return Drawer(
      backgroundColor: const Color(0xFFFCC400),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.black87),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.title ??
                              const Text(
                                '店舗切り替え',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'LINEseed',
                                ),
                              ),
                          const SizedBox(height: 4),
                          Text(
                            u.email ?? u.uid,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.showCloseButton)
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                      tooltip: '閉じる',
                    ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '店舗名で検索',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),

            // Body
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(() => _loading = true);
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  setState(() => _loading = false);
                },
                child: StreamBuilder<List<_TenantRow>>(
                  stream: _ownedTenantsStream(u.uid),
                  builder: (context, ownedSnap) {
                    final owned = ownedSnap.data ?? const <_TenantRow>[];
                    return StreamBuilder<List<_TenantRow>>(
                      stream: _invitedTenantsStream(u.uid),
                      builder: (context, invitedSnap) {
                        final invited =
                            invitedSnap.data ?? const <_TenantRow>[];

                        // 検索フィルタ
                        bool matches(_TenantRow r) {
                          if (_q.isEmpty) return true;
                          final q = _q.toLowerCase();
                          return r.name.toLowerCase().contains(q) ||
                              r.id.toLowerCase().contains(q);
                        }

                        final ownedF = owned.where(matches).toList()
                          ..sort((a, b) => a.name.compareTo(b.name));
                        final invitedF = invited.where(matches).toList()
                          ..sort((a, b) => a.name.compareTo(b.name));

                        final hasData =
                            ownedF.isNotEmpty || invitedF.isNotEmpty;

                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (!hasData)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('店舗が見つかりません')),
                              ),

                            if (ownedF.isNotEmpty) ...[
                              const _SectionHeader('自分の店舗'),
                              ...ownedF.map(_tileFor),
                              const SizedBox(height: 12),
                            ],

                            if (invitedF.isNotEmpty) ...[
                              const _SectionHeader('招待された店舗'),
                              ...invitedF.map(_tileFor),
                              const SizedBox(height: 12),
                            ],

                            const SizedBox(height: 40),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // ▼ 追加：フッターCTA（新規作成 / 再開・登録状況）
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 現在の店舗に対する「登録状況/再開」
                    if (widget.currentTenantId != null)
                      FilledButton.icon(
                        onPressed: () async {
                          final tid = widget.currentTenantId!;
                          final ownerUid = await _resolveOwnerUid(tid);
                          if (widget.onOpenOnboarding != null &&
                              ownerUid == u.uid) {
                            await widget.onOpenOnboarding!(
                              tid,
                              widget.currentTenantName,
                              ownerUid,
                            );
                          } else {
                            // フォールバック：ハンドラ未指定時は何もしない（トースト表示など）
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'オーナーでないと開けません',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.assignment_turned_in),
                        label: const Text('登録状況'),
                      ),

                    const SizedBox(height: 8),

                    // 新規作成
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (widget.onCreateTenant != null) {
                          await widget.onCreateTenant!();
                        } else {
                          // フォールバック：未指定ならトースト
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '親側で onCreateTenant を実装してください',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('新規店舗を作成'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileFor(_TenantRow t) {
    final selected = t.id == widget.currentTenantId;
    final icon = t.invited ? Icons.group : Icons.storefront;
    final note = t.invited ? '他オーナー' : 'あなたがオーナー';

    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        t.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        note,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.chevron_right),
      selected: selected,
      onTap: () => _select(t),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black54,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _TenantRow {
  final String id;
  final String name;
  final String ownerUid;
  final bool invited; // true: 他オーナー
  final List<String> memberUids;
  const _TenantRow({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.invited,
    required this.memberUids,
  });
}
