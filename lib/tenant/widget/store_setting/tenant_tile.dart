import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TenantTile extends StatelessWidget {
  final String uid;
  final String tenantId;
  final String name;

  const TenantTile({
    required this.uid,
    required this.tenantId,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1.5),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("削除しますか？"),
                  content: Text("「$name」を削除します。この操作は取り消せません。"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("キャンセル"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("削除する"),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                await FirebaseFirestore.instance
                    .collection(uid)
                    .doc(tenantId)
                    .delete();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "削除しました: $name",
                        style: const TextStyle(fontFamily: 'LINEseed'),
                      ),
                      backgroundColor: const Color(0xFFFCC400),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class TenantListSection extends StatelessWidget {
  final String uid;
  const TenantListSection({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection(uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Text('店舗情報の読み込みに失敗しました');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // invite ドキュメントを除外
        final docs = snap.data!.docs.where((d) => d.id != 'invite').toList();

        if (docs.isEmpty) {
          return const Text('あなたが作成した店舗はありません');
        }

        return Column(
          children: [
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TenantRow(uid: uid, tenantId: d.id, data: d.data()),
              ),
          ],
        );
      },
    );
  }
}

class _TenantRow extends StatelessWidget {
  final String uid;
  final String tenantId;
  final Map<String, dynamic> data;

  const _TenantRow({
    required this.uid,
    required this.tenantId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?) ?? '(店舗名未設定)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () async {
              // まず最新の status を取り直す
              final doc = await FirebaseFirestore.instance
                  .collection(uid)
                  .doc(tenantId)
                  .get();
              final status = (doc.data()?['status'] as String? ?? '')
                  .toLowerCase();

              // nonactive 以外は削除NG
              if (status != 'nonactive') {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'この店舗は削除できません。\n削除するには、先にステータスを「nonactive」にしてください。',
                      style: TextStyle(fontFamily: 'LINEseed'),
                    ),
                    backgroundColor: Color(0xFFFCC400),
                  ),
                );
                return;
              }

              // ★★★ ここからポップアップ確認 ★★★
              final ok = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.black, width: 2),
                    ),
                    title: const Text('店舗を削除しますか？'),
                    content: Text(
                      '「$name」を削除すると、この店舗の情報は元に戻せません。\n\n本当に削除してよろしいですか？',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('キャンセル'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('削除する'),
                      ),
                    ],
                  );
                },
              );

              if (ok != true) return;

              await FirebaseFirestore.instance
                  .collection(uid)
                  .doc(tenantId)
                  .delete();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '店舗「$name」を削除しました',
                      style: const TextStyle(fontFamily: 'LINEseed'),
                    ),
                    backgroundColor: const Color(0xFFFCC400),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
