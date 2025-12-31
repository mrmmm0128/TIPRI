import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/tenant/widget/store_home/export_report.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_card.dart';
import 'package:yourpay/tenant/widget/store_home/chip_card.dart';
import 'package:yourpay/tenant/widget/store_home/rank_entry.dart';
import 'package:yourpay/tenant/widget/store_home/period_payment_page.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_detail.dart';

class StoreHomeTab extends StatefulWidget {
  final String tenantId;
  final String? tenantName;
  final String? ownerId;
  final VoidCallback? onGoToPrintTab;

  const StoreHomeTab({
    super.key,
    required this.tenantId,
    this.tenantName,
    this.ownerId,
    this.onGoToPrintTab,
  });

  @override
  State<StoreHomeTab> createState() => _StoreHomeTabState();
}

// ==== 期間フィルタ：今日/昨日/今月/先月/任意月/自由指定 ====
enum _RangeMode { today, yesterday, thisMonth, lastMonth, month, custom }

class _StoreHomeTabState extends State<StoreHomeTab> {
  bool loading = false;
  bool _exporting = false;

  // 期間モード
  _RangeMode _mode = _RangeMode.thisMonth;
  DateTime? _selectedMonthStart; // 「月選択」の各月1日
  DateTimeRange? _customRange; // 自由指定

  // 除外するスタッフ（チップの集計・ランキング・PDFから外す）
  final Set<String> _excludedStaff = <String>{};

  // ====== State フィールド ======
  Stream<QuerySnapshot<Map<String, dynamic>>>? _tipsStream;
  String? _lastTipsKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowCreatedTenantToast(),
    );
    _tipsStream;
  }

  @override
  void didUpdateWidget(covariant StoreHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _lastTipsKey = null; // ← 強制的に再作成させる
      _ensureTipsStream(); // ← 新テナントで作り直し
    }
  }

  // 期間から一意キーを作る
  String _makeRangeKey(DateTime? start, DateTime? endExclusive) =>
      '${widget.tenantId}:${start?.millisecondsSinceEpoch ?? -1}-${endExclusive?.millisecondsSinceEpoch ?? -1}';

  // bounds が変わった時だけ stream を作り直す
  void _ensureTipsStream() {
    //final uid = FirebaseAuth.instance.currentUser!.uid; // 取得方法はお好みで
    final b = _rangeBounds(); // 既存の期間計算
    final key = _makeRangeKey(b.start, b.endExclusive);
    if (key == _lastTipsKey && _tipsStream != null) return;

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection(widget.ownerId!)
        .doc(widget.tenantId)
        .collection('tips')
        .where('status', isEqualTo: 'succeeded');

    if (b.start != null) {
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(b.start!),
      );
    }
    if (b.endExclusive != null) {
      q = q.where('createdAt', isLessThan: Timestamp.fromDate(b.endExclusive!));
    }
    q = q.orderBy('createdAt', descending: true).limit(1000);

    _tipsStream = q.snapshots();
    _lastTipsKey = key;
  }

  // ===== ユーティリティ =====
  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _firstDayOfNextMonth(DateTime d) => (d.month == 12)
      ? DateTime(d.year + 1, 1, 1)
      : DateTime(d.year, d.month + 1, 1);

  List<DateTime> _monthOptions() {
    final now = DateTime.now();
    final cur = _firstDayOfMonth(now);
    return List.generate(24, (i) => DateTime(cur.year, cur.month - i, 1));
  }

  int _calcFee(int amount, {num? percent, num? fixed}) {
    final p = ((percent ?? 0)).clamp(0, 100);
    final f = ((fixed ?? 0)).clamp(0, 1e9);
    final percentPart = (amount * p / 100).floor();
    return (percentPart + f.toInt()).clamp(0, amount);
  }

  final uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _maybeShowCreatedTenantToast() async {
    final uri = Uri.base;
    final frag =
        uri.fragment; // 例: "/?toast=tenant_created&tenant=xxx&name=YYY"
    final qi = frag.indexOf('?');
    final qp = <String, String>{}..addAll(uri.queryParameters);
    if (qi >= 0) qp.addAll(Uri.splitQueryString(frag.substring(qi + 1)));

    if (qp['toast'] != 'tenant_created') return;

    String name = qp['name'] ?? '';
    final tid = qp['tenant'];
    final ownerIdDoc = await FirebaseFirestore.instance
        .collection("tenantIndex")
        .doc(tid)
        .get();
    final ownerId = ownerIdDoc["uid"];
    print(ownerId);
    if (name.isEmpty && tid != null && tid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(ownerId!)
            .doc(tid)
            .get();
        name = (doc.data()?['name'] as String?) ?? '';
      } catch (_) {}
    }

    final msg = name.isNotEmpty ? '$name のサブスクリプションを登録しました' : '店舗を作成しました';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontFamily: 'LINEseed')),
        backgroundColor: Color(0xFFFCC400),
      ),
    );

    // （任意）URLの一度きりパラメータを消しておく → Webのみ使うならコメントアウト外す
    // try {
    //   final clean = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/#/';
    //   html.window.history.replaceState(null, '', clean);
    // } catch (_) {}
  }

  String _rangeLabel() {
    String ym(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}';
    String ymd(DateTime d) =>
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    switch (_mode) {
      case _RangeMode.today:
        return '今日（${ymd(today0)}）';
      case _RangeMode.yesterday:
        final yst = today0.subtract(const Duration(days: 1));
        return '昨日（${ymd(yst)}）';
      case _RangeMode.thisMonth:
        final s = _firstDayOfMonth(now);
        return '今月（${ym(s)}）';
      case _RangeMode.lastMonth:
        final s = _firstDayOfMonth(DateTime(now.year, now.month - 1, 1));
        return '先月（${ym(s)}）';
      case _RangeMode.month:
        final s = _selectedMonthStart ?? _firstDayOfMonth(now);
        return '月選択（${ym(s)}）';
      case _RangeMode.custom:
        if (_customRange == null) return '期間指定';
        return '${ymd(_customRange!.start)}〜${ymd(_customRange!.end)}';
    }
  }

  ({DateTime? start, DateTime? endExclusive}) _rangeBounds() {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    switch (_mode) {
      case _RangeMode.today:
        return (
          start: today0,
          endExclusive: today0.add(const Duration(days: 1)),
        );
      case _RangeMode.yesterday:
        final s = today0.subtract(const Duration(days: 1));
        return (start: s, endExclusive: today0);
      case _RangeMode.thisMonth:
        final s = _firstDayOfMonth(now);
        return (start: s, endExclusive: _firstDayOfNextMonth(s));
      case _RangeMode.lastMonth:
        final s = _firstDayOfMonth(DateTime(now.year, now.month - 1, 1));
        return (start: s, endExclusive: _firstDayOfNextMonth(s));
      case _RangeMode.month:
        final s = _selectedMonthStart ?? _firstDayOfMonth(now);
        return (start: s, endExclusive: _firstDayOfNextMonth(s));
      case _RangeMode.custom:
        if (_customRange == null) return (start: null, endExclusive: null);
        final s = DateTime(
          _customRange!.start.year,
          _customRange!.start.month,
          _customRange!.start.day,
        );
        final e = DateTime(
          _customRange!.end.year,
          _customRange!.end.month,
          _customRange!.end.day,
        ).add(const Duration(days: 1));
        return (start: s, endExclusive: e);
    }
  }

  // ==== 1) 既存の _pickCustomRange を “まるっと”置換 ====
  //
  // 使い方はそのまま：await _pickCustomRange();
  // 選択結果は _mode = _RangeMode.custom / _customRange に反映されます。

  Future<void> _pickCustomRange() async {
    final picked = await _openCustomRangeSheet(
      context,
      initial: _customRange,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1),
      accent: const Color(0xFFFCC400),
    );
    if (picked != null) {
      setState(() {
        _mode = _RangeMode.custom;
        _customRange = picked;
      });
    }
  }

  Future<DateTimeRange?> _openCustomRangeSheet(
    BuildContext context, {
    DateTimeRange? initial,
    required DateTime firstDate,
    required DateTime lastDate,
    Color accent = const Color(0xFFFCC400), // ブランド黄
  }) async {
    DateTime? start = initial?.start;
    DateTime? end = initial?.end;
    DateTime displayed = (initial?.start ?? DateTime.now());

    DateTime _at00(DateTime d) => DateTime(d.year, d.month, d.day);
    bool _sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    DateTime _clampDate(DateTime d) {
      final dd = _at00(d);
      if (dd.isBefore(_at00(firstDate))) return _at00(firstDate);
      if (dd.isAfter(_at00(lastDate))) return _at00(lastDate);
      return dd;
    }

    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void setRange(DateTime? s, DateTime? e) => setLocal(() {
              start = s;
              end = e;
            });

            // 範囲選択ロジック（開始→終了）
            void onSelect(DateTime day) {
              final d = _clampDate(day);
              if (start == null || (start != null && end != null)) {
                setRange(d, null);
              } else {
                if (d.isBefore(start!)) {
                  setRange(d, start);
                } else if (_sameDay(d, start!)) {
                  setRange(d, d); // 単日
                } else {
                  setRange(start, d);
                }
              }
            }

            void clearRange() => setRange(null, null);
            bool canConfirm = (start != null && end != null);

            Future<void> confirm() async {
              if (!canConfirm) return;
              await Future<void>.delayed(Duration.zero);
              if (Navigator.canPop(ctx)) {
                Navigator.pop(ctx, DateTimeRange(start: start!, end: end!));
              }
            }

            String ym(DateTime d) => '${d.year}年${d.month}月';
            List<String> wk = const ['日', '月', '火', '水', '木', '金', '土'];

            // 表示月の先頭（日曜始まり）を計算
            DateTime firstOfMonth = DateTime(
              displayed.year,
              displayed.month,
              1,
            );
            int offset = firstOfMonth.weekday % 7; // Mon=1..Sun=7 → Sun=0
            DateTime gridStart = firstOfMonth.subtract(Duration(days: offset));

            // ナビゲーション
            void prevMonth() {
              final d = DateTime(displayed.year, displayed.month - 1, 1);
              setLocal(() => displayed = _clampDate(d));
            }

            void nextMonth() {
              final d = DateTime(displayed.year, displayed.month + 1, 1);
              setLocal(() => displayed = _clampDate(d));
            }

            // ボタン共通スタイル
            final ButtonStyle primaryBtnStyle = FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(44),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: Colors.black, width: 3),
            );

            Widget buildDayCell(DateTime day) {
              final d = _at00(day);
              final isDisabled =
                  d.isBefore(_at00(firstDate)) || d.isAfter(_at00(lastDate));
              final inThisMonth = d.month == displayed.month;

              final isStart = (start != null) && _sameDay(d, start!);
              final isEnd = (end != null) && _sameDay(d, end!);
              final selected = isStart || isEnd;

              final inRange =
                  (start != null &&
                  end != null &&
                  d.isAfter(_at00(start!)) &&
                  d.isBefore(_at00(end!)));

              // テキスト色
              final baseTextColor = isDisabled
                  ? Colors.black26
                  : (inThisMonth ? Colors.black87 : Colors.black38);
              final textColor = selected ? Colors.black : baseTextColor;

              return GestureDetector(
                onTap: isDisabled ? null : () => onSelect(d),
                child: Container(
                  // ★ 丸は使わず、背景だけで表現
                  decoration: BoxDecoration(
                    color: selected
                        ? accent
                        : (inRange
                              // ignore: deprecated_member_use
                              ? accent.withOpacity(0.25)
                              : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    border: selected
                        ? Border.all(color: Colors.black, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '${d.day}',
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ハンドル
                    Container(
                      height: 4,
                      width: 40,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // ヘッダ（前月/次月/閉じる）
                    Row(
                      children: [
                        IconButton(
                          tooltip: '前の月',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: prevMonth,
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              ym(displayed),
                              style: const TextStyle(
                                fontFamily: 'LINEseed',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '次の月',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: nextMonth,
                        ),
                        IconButton(
                          tooltip: '閉じる',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 選択中ラベル
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        () {
                          if (start == null && end == null) return '期間が未選択';
                          if (start != null && end == null) {
                            final s = start!;
                            return '開始: ${s.year}/${s.month.toString().padLeft(2, '0')}/${s.day.toString().padLeft(2, '0')}（終了を選択）';
                          }
                          final s = start!;
                          final e = end!;
                          return '${s.year}/${s.month.toString().padLeft(2, '0')}/${s.day.toString().padLeft(2, '0')} 〜 '
                              '${e.year}/${e.month.toString().padLeft(2, '0')}/${e.day.toString().padLeft(2, '0')}';
                        }(),
                        style: const TextStyle(
                          fontFamily: 'LINEseed',
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 曜日見出し（Sun〜Sat）
                    Row(
                      children: List.generate(7, (i) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              wk[i],
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: i == 0
                                    ? Colors.redAccent
                                    : (i == 6
                                          ? Colors.blueAccent
                                          : Colors.black87),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),

                    // 月グリッド（6行×7列）
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(6, (row) {
                        return Row(
                          children: List.generate(7, (col) {
                            final idx = row * 7 + col;
                            final day = gridStart.add(Duration(days: idx));
                            return Expanded(child: buildDayCell(day));
                          }),
                        );
                      }),
                    ),

                    const SizedBox(height: 12),

                    // アクション
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: clearRange,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              foregroundColor: Colors.black87,
                              side: const BorderSide(
                                color: Colors.black87,
                                width: 1.6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('クリア'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: primaryBtnStyle,
                            onPressed: canConfirm
                                ? () async => confirm()
                                : null,
                            icon: const Icon(Icons.check),
                            label: const Text(
                              'この期間で確定',
                              style: TextStyle(fontFamily: 'LINEseed'),
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
        );
      },
    );
  }

  void _openPeriodPayments({RecipientFilter filter = RecipientFilter.all}) {
    final b = _rangeBounds();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PeriodPaymentsPage(
          tenantId: widget.tenantId,
          tenantName: widget.tenantName,
          start: b.start,
          endExclusive: b.endExclusive,
          recipientFilter: filter,
          ownerId: widget.ownerId!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthOptions();
    var monthValue = _selectedMonthStart ?? months.first;
    _ensureTipsStream(); // ★ 追加：ここで stream を安定化

    // === 置き換え: 以前の topCta 定義をこれに差し替え ===
    final topCta = Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左: タイトル
          const Expanded(
            child: Text(
              'チップまとめ',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                fontFamily: "LINEseed",
              ),
            ),
          ),
          const SizedBox(width: 12),

          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MonthlyReportExportPage(
                          ownerId: widget
                              .ownerId!, // これまで _exportMonthlyReportPdf で使っていた ownerId
                          tenantId: widget.tenantId,
                          tenantName: widget.tenantName,
                          excludedStaffIds: _excludedStaff,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 25),
                  label: const Text('明細'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    backgroundColor: const Color(0xFFFCC400),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Colors.black, width: 3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // === フィルタバー ===
    final filterBar = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            RangePill(
              label: '今日',
              active: _mode == _RangeMode.today,
              onTap: () => setState(() => _mode = _RangeMode.today),
            ),
            RangePill(
              label: '昨日',
              active: _mode == _RangeMode.yesterday,
              onTap: () => setState(() => _mode = _RangeMode.yesterday),
            ),
            RangePill(
              label: '今月',
              active: _mode == _RangeMode.thisMonth,
              onTap: () => setState(() => _mode = _RangeMode.thisMonth),
            ),
            RangePill(
              label: '先月',
              active: _mode == _RangeMode.lastMonth,
              onTap: () => setState(() => _mode = _RangeMode.lastMonth),
            ),
            RangePill(
              label: _mode == _RangeMode.custom ? _rangeLabel() : '期間指定',
              active: _mode == _RangeMode.custom,
              onTap: _pickCustomRange,
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          topCta,
          const Text(
            "期間",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              fontFamily: "LINEseed",
            ),
          ),
          const SizedBox(height: 7),
          filterBar,

          // ===== データ＆UI（スタッフチップ/ランキング/統計） =====
          StreamBuilder<QuerySnapshot>(
            stream: _tipsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: CardShellHome(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('読み込みエラー: ${snap.error}'),
                    ),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];

              // まず「この期間に現れたスタッフ一覧（全員）」を作る（合計額で並び替え）
              final Map<String, int> staffTotalsAll = {};
              final Map<String, String> staffNamesAll = {};
              for (final doc in docs) {
                final d = doc.data() as Map<String, dynamic>;
                final recipient = (d['recipient'] as Map?)
                    ?.cast<String, dynamic>();
                final employeeId =
                    (d['employeeId'] as String?) ??
                    recipient?['employeeId'] as String?;
                if (employeeId != null && employeeId.isNotEmpty) {
                  final name =
                      (d['employeeName'] as String?) ??
                      (recipient?['employeeName'] as String?) ??
                      'スタッフ';
                  staffNamesAll[employeeId] = name;
                  final amount = (d['amount'] as num?)?.toInt() ?? 0;
                  staffTotalsAll[employeeId] =
                      (staffTotalsAll[employeeId] ?? 0) + amount;
                }
              }
              final staffOrder = staffTotalsAll.keys.toList()
                ..sort(
                  (a, b) => (staffTotalsAll[b] ?? 0).compareTo(
                    staffTotalsAll[a] ?? 0,
                  ),
                );

              // === スタッフ切替ボタン列（除外は暗く） ===
              Widget staffChips() {
                if (staffOrder.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in staffOrder)
                        ChoiceChip(
                          label: Text(staffNamesAll[id] ?? 'スタッフ'),
                          selected: _excludedStaff.contains(id),
                          onSelected: (sel) {
                            setState(() {
                              if (sel) {
                                _excludedStaff.add(id);
                              } else {
                                _excludedStaff.remove(id);
                              }
                            });
                          },

                          // 配色（選択中は黒塗り＋白文字 / 非選択は白地＋黒文字）
                          backgroundColor: Color(0xFFFCC400),
                          selectedColor: Colors.white,

                          // ラベルのフォントと色（LINEseedで統一）
                          labelStyle: TextStyle(
                            fontFamily: 'LINEseed',
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),

                          // 太い黒枠
                          shape: const StadiumBorder(
                            side: BorderSide(color: Colors.black, width: 3),
                          ),

                          // 余計なチェックマークは出さない
                          showCheckmark: false,

                          // タップ領域少しコンパクトに（お好みで）
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      if (_excludedStaff.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              setState(() => _excludedStaff.clear()),
                          child: const Text('全員含める'),
                        ),
                    ],
                  ),
                );
              }

              // ==== 集計（除外を反映）====
              int totalAll = 0, countAll = 0;
              int totalStore = 0, countStore = 0;
              int totalStaff = 0, countStaff = 0;
              final Map<String, StaffAgg> agg = {};
              final Map<String, int> payerTotals = {}; // ★ 追加: 送金者集計

              for (final doc in docs) {
                final d = doc.data() as Map<String, dynamic>;
                final currency =
                    (d['currency'] as String?)?.toUpperCase() ?? 'JPY';
                if (currency != 'JPY') continue;
                final amount = (d['amount'] as num?)?.toInt() ?? 0;

                final recipient = (d['recipient'] as Map?)
                    ?.cast<String, dynamic>();
                final employeeId =
                    (d['employeeId'] as String?) ??
                    recipient?['employeeId'] as String?;
                final isStaff = (employeeId != null && employeeId.isNotEmpty);

                // 除外ロジック：スタッフ分は除外セットに入っていたらスキップ
                final include =
                    !isStaff || !_excludedStaff.contains(employeeId);
                if (!include) continue;

                totalAll += amount;
                countAll += 1;

                if (isStaff) {
                  totalStaff += amount;
                  countStaff += 1;
                  final employeeName =
                      (d['employeeName'] as String?) ??
                      (recipient?['employeeName'] as String?) ??
                      'スタッフ';
                  final entry = agg.putIfAbsent(
                    employeeId,
                    () => StaffAgg(name: employeeName),
                  );
                  entry.total += amount;
                  entry.count += 1;
                } else {
                  totalStore += amount;
                  countStore += 1;
                }

                // 送金者集計（名前があるもののみ）
                final payerName = (d['payerName'] as String?)?.trim() ?? '';
                if (payerName.isNotEmpty) {
                  payerTotals[payerName] =
                      (payerTotals[payerName] ?? 0) + amount;
                }
              }

              // 送金者ランキング作成
              final payerRanking =
                  payerTotals.entries
                      .map((e) => PayerAgg(name: e.key, total: e.value))
                      .toList()
                    ..sort((a, b) => b.total.compareTo(a.total));

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CardShellHome(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'この期間のデータがありません',
                              style: TextStyle(
                                color: Colors.black87,
                                fontFamily: "LINEseed",
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'QRコードを印刷し、チップを受け取ろう',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontFamily: "LINEseed",
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFCC400),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 3,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'LINEseed',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () {
                                // 親から渡してもらうコールバックで「印刷」タブへ
                                widget.onGoToPrintTab?.call();
                              },
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('印刷タブを開く'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final ranking = agg.entries.toList()
                ..sort((a, b) => b.value.total.compareTo(a.value.total));
              final top10 = ranking.take(10).toList();
              final entries = List.generate(top10.length, (i) {
                final e = top10[i];
                return RankEntry(
                  rank: i + 1,
                  employeeId: e.key,
                  name: e.value.name,
                  amount: e.value.total,
                  count: e.value.count,
                  ownerId: widget.ownerId!,
                );
              });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "スタッフ",
                    style: TextStyle(
                      color: Colors.black87,
                      fontFamily: "LINEseed",
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  staffChips(),
                  // ★ 横並びに変更
                  LayoutBuilder(
                    builder: (context, box) {
                      final isNarrow = box.maxWidth < 600;
                      if (isNarrow) {
                        return Column(
                          mainAxisSize: MainAxisSize.min, // ← 追加
                          children: [
                            TotalsCard(
                              totalYen: totalAll,
                              count: countAll,
                              onTap: _openPeriodPayments,
                            ),
                            const SizedBox(height: 10), // 12 -> 10
                            PayerRankingCard(
                              topPayers: payerRanking,
                              onTap: _openPeriodPayments,
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TotalsCard(
                                totalYen: totalAll,
                                count: countAll,
                                onTap: _openPeriodPayments,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PayerRankingCard(
                                topPayers: payerRanking,
                                onTap: _openPeriodPayments,
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10), // 12 -> 10
                  // 例：SplitMetricsRow の配置箇所
                  SplitMetricsRow(
                    storeYen: totalStore,
                    storeCount: countStore,
                    staffYen: totalStaff,
                    staffCount: countStaff,
                    onTapStore: () => _openPeriodPayments(
                      filter: RecipientFilter.storeOnly, // ★ 店舗のみ
                    ),
                    onTapStaff: () => _openPeriodPayments(
                      filter: RecipientFilter.staffOnly, // ★ スタッフのみ
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'スタッフランキング 上位10名',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      fontFamily: "LINEseed",
                    ),
                  ),
                  const SizedBox(height: 8),
                  RankingGrid(
                    tenantId: widget.tenantId,
                    entries: entries,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    ownerId: widget.ownerId!,
                    onEntryTap: (entry) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StaffDetailScreen(
                            tenantId: widget.tenantId,
                            employeeId: entry.employeeId,
                            ownerId: widget.ownerId!,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
