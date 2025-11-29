import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ★ 追加
import 'package:flutter/material.dart';

/// キャッシュバック申請 / 完了リスト画面
///
/// - collection: cashbackList
/// - fields (例):
///   - ownerUid: String
///   - tenantId: String
///   - tenantName: String
///   - status: "apply" | "done"
///   - updatedAt: Timestamp
class CashbackListPage extends StatefulWidget {
  const CashbackListPage({super.key});

  @override
  State<CashbackListPage> createState() => _CashbackListPageState();
}

class _CashbackListPageState extends State<CashbackListPage> {
  /// 申請中 (status == apply)
  Query<Map<String, dynamic>> get _applyQuery => FirebaseFirestore.instance
      .collection('cashbackList')
      .where('status', isEqualTo: 'apply')
      .orderBy('updateAt', descending: true);

  /// 完了 (status == done)
  Query<Map<String, dynamic>> get _doneQuery => FirebaseFirestore.instance
      .collection('cashbackList')
      .where('status', isEqualTo: 'done')
      .orderBy('updateAt', descending: true);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Color(0xFFFCC400),
          title: const Text(
            'キャッシュバック管理',
            style: TextStyle(
              fontFamily: 'LINEseed',
              color: Color(0xFFFCC400),
              fontSize: 20,
            ),
          ),
          bottom: TabBar(
            indicatorColor: const Color(0xFFFCC400),
            labelColor: const Color(0xFFFCC400), // 選択中タブの文字色
            unselectedLabelColor: const Color(0xFFFCC400), // 非選択タブも黄色系に
            labelStyle: const TextStyle(
              fontFamily: 'LINEseed',
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: '申請中'),
              Tab(text: '完了'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CashbackListTab(statusLabel: '申請中', isDone: false),
            _CashbackListTab(statusLabel: '完了', isDone: true),
          ],
        ),
      ),
    );
  }
}

class _CashbackListTab extends StatelessWidget {
  const _CashbackListTab({required this.statusLabel, required this.isDone});

  final String statusLabel;
  final bool isDone;

  Query<Map<String, dynamic>> _buildQuery() {
    final col = FirebaseFirestore.instance.collection('cashbackList');
    final status = isDone ? 'done' : 'apply';

    return col
        .where('status', isEqualTo: status)
        .orderBy(
          'updateAt',
          descending: true,
        ); // ★ typo 修正: updateAt → updatedAt
  }

  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    // ★ 権限を持つメールアドレス
    const allowedEmails = ['tiprilogin@gmail.com', 'appfromkomeda@gmail.com'];

    final currentUser = FirebaseAuth.instance.currentUser;
    final currentEmail = currentUser?.email ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '読み込み中にエラーが発生しました\n${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Text(
              isDone ? 'キャッシュバック完了の履歴はまだありません。' : '現在申請中のキャッシュバックはありません。',
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final tenantName = (data['tenantName'] ?? '').toString();
            final tenantId = (data['tenantId'] ?? '').toString();
            final ownerUid = (data['ownerUid'] ?? '').toString();
            final ts = data['updateAt'];
            DateTime? updatedAt;
            if (ts is Timestamp) {
              updatedAt = ts.toDate();
            }

            final subtitleLines = <String>[];
            if (tenantId.isNotEmpty) subtitleLines.add('店舗ID: $tenantId');
            if (ownerUid.isNotEmpty) subtitleLines.add('オーナーID: $ownerUid');
            if (updatedAt != null) {
              subtitleLines.add('更新日時: ${_formatDateTime(updatedAt)}');
            }

            // ★ 振り込み完了ボタンを活性にしていいかどうか
            final canComplete = !isDone && allowedEmails.contains(currentEmail);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isDone
                    ? Colors.green.withOpacity(0.1)
                    : const Color(0xFFFCC400).withOpacity(0.1),
                child: Icon(
                  isDone ? Icons.check_circle : Icons.pending,
                  color: isDone ? Colors.green : const Color(0xFFFCC400),
                ),
              ),
              title: Text(
                tenantName.isEmpty ? '店舗名未設定' : tenantName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'LINEseed',
                ),
              ),
              subtitle: subtitleLines.isEmpty
                  ? null
                  : Text(
                      subtitleLines.join('\n'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
              // ★ trailing を変更：ステータスチップ + (申請中で権限あれば) 振り込み完了ボタン
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusChip(label: statusLabel, isDone: isDone),
                  if (!isDone) const SizedBox(width: 8),
                  if (!isDone)
                    OutlinedButton(
                      onPressed: canComplete
                          ? () async {
                              try {
                                await doc.reference.update({
                                  'status': 'done',
                                  'updatedt':
                                      FieldValue.serverTimestamp(), // ★ 更新日時も更新
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('振り込み完了に更新しました'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('更新に失敗しました: $e')),
                                  );
                                }
                              }
                            }
                          : null, // 権限ない人は非活性
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        side: const BorderSide(color: Color(0xFFFCC400)),
                      ),
                      child: const Text(
                        '振り込み完了',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () {
                // 必要なら詳細ダイアログなどをここで出せる
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(tenantName.isEmpty ? '店舗詳細' : tenantName),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('店舗ID: $tenantId'),
                        const SizedBox(height: 4),
                        Text('ownerUid: $ownerUid'),
                        if (updatedAt != null) ...[
                          const SizedBox(height: 4),
                          Text('更新日時: ${_formatDateTime(updatedAt)}'),
                        ],
                        const SizedBox(height: 12),
                        Text('ステータス: $statusLabel'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static String _formatDateTime(DateTime dt) {
    // シンプルなフォーマット（必要なら intl パッケージでローカライズしてもOK）
    return '${dt.year}/${_two(dt.month)}/${_two(dt.day)} '
        '${_two(dt.hour)}:${_two(dt.minute)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.isDone});

  final String label;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final bg = isDone
        ? Colors.green.withOpacity(0.1)
        : const Color(0xFFFCC400).withOpacity(0.12);
    final fg = isDone ? Colors.green.shade800 : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(
            color: isDone ? Colors.green.shade300 : const Color(0xFFFCC400),
            width: 1,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
