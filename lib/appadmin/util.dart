// ▼ 追加：ステータス表示カード
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/admin_dashboard_screen.dart';
import 'package:yourpay/appadmin/agent/agent_list.dart';

enum DatePreset { today, yesterday, thisMonth, lastMonth, custom }

enum SortBy { revenueDesc, nameAsc, createdDesc }

enum _ChipKind { good, warn, bad }

class StatusCard extends StatelessWidget {
  final String tenantId;
  const StatusCard({super.key, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    // ① tenantIndex から uid を解決するだけのストリーム
    final indexRef = FirebaseFirestore.instance
        .collection('tenantIndex')
        .doc(tenantId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: indexRef.snapshots(),
      builder: (context, idxSnap) {
        if (idxSnap.hasError) {
          return myCard(
            title: '登録状況',
            child: Text('uid解決エラー: ${idxSnap.error}'),
          );
        }
        if (!idxSnap.hasData) {
          return const myCard(
            title: '登録状況',
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final idx = idxSnap.data!.data() ?? {};
        final uid = (idx['uid'] as String?)?.trim();

        if (uid == null || uid.isEmpty) {
          return const myCard(
            title: '登録状況',
            child: Text('この店舗の uid が未登録です（tenantIndex を確認してください）'),
          );
        }

        // ② オーナー配下 /{uid}/{tenantId} の実体を購読
        final tenantRef = FirebaseFirestore.instance
            .collection(uid)
            .doc(tenantId);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: tenantRef.snapshots(),
          builder: (context, tSnap) {
            if (tSnap.hasError) {
              return myCard(
                title: '登録状況',
                child: Text('読込エラー: ${tSnap.error}'),
              );
            }
            if (!tSnap.hasData) {
              return const myCard(
                title: '登録状況',
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (!tSnap.data!.exists) {
              return const myCard(
                title: '登録状況',
                child: Text('店舗ドキュメントが見つかりませんでした'),
              );
            }

            final m = tSnap.data!.data() ?? {};

            // ---- 初期費用 ----
            final initStatus =
                (m['initialFee']?['status'] ??
                        m['billing']?['initialFee']?['status'] ??
                        'none')
                    .toString();
            final initChip = _statusChip(
              label: switch (initStatus) {
                'paid' => '初期費用: 支払い済み',
                'checkout_open' => '初期費用: 決済中',
                _ => '初期費用: 未払い',
              },
              kind: switch (initStatus) {
                'paid' => _ChipKind.good,
                'checkout_open' => _ChipKind.warn,
                _ => _ChipKind.bad,
              },
            );

            // ---- サブスク ----
            final sub = (m['subscription'] as Map?) ?? const {};
            final subPlan = (sub['plan'] ?? '選択なし').toString();
            final subStatus = (sub['status'] ?? '').toString();

            // 期限: nextPaymentAt 優先、なければ currentPeriodEnd
            final rawNext = sub['nextPaymentAt'] ?? sub['currentPeriodEnd'];
            final nextAt = (rawNext is Timestamp) ? rawNext.toDate() : null;

            final overdue =
                (sub['overdue'] == true) ||
                subStatus == 'past_due' ||
                subStatus == 'unpaid';

            final subChip = _statusChip(
              label:
                  'サブスク: $subPlan ${subStatus.toUpperCase()}${nextAt != null ? '（次回: ${_ymd(nextAt)}）' : ''}${overdue ? '（未払い）' : ''}',
              kind: overdue
                  ? _ChipKind.bad
                  : (subStatus == 'active' || subStatus == 'trialing')
                  ? _ChipKind.good
                  : _ChipKind.bad,
            );

            // ---- Connect ----
            final connect = (m['connect'] as Map?) ?? const {};
            final chargesEnabled = connect['charges_enabled'] == true;
            final currentlyDueLen =
                ((connect['requirements'] as Map?)?['currently_due'] as List?)
                    ?.length ??
                0;

            final connectRows = <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    label: 'コネクトアカウント: ${chargesEnabled ? '登録済み' : '未登録'}',
                    kind: chargesEnabled ? _ChipKind.good : _ChipKind.bad,
                  ),
                  if (currentlyDueLen > 0)
                    _statusChip(
                      label: '要提出: $currentlyDueLen 件',
                      kind: _ChipKind.warn,
                    ),
                ],
              ),
            ];

            return myCard(
              title: '登録状況',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 初期費用
                  const Text('初期費用'),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 8, children: [initChip]),
                  const SizedBox(height: 12),

                  // サブスク
                  const Text('サブスクリプション'),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 8, children: [subChip]),
                  const SizedBox(height: 12),

                  // Connect
                  const Text('Stripe Connect'),
                  const SizedBox(height: 4),
                  ...connectRows,
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Widget _statusChip({required String label, required _ChipKind kind}) {
    final color = switch (kind) {
      _ChipKind.good => const Color(0xFF1B5E20),
      _ChipKind.warn => const Color(0xFFB26A00),
      _ChipKind.bad => const Color(0xFFB00020),
    };
    final bg = switch (kind) {
      _ChipKind.good => const Color(0xFFE8F5E9),
      _ChipKind.warn => const Color(0xFFFFF3E0),
      _ChipKind.bad => const Color(0xFFFFEBEE),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class myCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const myCard({required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (action != null) action!,
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class Filters extends StatelessWidget {
  final TextEditingController searchCtrl;
  final DatePreset preset;
  final void Function(DatePreset) onPresetChanged;
  final DateTime? rangeStart; // 使わないが互換のため保持
  final DateTime? rangeEndEx; // 使わないが互換のため保持
  final bool activeOnly; // 今回は非表示（要件外のため）
  final bool chargesEnabledOnly; // 同上
  final ValueChanged<bool> onToggleActive; // 同上
  final ValueChanged<bool> onToggleCharges; // 同上
  final SortBy sortBy;
  final ValueChanged<SortBy> onSortChanged;

  const Filters({
    super.key,
    required this.searchCtrl,
    required this.preset,
    required this.onPresetChanged,
    required this.rangeStart,
    required this.rangeEndEx,
    required this.activeOnly,
    required this.chargesEnabledOnly,
    required this.onToggleActive,
    required this.onToggleCharges,
    required this.sortBy,
    required this.onSortChanged,
  });

  // 共通：黒の太枠デコレーション
  InputDecoration _thickDecoration({
    String? label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(width: 4, color: Colors.black),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(width: 4, color: Colors.black),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return TextField(
      controller: searchCtrl,
      cursorColor: Colors.black,
      style: const TextStyle(height: 1.2),
      decoration: _thickDecoration(
        hint: '店舗名検索',
        prefixIcon: const Icon(Icons.search, color: Colors.black),
        suffixIcon: (searchCtrl.text.isEmpty)
            ? null
            : IconButton(
                tooltip: 'クリア',
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () {
                  // Statelessでもcontrollerを変更すればリスナーに通知される
                  searchCtrl.clear();
                },
              ),
      ),
      onChanged: (_) {
        // 親側がcontrollerの変更をlistenしていれば即時フィルタされる
      },
    );
  }

  Widget _presetDropdown({
    double fontSize = 13, // 文字サイズ
    double vPad = 6, // 上下パディング（フィールド高さに効く）
    double hPad = 12, // 左右パディング
    double itemHeight = 36, // メニュー各行の高さ
    double iconSize = 18,
    bool expanded = true, // 横幅をいっぱいに
    double? fieldHeight, // 明示的に高さ固定したい場合
  }) {
    final items =
        const [
              DropdownMenuItem(value: DatePreset.today, child: Text('今日')),
              DropdownMenuItem(value: DatePreset.yesterday, child: Text('昨日')),
              DropdownMenuItem(value: DatePreset.thisMonth, child: Text('今月')),
              DropdownMenuItem(value: DatePreset.lastMonth, child: Text('先月')),
              DropdownMenuItem(value: DatePreset.custom, child: Text('期間指定')),
            ]
            .map(
              (e) => DropdownMenuItem<DatePreset>(
                value: e.value!,
                child: SizedBox(
                  height: itemHeight,
                  child: Align(alignment: Alignment.centerLeft, child: e.child),
                ),
              ),
            )
            .toList();

    final core = DropdownButtonFormField<DatePreset>(
      value: preset,
      onChanged: (v) => v != null ? onPresetChanged(v) : null,
      isDense: true, // 余白を詰める
      isExpanded: expanded,
      iconSize: iconSize,
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: "LINEseed",
      ), // 入力中/表示中の文字サイズ
      menuMaxHeight: 320,
      decoration: _thickDecoration(label: '期間').copyWith(
        contentPadding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
      ),
      items: items,
    );

    // 明示的に高さを固定したい時だけ SizedBox で包む
    return fieldHeight != null
        ? SizedBox(height: fieldHeight, child: core)
        : core;
  }

  Widget _sortDropdown({
    double fontSize = 13,
    double vPad = 6,
    double hPad = 12,
    double itemHeight = 36,
    double iconSize = 18,
    bool expanded = true,
    double? fieldHeight,
  }) {
    final items =
        const [
              DropdownMenuItem(
                value: SortBy.revenueDesc,
                child: Text('売上の高い順'),
              ),
              DropdownMenuItem(
                value: SortBy.createdDesc,
                child: Text('作成日時が新しい順'),
              ),
            ]
            .map(
              (e) => DropdownMenuItem<SortBy>(
                value: e.value!,
                child: SizedBox(
                  height: itemHeight,
                  child: Align(alignment: Alignment.centerLeft, child: e.child),
                ),
              ),
            )
            .toList();

    final core = DropdownButtonFormField<SortBy>(
      value: sortBy,
      onChanged: (v) => v != null ? onSortChanged(v) : null,
      isDense: true,
      isExpanded: expanded,
      iconSize: iconSize,
      style: TextStyle(fontSize: fontSize, fontFamily: "LINEseed"),
      menuMaxHeight: 320,
      decoration: _thickDecoration(label: '並び順').copyWith(
        contentPadding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
      ),
      items: items,
    );

    return fieldHeight != null
        ? SizedBox(height: fieldHeight, child: core)
        : core;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final isNarrow = w < 420; // スマホ縦
        final isMedium = w >= 420 && w < 720; // タブレット/スマホ横
        // wide >= 720 はPC相当

        // 共通左右パディング
        const hp = 12.0;

        if (isNarrow) {
          // ===== スマホ（狭）: 縦に積む =====
          return Padding(
            padding: const EdgeInsets.fromLTRB(hp, 8, hp, 8),
            child: Column(
              children: [
                _searchField(context),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _presetDropdown()),
                    const SizedBox(width: 8),
                    Expanded(child: _sortDropdown()),
                  ],
                ),
              ],
            ),
          );
        } else if (isMedium) {
          // ===== 中（タブレット/スマホ横）: 検索フル幅 + 2分割 =====
          return Padding(
            padding: const EdgeInsets.fromLTRB(hp, 8, hp, 8),
            child: Column(
              children: [
                _searchField(context),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _presetDropdown()),
                    const SizedBox(width: 8),
                    Expanded(child: _sortDropdown()),
                  ],
                ),
              ],
            ),
          );
        } else {
          // ===== 広（PC）: 横一列（検索広め、ドロップダウン2つ） =====
          return Padding(
            padding: const EdgeInsets.fromLTRB(hp, 8, hp, 8),
            child: Row(
              children: [
                // 検索は広め（2）
                Expanded(flex: 2, child: _searchField(context)),
                const SizedBox(width: 12),
                // プリセットと並び順は同じ幅（1,1）
                Expanded(child: _presetDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _sortDropdown()),
              ],
            ),
          );
        }
      },
    );
  }
}

class Revenue {
  final int sum;
  final int count;
  const Revenue({required this.sum, required this.count});
}

class AgenciesView extends StatelessWidget {
  final String query;
  final AgenciesTab tab;
  final ValueChanged<AgenciesTab> onTabChanged;

  const AgenciesView({
    required this.query,
    required this.tab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 代理店ビュー内のサブ切替（必要なら拡張）
        const Divider(height: 1),
        Expanded(child: AgentsList(query: query)),
      ],
    );
  }
}
