import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// テナントのお知らせ一覧＋詳細BottomSheet付きボタン
class TenantAlertsButton extends StatefulWidget {
  final String tenantId;

  const TenantAlertsButton({super.key, required this.tenantId});

  @override
  State<TenantAlertsButton> createState() => _TenantAlertsButtonState();
}

class _TenantAlertsButtonState extends State<TenantAlertsButton> {
  /// 一覧を開く
  Future<void> _openAlertsPanel() async {
    final tid = widget.tenantId;
    if (tid.isEmpty) return;

    // 1) ownerUid を tenantIndex から取得（招待テナント対応）
    String? ownerUidResolved;
    try {
      final idx = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tid)
          .get();
      ownerUidResolved = idx.data()?['uid'] as String?;
    } catch (_) {}
    // 自分オーナーのケースのフォールバック
    ownerUidResolved ??= FirebaseAuth.instance.currentUser?.uid;

    if (ownerUidResolved == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '通知の取得に失敗しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    final col = FirebaseFirestore.instance
        .collection(ownerUidResolved)
        .doc(tid)
        .collection('alerts');

    if (!mounted) return;

    // 2) 一覧（未読は強調表示）。開いただけでは既読にしない。
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          right: true,
          left: true,
          minimum: const EdgeInsets.all(6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      'お知らせ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        // すべて既読
                        final qs = await col
                            .where('read', isEqualTo: false)
                            .get();
                        final batch = FirebaseFirestore.instance.batch();
                        for (final d in qs.docs) {
                          batch.set(d.reference, {
                            'read': true,
                            'readAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        }
                        await batch.commit();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.done_all),
                      label: const Text('すべて既読'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: col
                        .orderBy('createdAt', descending: true)
                        .limit(100)
                        .snapshots(),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('読み込みエラー: ${snap.error}'));
                      }
                      final docs = snap.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('新しいお知らせはありません'),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final d = docs[i];
                          final m = d.data();
                          final msg =
                              (m['message'] as String?)?.trim() ?? 'お知らせ';
                          final read = (m['read'] as bool?) ?? false;
                          final createdAt = m['createdAt'];
                          String when = '';
                          if (createdAt is Timestamp) {
                            final dt = createdAt.toDate().toLocal();
                            when =
                                '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
                                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          }

                          return ListTile(
                            leading: Icon(
                              read
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: read ? Colors.black45 : Colors.orange,
                            ),
                            title: Text(
                              msg,
                              style: TextStyle(
                                fontFamily: 'LINEseed',
                                fontWeight: read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: when.isEmpty ? null : Text(when),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 6,
                            ),
                            onTap: () => _openAlertDetailAndMarkRead(
                              docRef: d.reference,
                              data: m,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 通知詳細シート + 個別既読化
  Future<void> _openAlertDetailAndMarkRead({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
  }) async {
    // 個別既読化
    try {
      await docRef.set({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;

    final msg = (data['message'] as String?)?.trim() ?? 'お知らせ';
    final title = (data['title'] as String?)?.trim() ?? 'タイトル';
    final details = (data['details'] as String?)?.trim(); // 任意の詳細
    final payload = (data['payload'] as Map?)
        ?.cast<String, dynamic>(); // 追加情報がある場合
    final createdAt = data['createdAt'];
    String when = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate().toLocal();
      when =
          '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final maxW = size.width < 480 ? size.width : 560.0;
        final maxH = size.height * 0.8;

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications, color: Colors.black87),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'LINEseed',
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        msg,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'LINEseed',
                        ),
                      ),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          when,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (details != null && details.isNotEmpty) ...[
                              Text(
                                details,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (payload != null && payload.isNotEmpty) ...[
                              const Text(
                                '詳細情報',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: SelectableText(
                                  _prettyJson(payload),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _prettyJson(Map<String, dynamic> m) {
    try {
      final entries = m.entries.map((e) => '• ${e.key}: ${e.value}').join('\n');
      return entries.isEmpty ? '(なし)' : entries;
    } catch (_) {
      return m.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _openAlertsPanel,
      icon: const Icon(Icons.notifications_outlined),
      tooltip: 'お知らせ',
    );
  }
}
