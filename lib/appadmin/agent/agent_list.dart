// 代理店一覧（タップで代理店詳細ページへ遷移）
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/agent/agent_detail.dart';

class AgentsList extends StatelessWidget {
  final String query;
  const AgentsList({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('agencies')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('読込エラー: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        var docs = snap.data!.docs;
        final q = query.trim().toLowerCase();
        if (q.isNotEmpty) {
          docs = docs.where((d) {
            final m = d.data();
            final name = (m['name'] ?? '').toString().toLowerCase();
            final email = (m['email'] ?? '').toString().toLowerCase();
            final code = (m['code'] ?? '').toString().toLowerCase();
            return name.contains(q) ||
                email.contains(q) ||
                code.contains(q) ||
                d.id.toLowerCase().contains(q);
          }).toList();
        }

        if (docs.isEmpty) return const Center(child: Text('代理店がありません'));

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Colors.black),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();

            final name = (m['name'] ?? '(no name)').toString();
            final email = (m['email'] ?? '').toString();
            final code = (m['code'] ?? '').toString();
            final status = (m['status'] ?? 'active').toString();
            final percentVal = m['commissionPercent'];
            final commissionPercent = _formatPercent(percentVal);

            return _AgencyTile(
              agentId: d.id,
              name: name,
              email: email,
              code: code,
              status: status,
              commissionPercent: commissionPercent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AgencyDetailPage(agentId: d.id, agent: false),
                    settings: RouteSettings(arguments: {'agentId': d.id}),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // num / String / null に来ても安全に "xx%" 表記へ
  String _formatPercent(dynamic v) {
    if (v == null) return '—';
    if (v is num) return '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}%';
    final parsed = num.tryParse(v.toString());
    if (parsed == null) return v.toString();
    return '${parsed.toStringAsFixed(parsed % 1 == 0 ? 0 : 1)}%';
  }
}

class _AgencyTile extends StatelessWidget {
  final String agentId;
  final String name;
  final String email;
  final String code;
  final String status;
  final String commissionPercent;
  final VoidCallback onTap;

  const _AgencyTile({
    required this.agentId,
    required this.name,
    required this.email,
    required this.code,
    required this.status,
    required this.commissionPercent,
    required this.onTap,
  });

  static const _brandYellow = Color(0xFFFCC400);

  @override
  Widget build(BuildContext context) {
    return Material(
      //color: Colors.transparent,
      color: const Color.fromARGB(255, 242, 242, 242),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (ctx, c) {
              final narrow = c.maxWidth < 560; // しきい値はテナント側と合わせる
              return narrow ? _buildNarrow(context) : _buildWide(context);
            },
          ),
        ),
      ),
    );
  }

  // ===== チップ（テナント側と揃えた見た目） =====
  Widget _chip({
    required String text,
    required Color bg,
    Color fg = Colors.black,
    IconData? icon,
    bool bold = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
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
            ),
          ),
        ],
      ),
    );
  }

  // ステータス → 日本語 + 色分け
  (_StatusVisual, String) _statusVisual(String raw) {
    final v = raw.toLowerCase();
    if (v == 'active') {
      return (_StatusVisual.good, '有効');
    } else if (v == 'pending' || v == 'review' || v == 'awaiting') {
      return (_StatusVisual.warn, '確認中');
    } else if (v == 'suspended' || v == 'inactive' || v == 'disabled') {
      return (_StatusVisual.bad, '無効');
    }
    return (_StatusVisual.neutral, raw); // 不明値はそのまま
  }

  Color _bgForStatus(_StatusVisual vis) {
    switch (vis) {
      case _StatusVisual.good:
        return _brandYellow; // 良好はブランド黄
      case _StatusVisual.warn:
        return const Color(0xFFFFE0B2); // 薄オレンジ
      case _StatusVisual.bad:
        return const Color(0xFFFFCDD2); // 薄赤
      case _StatusVisual.neutral:
      default:
        return Colors.white;
    }
  }

  IconData? _iconForStatus(_StatusVisual vis) {
    switch (vis) {
      case _StatusVisual.good:
        return Icons.check_circle;
      case _StatusVisual.warn:
        return Icons.warning_amber_rounded;
      case _StatusVisual.bad:
        return Icons.block;
      case _StatusVisual.neutral:
      default:
        return Icons.info_outline;
    }
  }

  // ===== レイアウト wide（横並び） =====
  Widget _buildWide(BuildContext context) {
    final (vis, jp) = _statusVisual(status);

    return Row(
      children: [
        // 左：タイトル＋チップ群
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 代理店名
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              // 情報チップ群
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (email.isNotEmpty)
                    _chip(
                      text: email,
                      bg: Colors.white,
                      icon: Icons.mail,
                      bold: false,
                    ),
                  if (code.isNotEmpty)
                    _chip(
                      text: 'コード: $code',
                      bg: Colors.white,
                      icon: Icons.badge,
                      bold: false,
                    ),
                  // _chip(
                  //   text: '手数料: $commissionPercent',
                  //   bg: Colors.white,
                  //   icon: Icons.percent,
                  //   bold: false,
                  // ),
                  _chip(
                    text: 'ステータス: $jp',
                    bg: _bgForStatus(vis),
                    icon: _iconForStatus(vis),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.chevron_right),
      ],
    );
  }

  // ===== レイアウト narrow（縦積み） =====
  Widget _buildNarrow(BuildContext context) {
    final (vis, jp) = _statusVisual(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (email.isNotEmpty)
              _chip(
                text: email,
                bg: Colors.white,
                icon: Icons.mail,
                bold: false,
              ),
            if (code.isNotEmpty)
              _chip(
                text: 'コード: $code',
                bg: Colors.white,
                icon: Icons.badge,
                bold: false,
              ),
            // _chip(
            //   text: '手数料: $commissionPercent',
            //   bg: Colors.white,
            //   icon: Icons.percent,
            //   bold: false,
            // ),
            _chip(
              text: 'ステータス: $jp',
              bg: _bgForStatus(vis),
              icon: _iconForStatus(vis),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

enum _StatusVisual { good, warn, bad, neutral }
