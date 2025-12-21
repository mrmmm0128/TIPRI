import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:yourpay/appadmin/tenant/tenant_detail.dart';

enum _ChipKind { good, warn, bad }

enum Tri { any, yes, no }

class ContractsListForAgent extends StatelessWidget {
  final String agentId;
  final String query; // 空なら無視
  final Tri initialPaid; // 初期費用 paid
  final Tri subActive; // subscription: active/trialing を yes
  final Tri connectCreated; // connect.charges_enabled を yes
  final String? agentPerson; // ★ 追加：担当者名

  const ContractsListForAgent({
    super.key,
    required this.agentId,
    this.query = '',
    this.initialPaid = Tri.any,
    this.subActive = Tri.any,
    this.connectCreated = Tri.any,
    this.agentPerson, // ★ 追加
  });

  // String _ymdhm(DateTime d) =>
  //     '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
  //     '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  // サブスク状態を日本語化
  String _jpSubStatus(String s) {
    switch (s.toLowerCase()) {
      case 'active':
        return '有効';
      case 'trialing':
        return 'トライアル中';
      case 'past_due':
        return '支払い遅延';
      case 'unpaid':
        return '未払い';
      case 'canceled':
        return 'キャンセル';
      case 'incomplete':
        return '未完了';
      case 'incomplete_expired':
        return '期限切れ（未完了）';
      case 'paused':
        return '一時停止';
      case 'inactive':
      case 'nonactive':
      case 'non_active':
        return '無効';
      default:
        return s.isEmpty ? '' : s; // 不明な値はそのまま
    }
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('agencies')
        .doc(agentId)
        .collection('contracts');

    // ▼ 担当者フィルタ（document に agentPersonName が入っている想定）
    if (agentPerson != null && agentPerson!.isNotEmpty) {
      q = q.where('agentPersonName', isEqualTo: agentPerson);
      // ↑ フィールド名は実データに合わせてください
    }
    // ▼ この q を使って stream を作ること！
    final stream = q
        .orderBy('contractedAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return ListTile(title: Text('読込エラー: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const ListTile(title: Text('登録店舗はまだありません'));
        }

        // 親 ListView の中に入ることを想定（自身はスクロールしない）
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Colors.black12),
          itemBuilder: (context, index) {
            final d = docs[index];
            final m = d.data();

            final people =
                (m['agent_people'] as List?)?.cast<String>() ?? const [];
            if (agentPerson != null && agentPerson!.isNotEmpty) {
              if (!people.contains(agentPerson)) return const SizedBox.shrink();
            }

            final tenantId = (m['tenantId'] ?? '').toString();

            //final whenTs = m['contractedAt'];
            //final when = (whenTs is Timestamp) ? whenTs.toDate() : null;
            final ownerUidFromContract = (m['ownerUid'] ?? '').toString();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(ownerUidFromContract)
                  .doc(tenantId)
                  .snapshots(),
              builder: (context, st) {
                final tm = st.data?.data() ?? {};

                // ====== フィルタ判定 ======
                bool passes = true;

                final init =
                    (tm['initialFee']?['status'] ??
                            tm['billing']?['initialFee']?['status'] ??
                            'none')
                        .toString();
                final tenantName = tm["name"];

                final subSt = (tm['subscription']?['status'] ?? '').toString();
                final subPl = (tm['subscription']?['plan'] ?? '選択なし')
                    .toString();
                final chg = tm['connect']?['charges_enabled'] == true;

                final _nextRaw =
                    tm['subscription']?['nextPaymentAt'] ??
                    tm['subscription']?['currentPeriodEnd'];
                final nextAt = (_nextRaw is Timestamp)
                    ? _nextRaw.toDate()
                    : null;

                final overdue =
                    tm['subscription']?['overdue'] == true ||
                    subSt == 'past_due' ||
                    subSt == 'unpaid';

                final ownerUid = ownerUidFromContract.isNotEmpty
                    ? ownerUidFromContract
                    : (tm['uid'] ?? '').toString();

                final q = query.trim().toLowerCase();
                if (q.isNotEmpty) {
                  final hay = [
                    tenantName.toLowerCase(),
                    tenantId.toLowerCase(),
                    ownerUid.toLowerCase(),
                  ].join(' ');
                  passes = hay.contains(q);
                }

                DateTime? _toDate(dynamic v) {
                  if (v is Timestamp) return v.toDate();
                  if (v is int) {
                    return DateTime.fromMillisecondsSinceEpoch(v * 1000);
                  }
                  if (v is double) {
                    return DateTime.fromMillisecondsSinceEpoch(
                      (v * 1000).round(),
                    );
                  }
                  return null;
                }

                final subMap = (tm['subscription'] as Map?) ?? const {};
                final bool isTrialing =
                    (subMap['trial'] as Map?)?['status'] == 'trialing';

                final DateTime? trialEnd =
                    _toDate(subMap['trialEnd']) ??
                    _toDate(subMap['trial_end']) ??
                    _toDate(subMap['currentPeriodEnd']);

                // 初期費用バッジ
                String initLabel;
                _ChipKind initKind;
                if (isTrialing && trialEnd != null) {
                  initLabel = '初期費用 ${_ymd(trialEnd)} 支払予定';
                  initKind = _ChipKind.warn;
                } else if (init == 'paid') {
                  initLabel = '初期費用 済';
                  initKind = _ChipKind.good;
                } else if (init == 'checkout_open') {
                  initLabel = '初期費用 決済中';
                  initKind = _ChipKind.warn;
                } else {
                  initLabel = '初期費用 未払い';
                  initKind = _ChipKind.bad;
                }

                // フィルタ適用
                if (passes && initialPaid != Tri.any) {
                  final isPaid = init == 'paid';
                  passes = (initialPaid == Tri.yes) ? isPaid : !isPaid;
                }
                if (passes && subActive != Tri.any) {
                  final isActive = (subSt == 'active' || subSt == 'trialing');
                  passes = (subActive == Tri.yes) ? isActive : !isActive;
                }
                if (passes && connectCreated != Tri.any) {
                  passes = (connectCreated == Tri.yes) ? chg : !chg;
                }

                if (!passes) return const SizedBox.shrink();

                return ResponsiveContractTile(
                  tenantName: tenantName,
                  subtitleLines: [],
                  chips: [
                    _mini(initLabel, initKind),
                    _mini(
                      'サブスク: $subPl ${_jpSubStatus(subSt)}'
                      '${nextAt != null ? '・次回: ${_ymd(nextAt)}' : ''}'
                      '${overdue ? '・未払い' : ''}',
                      overdue
                          ? _ChipKind.bad
                          : ((subSt == 'active' || subSt == 'trialing')
                                ? _ChipKind.good
                                : _ChipKind.bad),
                    ),

                    _mini(
                      chg ? 'Stripe: 登録済' : 'Stripe: 未登録',
                      chg ? _ChipKind.good : _ChipKind.bad,
                    ),
                  ],
                  onTap: () {
                    if (tenantId.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminTenantDetailPage(
                          ownerUid: ownerUid,
                          tenantId: tenantId,
                          tenantName: tenantName,
                          agentId: agentId ?? "",
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _mini(String label, _ChipKind kind) {
    final color = switch (kind) {
      _ChipKind.good => const Color(0xFF1B5E20),
      _ChipKind.warn => const Color(0xFFB26A00),
      _ChipKind.bad => const Color(0xFFB00020),
    };
    final bg = color.withOpacity(0.08);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class ResponsiveContractTile extends StatelessWidget {
  final String tenantName;
  final List<String> subtitleLines;
  final List<Widget> chips;
  final VoidCallback? onTap;

  const ResponsiveContractTile({
    super.key,
    required this.tenantName,
    required this.subtitleLines,
    required this.chips,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isCompact = w < 420;
    final isMedium = w >= 420 && w < 720;

    // ---------- 共通テキスト ----------
    final title = Text(
      tenantName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    final subtitle = Text(
      subtitleLines.join('  •  '),
      maxLines: isCompact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: const TextStyle(color: Colors.black54, height: 1.2),
    );

    // ---------- バッジ（Wrapで自動改行） ----------
    // PC/タブレットは矢印を押し出さないように上限を少し絞る。スマホはフル幅。
    double? badgeMaxWidth;
    if (!isCompact) {
      final base = isMedium ? w * 0.45 : w * 0.55;
      badgeMaxWidth = base.clamp(160.0, 520.0);
    }
    final Widget badgesWrap = ConstrainedBox(
      constraints: BoxConstraints(
        // compact のときは maxWidth 制限なし＝自然に折り返し
        maxWidth: badgeMaxWidth ?? double.infinity,
      ),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );

    const chevron = Icon(Icons.chevron_right);

    // ---------- レイアウト ----------
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isCompact ? 10 : 12,
          ),
          child: isCompact
              // ====== Compact (全部縦並び・バッジは改行して折り返し) ======
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(child: title),
                        const SizedBox(width: 6),
                        chevron,
                      ],
                    ),
                    const SizedBox(height: 4),
                    subtitle,
                    const SizedBox(height: 6),
                    badgesWrap, // ← Wrapで改行
                  ],
                )
              // ====== Medium / Wide (横並び) ======
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 10),
                    // 左：タイトル＋サブタイトル
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 2), subtitle],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 右：バッジ（幅を抑制して矢印を押し出さない）
                    badgesWrap,
                    const SizedBox(width: 6),
                    chevron,
                  ],
                ),
        ),
      ),
    );
  }
}
