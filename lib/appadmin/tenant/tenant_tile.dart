// ======= 店舗行（売上は非同期集計／レスポンシブ） =======
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/util.dart';

class TenantTile extends StatefulWidget {
  final String tenantId;
  final String ownerUid;
  final String name;
  final String status;
  final String plan;
  final bool chargesEnabled;
  final DateTime? createdAt;
  final String rangeLabel;
  final Future<Revenue> Function() loadRevenue;
  final VoidCallback onTap;
  final String Function(int) yen;

  // サブスク表示用
  final String subPlan;
  final String
  subStatus; // 'active' / 'trialing' / 'past_due' / 'unpaid' / 'canceled' ...
  final bool subOverdue;
  final DateTime? subNextPaymentAt;

  // 追加情報（nullable）
  final String? download; // 'done' など

  const TenantTile({
    super.key,
    required this.tenantId,
    required this.ownerUid,
    required this.name,
    required this.status,
    required this.plan,
    required this.chargesEnabled,
    required this.createdAt,
    required this.rangeLabel,
    required this.loadRevenue,
    required this.onTap,
    required this.yen,
    required this.subPlan,
    required this.subStatus,
    required this.subOverdue,
    required this.subNextPaymentAt,
    this.download,
  });

  @override
  State<TenantTile> createState() => _TenantTileState();
}

class _TenantTileState extends State<TenantTile> {
  Revenue? _rev;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.loadRevenue();
    if (!mounted) return;
    setState(() {
      _rev = r;
      _loading = false;
    });
  }

  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

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
      case 'nonactive':
      case 'non_active':
      case 'inactive':
        return '無効';
      default:
        return s;
    }
  }

  String _jpTenantStatus(String s) {
    switch (s.toLowerCase()) {
      case 'active':
        return '有効';
      case 'inactive':
      case 'nonactive':
      case 'non_active':
        return '無効';
      case 'suspended':
        return '一時停止';
      case 'paused':
        return '一時停止';
      case 'archived':
        return 'アーカイブ';
      case 'pending':
      case 'awaiting':
      case 'review':
        return '確認中';
      case 'draft':
        return '下書き';
      case 'deleted':
        return '削除済み';
      default:
        return s; // 不明値はそのまま（ログ目的で残す）
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final isNarrow = w < 560; // 下段に売上を回すブレークポイント
        final isCompact = w < 380; // 文字サイズ/余白を詰める閾値

        // 固定ブランド色（良好ステータス用）
        const brandYellow = Color(0xFFFCC400);

        // 共通チップ（黒枠・角丸ピル・テキスト省略対応）
        Widget chip({
          required String text,
          required Color bg,
          Color fg = Colors.black,
          IconData? icon,
          bool bold = true,
        }) {
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : 10,
              vertical: isCompact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: isCompact ? 13 : 14, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: .2,
                    height: 1.1,
                    fontSize: isCompact ? 12 : null,
                  ),
                ),
              ],
            ),
          );
        }

        // // 旧 subtitle の要約
        // final subtitleLines = <String>[
        //   if (widget.plan.isNotEmpty)
        //     'プラン ${widget.plan} : ${_jpTenantStatus(widget.status)}'
        //         '${widget.chargesEnabled ? '・コネクトアカウント作成済' : '・コネクトアカウント未作成'}',
        // ];

        // Connect
        final connectChip = chip(
          text: widget.chargesEnabled ? 'Connect: 登録済み' : 'Connect: 未登録',
          bg: widget.chargesEnabled ? brandYellow : Colors.white,
          icon: widget.chargesEnabled ? Icons.check : Icons.link_off,
        );

        // サブスク
        final bool subActive =
            widget.subStatus == 'active' || widget.subStatus == 'trialing';
        final bool subBad =
            widget.subOverdue ||
            widget.subStatus == 'past_due' ||
            widget.subStatus == 'unpaid';

        final Color subBg = subBad
            ? const Color(0xFFFFCDD2)
            : (subActive ? brandYellow : Colors.white);
        final IconData subIcon = subBad
            ? Icons.warning_amber_rounded
            : (subActive ? Icons.check_circle : Icons.remove_circle_outline);

        final subParts = <String>[
          'サブスク: ${widget.subPlan.isEmpty ? '未選択' : widget.subPlan}',
          if (widget.subStatus.isNotEmpty) _jpSubStatus(widget.subStatus),
          if (widget.subNextPaymentAt != null &&
              _jpSubStatus(widget.subStatus) != "無効")
            '次回: ${_ymd(widget.subNextPaymentAt!)}',
          if (widget.subOverdue) '未払い',
        ];
        final subChip = chip(
          text: subParts.join(' / '),
          bg: subBg,
          icon: subIcon,
        );

        // 補助情報
        final extraChips = <Widget>[
          if ((widget.download ?? '').isNotEmpty)
            chip(
              text: 'ポスターDL: ${widget.download}',
              bg: Colors.white,
              icon: Icons.download_done,
              bold: false,
            ),
        ];

        // 売上ブロック（右 or 下）
        Widget revenueBlock({bool horizontal = false}) {
          final amount = _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _rev == null ? '—' : widget.yen(_rev!.sum),
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                );

          final overdueBadge = widget.subOverdue
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFB00020).withOpacity(0.25),
                    ),
                  ),
                  child: const Text(
                    '未払いあり',
                    style: TextStyle(
                      color: Color(0xFFB00020),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const SizedBox.shrink();

          if (!horizontal) {
            // 右側に縦積み表示（ワイド）
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.rangeLabel,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                amount,
                if (widget.subOverdue) ...[
                  const SizedBox(height: 4),
                  overdueBadge,
                ],
              ],
            );
          } else {
            // 下段に横並び表示（ナロー）
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.rangeLabel,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    amount,
                  ],
                ),
                if (widget.subOverdue) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerLeft, child: overdueBadge),
                ],
              ],
            );
          }
        }

        // ---------- レイアウト分岐 ----------
        if (!isNarrow) {
          // ワイド：従来の「左：情報／右：売上」
          return Material(
            color: const Color.fromARGB(255, 242, 242, 242), // ← 背景を薄い灰色に
            child: ListTile(
              onTap: widget.onTap,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isCompact ? 4 : 6,
              ),
              title: Text(
                widget.name.isEmpty ? '設定なし' : widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isCompact ? 15 : 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // if (subtitleLines.isNotEmpty)
                  //   Text(
                  //     subtitleLines.join('  •  '),
                  //     maxLines: 1,
                  //     overflow: TextOverflow.ellipsis,
                  //     style: TextStyle(fontSize: isCompact ? 12 : null),
                  //   ),
                  SizedBox(height: isCompact ? 4 : 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [subChip, connectChip, ...extraChips],
                  ),
                ],
              ),
              trailing: revenueBlock(),
            ),
          );
        } else {
          // ナロー：情報 → 売上ブロックの順で縦並び（見切れ防止）
          return InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isCompact ? 8 : 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // タイトル
                  Text(
                    widget.name.isEmpty ? '設定なし' : widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isCompact ? 15 : 16,
                    ),
                  ),
                  // 要約
                  // if (subtitleLines.isNotEmpty) ...[
                  //   const SizedBox(height: 4),
                  //   Text(
                  //     subtitleLines.join('  •  '),
                  //     maxLines: 2,
                  //     overflow: TextOverflow.ellipsis,
                  //     style: TextStyle(fontSize: isCompact ? 12 : null),
                  //   ),
                  // ],
                  SizedBox(height: isCompact ? 6 : 8),
                  // チップ群
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [subChip, connectChip, ...extraChips],
                  ),
                  // 下段：売上（横並び）
                  revenueBlock(horizontal: true),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}
