import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_card.dart';

class AdminSectionCard extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> tenantRef;
  final String tenantId;
  final String? ownerId;
  final FirebaseFunctions functions;
  final Map<String, dynamic> dataMap;
  final Future<void> Function(String uid) onRemoveAdmin;

  const AdminSectionCard({
    super.key,
    required this.tenantRef,
    required this.tenantId,
    required this.ownerId,
    required this.functions,
    required this.dataMap,
    required this.onRemoveAdmin,
  });

  @override
  State<AdminSectionCard> createState() => _AdminSectionCardState();
}

class _AdminSectionCardState extends State<AdminSectionCard> {
  bool get _isOwner =>
      widget.ownerId != null &&
      widget.ownerId == FirebaseAuth.instance.currentUser?.uid;

  Future<void> _inviteAdminDialog() async {
    final ctrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,

      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // final viewInsets = MediaQuery.of(ctx).viewInsets;
        bool inviting = false;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.only(bottom: 2),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> submit() async {
                final email = ctrl.text.trim();
                if (email.isEmpty || inviting) return;

                setLocal(() => inviting = true);
                try {
                  await widget.functions
                      .httpsCallable('inviteTenantAdmin')
                      .call({'tenantId': widget.tenantId, 'email': email});
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          '招待に失敗: $e',
                          style: const TextStyle(fontFamily: 'LINEseed'),
                        ),
                        backgroundColor: const Color(0xFFFCC400),
                      ),
                    );
                  }
                } finally {
                  if (ctx.mounted) setLocal(() => inviting = false);
                }
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '管理者を招待',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        autofocus: true,
                        controller: ctrl,
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.emailAddress,
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '※ 入力したメールアドレスに招待メールを送信します。',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: inviting
                                  ? null
                                  : () => Navigator.pop(ctx, false),
                              child: const Text('キャンセル'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: inviting ? null : submit,
                              icon: inviting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: const Text('招待'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFCC400),
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('招待を送信しました', style: TextStyle(fontFamily: 'LINEseed')),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    }

    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantRef = widget.tenantRef;
    final dataMap = widget.dataMap;

    return CardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- 承認待ちの招待 ---
            StreamBuilder<QuerySnapshot>(
              stream: tenantRef
                  .collection('invites')
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, invSnap) {
                final invites = invSnap.data?.docs ?? const [];
                if (invSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '承認待ちの招待',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (invites.isEmpty)
                      const Text(
                        '承認待ちはありません',
                        style: TextStyle(
                          color: Colors.black54,
                          fontFamily: 'LINEseed',
                        ),
                      )
                    else
                      ...invites.map((d) {
                        final m = d.data() as Map<String, dynamic>;
                        final email = (m['emailLower'] as String?) ?? '';
                        final expTs = m['expiresAt'];
                        final exp = expTs is Timestamp ? expTs.toDate() : null;

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.pending_actions,
                            color: Colors.orange,
                          ),
                          title: Text(
                            email,
                            style: const TextStyle(color: Colors.black87),
                          ),
                          subtitle: exp == null
                              ? null
                              : Text(
                                  '有効期限: ${exp.year}/${exp.month.toString().padLeft(2, '0')}/${exp.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontFamily: 'LINEseed',
                                  ),
                                ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  await widget.functions
                                      .httpsCallable('inviteTenantAdmin')
                                      .call({
                                        'tenantId': widget.tenantId,
                                        'email': email,
                                      });
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '招待メールを再送しました',
                                        style: TextStyle(
                                          fontFamily: 'LINEseed',
                                        ),
                                      ),
                                      backgroundColor: Color(0xFFFCC400),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.send),
                                label: const Text('再送'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await widget.functions
                                      .httpsCallable('cancelTenantAdminInvite')
                                      .call({
                                        'tenantId': widget.tenantId,
                                        'inviteId': d.id,
                                      });
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '招待を取り消しました',
                                        style: TextStyle(
                                          fontFamily: 'LINEseed',
                                        ),
                                      ),
                                      backgroundColor: Color(0xFFFCC400),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.close),
                                label: const Text('取消'),
                              ),
                            ],
                          ),
                        );
                      }),
                    const Divider(height: 24, color: Colors.black87),
                  ],
                );
              },
            ),

            // --- 管理者一覧 ---
            StreamBuilder<QuerySnapshot>(
              stream: tenantRef.collection('members').snapshots(),
              builder: (context, memSnap) {
                final members = memSnap.data?.docs ?? [];
                if (memSnap.hasData && members.isNotEmpty) {
                  return AdminList(
                    entries: members.map((m) {
                      final md = m.data() as Map<String, dynamic>;
                      return AdminEntry(
                        uid: m.id,
                        email: (md['email'] as String?) ?? '',
                        name: (md['displayName'] as String?) ?? '',
                      );
                    }).toList(),
                    onRemove: (uidToRemove) {
                      if (!_isOwner) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '削除できるのはオーナーのみです',
                              style: TextStyle(fontFamily: 'LINEseed'),
                            ),
                            backgroundColor: Color(0xFFFCC400),
                          ),
                        );
                        return;
                      }
                      widget.onRemoveAdmin(uidToRemove);
                    },
                  );
                }

                final uids =
                    (dataMap['memberUids'] as List?)?.cast<String>() ??
                    const <String>[];
                if (uids.isEmpty) {
                  return const ListTile(
                    title: Text(
                      '管理者がいません',
                      style: TextStyle(color: Colors.black87),
                    ),
                    subtitle: Text(
                      '右上の追加ボタンから招待できます',
                      style: TextStyle(color: Colors.black87),
                    ),
                  );
                }

                return AdminList(
                  entries: uids
                      .map((u) => AdminEntry(uid: u, email: '', name: ''))
                      .toList(),
                  onRemove: (uidToRemove) {
                    if (!_isOwner) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '削除できるのはオーナーのみです',
                            style: TextStyle(fontFamily: 'LINEseed'),
                          ),
                          backgroundColor: Color(0xFFFCC400),
                        ),
                      );
                      return;
                    }
                    widget.onRemoveAdmin(uidToRemove);
                  },
                );
              },
            ),

            // --- 管理者追加ボタン ---
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _inviteAdminDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('管理者を追加'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
