import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SubscriptionCancelListPage extends StatelessWidget {
  const SubscriptionCancelListPage({super.key});

  Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('subscriptionCancelRequests')
      .orderBy('requestedAt', descending: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cardDecoration = BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: theme.colorScheme.outline.withOpacity(0.6),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    );

    return Scaffold(
      // 全体背景はアプリ共通テーマに任せる
      appBar: AppBar(title: const Text('サブスク解約申請一覧')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _query.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  '解約申請の取得中にエラーが発生しました。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
              );
            }

            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  '現在、サブスクチップの解約申請はありません。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final d = docs[index];
                final data = d.data();
                final email = (data['payerEmail'] as String? ?? '').trim();
                final status = data['status'] as String? ?? 'pending';
                final ts = data['requestedAt'] as Timestamp?;
                final dt = ts?.toDate();
                final dtStr = dt != null ? dt.toLocal().toString() : '-';

                Color statusColor;
                String statusLabel;
                switch (status) {
                  case 'done':
                    statusColor = Colors.green.shade600;
                    statusLabel = '処理済み';
                    break;
                  case 'pending':
                  default:
                    statusColor = Colors.orange.shade700;
                    statusLabel = '未処理';
                    break;
                }

                return Container(
                  decoration: cardDecoration,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1行目: メールアドレス + ステータス
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              email.isEmpty ? '(メール未登録)' : email,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: statusColor, width: 1),
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '申請日時：$dtStr',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
