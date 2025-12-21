import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// PDF まわり
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Web で CSV をダウンロードしたい場合
// ignore: unused_import
import 'package:universal_html/html.dart' as html;
import 'package:yourpay/fonts/jp_font.dart';

// ======== 明細出力画面 ========
class MonthlyReportExportPage extends StatefulWidget {
  final String ownerId;
  final String tenantId;
  final String? tenantName;
  final Set<String> excludedStaffIds;

  const MonthlyReportExportPage({
    super.key,
    required this.ownerId,
    required this.tenantId,
    this.tenantName,
    this.excludedStaffIds = const {},
  });

  @override
  State<MonthlyReportExportPage> createState() =>
      _MonthlyReportExportPageState();
}

enum _OutputKind { pdf, csv }

class _MonthlyReportExportPageState extends State<MonthlyReportExportPage> {
  DateTime? _from;
  DateTime? _to;
  _OutputKind _output = _OutputKind.pdf;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
  }

  // 手数料計算（あなたの元コードと同じロジック）
  int _calcFee(int amount, {num? percent, num? fixed}) {
    final p = (percent ?? 0).toDouble();
    final f = (fixed ?? 0).toDouble();
    final v = (amount * p / 100).round() + f.round();
    return v.clamp(0, amount);
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final res = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: first,
      lastDate: last,
    );
    if (res != null) {
      setState(() => _from = res);
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final res = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: first,
      lastDate: last,
    );
    if (res != null) {
      setState(() => _to = res);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);

    // すでに選択済みならそれを初期値として渡す
    final initial = (_from != null && _to != null)
        ? DateTimeRange(start: _from!, end: _to!)
        : null;

    final res = await _openCustomRangeSheet(
      context,
      initial: initial,
      firstDate: first,
      lastDate: last,
      accent: const Color(0xFFFCC400),
    );

    if (res != null) {
      setState(() {
        _from = DateTime(res.start.year, res.start.month, res.start.day);
        _to = DateTime(res.end.year, res.end.month, res.end.day);
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

  Future<void> _onTapExport() async {
    if (_running) return;

    if (_from == null || _to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '期間を選択してください',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    final from = DateTime(_from!.year, _from!.month, _from!.day);
    final to = DateTime(_to!.year, _to!.month, _to!.day);
    if (!from.isBefore(to) && !from.isAtSameMomentAs(to)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '終了日は開始日以降を指定してください',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    final endExclusive = to.add(const Duration(days: 1));

    setState(() => _running = true);
    try {
      switch (_output) {
        case _OutputKind.pdf:
          await _exportPdf(from, endExclusive);
          break;
        case _OutputKind.csv:
          await _exportCsv(from, endExclusive);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '明細の生成に失敗しました: $e',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: const Color(0xFFFCC400),
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ========= PDF 出力（元の _exportMonthlyReportPdf を日付指定対応にした版） =========
  Future<void> _exportPdf(DateTime start, DateTime endExclusive) async {
    // ↓ ここからは、あなたの _exportMonthlyReportPdf をほぼそのままコピペしています
    //    変更点:
    //    - _rangeBounds() 呼び出しをやめて、start / endExclusive を使う
    //    - widget.ownerId / widget.tenantId / widget.tenantName / widget.excludedStaffIds を利用

    try {
      // 現行の手数料設定（古いレコードのフォールバック用）
      final tSnap = await FirebaseFirestore.instance
          .collection(widget.ownerId)
          .doc(widget.tenantId)
          .get();
      final tData = tSnap.data() ?? {};
      final feeCfg =
          (tData['fee'] as Map?)?.cast<String, dynamic>() ?? const {};
      final storeCfg =
          (tData['storeDeduction'] as Map?)?.cast<String, dynamic>() ??
          const {};
      final feePercent = feeCfg['percent'] as num?;
      final feeFixed = feeCfg['fixed'] as num?;
      final storePercent = storeCfg['percent'] as num?;
      final storeFixed = storeCfg['fixed'] as num?;

      // 期間の Tips を取得
      final qs = await FirebaseFirestore.instance
          .collection(widget.ownerId)
          .doc(widget.tenantId)
          .collection('tips')
          .where('status', isEqualTo: 'succeeded')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(endExclusive))
          .orderBy('createdAt', descending: false)
          .limit(5000)
          .get();

      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '対象期間にデータがありません',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
        return;
      }

      // Stripe手数料の推定（保存が無い古いレコード用）
      int estimateStripeFee(int v) => (v * 34) ~/ 1000;

      // 集計
      int totalGross = 0; // 全体の実額合計
      int totalAppFee = 0; // プラットフォーム手数料合計
      int totalStripeFee = 0; // Stripe手数料合計
      int totalStoreNet = 0; // 店舗受取見込み（net.toStore）の合計
      bool anyStripeEstimated = false;

      final byStaff = <String, Map<String, dynamic>>{};
      int grandGross = 0,
          grandAppFee = 0,
          grandStripe = 0,
          grandStore = 0,
          grandNet = 0;

      for (final doc in qs.docs) {
        final d = doc.data();
        final currency = (d['currency'] as String?)?.toUpperCase() ?? 'JPY';
        if (currency != 'JPY') continue;

        final amount = (d['amount'] as num?)?.toInt() ?? 0;
        if (amount <= 0) continue;

        // プラットフォーム手数料
        final feesMap = (d['fees'] as Map?)?.cast<String, dynamic>();
        final appFeeStored =
            (feesMap?['platform'] as num?)?.toInt() ??
            (d['appFee'] as num?)?.toInt();
        final appFee =
            appFeeStored ??
            _calcFee(amount, percent: feePercent, fixed: feeFixed);

        // Stripe手数料
        final stripeFeeStored =
            ((feesMap?['stripe'] as Map?)?['amount'] as num?)?.toInt();
        final stripeFee = stripeFeeStored ?? estimateStripeFee(amount);
        if (stripeFeeStored == null) anyStripeEstimated = true;

        // 店舗控除
        final split = (d['split'] as Map?)?.cast<String, dynamic>();
        int storeCut;
        if (split != null) {
          final storeAmount = (split['storeAmount'] as num?)?.toInt();
          if (storeAmount != null) {
            storeCut = storeAmount;
          } else {
            final pApplied = (split['percentApplied'] as num?)?.toDouble();
            final fApplied = (split['fixedApplied'] as num?)?.toDouble();
            storeCut = _calcFee(amount, percent: pApplied, fixed: fApplied);
          }
        } else {
          storeCut = _calcFee(amount, percent: storePercent, fixed: storeFixed);
        }

        // 受取先
        final rec = (d['recipient'] as Map?)?.cast<String, dynamic>();
        final staffId =
            (d['employeeId'] as String?) ?? (rec?['employeeId'] as String?);
        final isStaff = staffId != null && staffId.isNotEmpty;

        // net
        final netMap = (d['net'] as Map?)?.cast<String, dynamic>();
        final netToStoreSaved = (netMap?['toStore'] as num?)?.toInt();
        final netToStaffSaved = (netMap?['toStaff'] as num?)?.toInt();

        final netToStore =
            netToStoreSaved ??
            (isStaff
                ? storeCut
                : (amount - appFee - stripeFee).clamp(0, amount));
        final netToStaff =
            netToStaffSaved ??
            (isStaff
                ? (amount - appFee - stripeFee - storeCut).clamp(0, amount)
                : 0);

        // 店舗サマリ
        final include = !isStaff || !widget.excludedStaffIds.contains(staffId);
        if (include) {
          totalGross += amount;
          totalAppFee += appFee;
          totalStripeFee += stripeFee;
          totalStoreNet += netToStore;
        }

        // スタッフ別
        if (isStaff && !widget.excludedStaffIds.contains(staffId)) {
          final staffName =
              (d['employeeName'] as String?) ??
              (rec?['employeeName'] as String?) ??
              'スタッフ';

          final ts = d['createdAt'];
          final when = (ts is Timestamp) ? ts.toDate() : DateTime.now();
          final memo = (d['memo'] as String?) ?? '';

          final bucket = byStaff.putIfAbsent(
            staffId,
            () => {
              'name': staffName,
              'rows': <Map<String, dynamic>>[],
              'gross': 0,
              'appFee': 0,
              'stripe': 0,
              'store': 0,
              'net': 0,
            },
          );

          (bucket['rows'] as List).add({
            'when': when,
            'gross': amount,
            'appFee': appFee,
            'stripe': stripeFee,
            'store': storeCut,
            'net': netToStaff,
            'memo': memo,
          });

          bucket['gross'] = (bucket['gross'] as int) + amount;
          bucket['appFee'] = (bucket['appFee'] as int) + appFee;
          bucket['stripe'] = (bucket['stripe'] as int) + stripeFee;
          bucket['store'] = (bucket['store'] as int) + storeCut;
          bucket['net'] = (bucket['net'] as int) + netToStaff;

          grandGross += amount;
          grandAppFee += appFee;
          grandStripe += stripeFee;
          grandStore += storeCut;
          grandNet += netToStaff;
        }
      }

      // ===== PDF 作成（ここも元コードとほぼ同じ） =====
      String ymd(DateTime d) =>
          '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
      final periodLabel =
          '${ymd(start)}〜${ymd(endExclusive.subtract(const Duration(days: 1)))}';

      final jpTheme = await JpPdfFont.theme();
      final pdf = pw.Document(theme: jpTheme);

      final tenant = widget.tenantName ?? widget.tenantId;
      String yen(int v) => '¥${v.toString()}';
      String fmtDT(DateTime d) =>
          '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          header: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '月次チップレポート',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '店舗: $tenant    対象期間: $periodLabel',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (anyStripeEstimated)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    '※ 一部のStripe手数料は3.6%で推定しています（保存がない決済）。',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              pw.SizedBox(height: 8),
              pw.Divider(),
            ],
          ),
          build: (ctx) {
            final widgets = <pw.Widget>[];

            // ① 店舗入金（見込み）
            widgets.addAll([
              pw.Text(
                '① 店舗入金（見込み）',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey500,
                  width: 0.7,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(2),
                },
                children: [
                  _trSummary('対象期間チップ総額', yen(totalGross)),
                  _trSummary('運営手数料（合計）', yen(totalAppFee)),
                  _trSummary('Stripe手数料（合計）', yen(totalStripeFee)),
                  _trSummary('店舗受取見込み（合計）', yen(totalStoreNet)),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(),
            ]);

            // ② スタッフ別
            if (byStaff.isEmpty) {
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text('スタッフ宛のチップは対象期間にありません。'),
                ),
              );
            } else {
              widgets.addAll([
                pw.Text(
                  '② スタッフ別支払予定',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
              ]);

              final staffEntries = byStaff.entries.toList()
                ..sort(
                  (a, b) =>
                      (b.value['net'] as int).compareTo(a.value['net'] as int),
                );

              for (final e in staffEntries) {
                final name = e.value['name'] as String;
                final rows = (e.value['rows'] as List)
                    .cast<Map<String, dynamic>>();
                rows.sort(
                  (a, b) =>
                      (a['when'] as DateTime).compareTo(b['when'] as DateTime),
                );

                widgets.addAll([
                  pw.SizedBox(height: 10),
                  pw.Text(
                    '■ $name',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.symmetric(
                      inside: const pw.BorderSide(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      outside: const pw.BorderSide(
                        color: PdfColors.grey500,
                        width: 0.7,
                      ),
                    ),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2), // 日時
                      1: pw.FlexColumnWidth(1), // 実額
                      2: pw.FlexColumnWidth(1), // 運営手数料
                      3: pw.FlexColumnWidth(1), // Stripe手数料
                      4: pw.FlexColumnWidth(1), // 店舗控除
                      5: pw.FlexColumnWidth(1), // 受取
                      6: pw.FlexColumnWidth(2), // メモ
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          _cell('日時', bold: true),
                          _cell('実額', bold: true, alignRight: true),
                          _cell('運営手数料', bold: true, alignRight: true),
                          _cell('Stripe手数料', bold: true, alignRight: true),
                          _cell('店舗控除', bold: true, alignRight: true),
                          _cell('受取額', bold: true, alignRight: true),
                          _cell('メモ', bold: true),
                        ],
                      ),
                      ...rows.map((r) {
                        final dt = r['when'] as DateTime;
                        return pw.TableRow(
                          children: [
                            _cell(fmtDT(dt)),
                            _cell(yen(r['gross'] as int), alignRight: true),
                            _cell(yen(r['appFee'] as int), alignRight: true),
                            _cell(yen(r['stripe'] as int), alignRight: true),
                            _cell(yen(r['store'] as int), alignRight: true),
                            _cell(yen(r['net'] as int), alignRight: true),
                            _cell((r['memo'] as String?) ?? ''),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(top: 6),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Text(
                        '小計  実額: ${yen(e.value['gross'] as int)}   '
                        '運営手数料: ${yen(e.value['appFee'] as int)}   '
                        'Stripe手数料: ${yen(e.value['stripe'] as int)}   '
                        '店舗控除: ${yen(e.value['store'] as int)}   '
                        '受取額: ${yen(e.value['net'] as int)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ]);
              }

              widgets.addAll([
                pw.SizedBox(height: 14),
                pw.Divider(),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '（スタッフ宛）総計  実額: ${yen(grandGross)}   '
                    '運営手数料: ${yen(grandAppFee)}   '
                    'Stripe手数料: ${yen(grandStripe)}   '
                    '店舗控除: ${yen(grandStore)}   '
                    '受取額: ${yen(grandNet)}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ]);
            }

            return widgets;
          },
        ),
      );

      // 保存（Webはダウンロード、モバイルは共有）
      String ymdFile(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      final fname =
          'monthly_report_${ymdFile(start)}_to_${ymdFile(endExclusive.subtract(const Duration(days: 1)))}.pdf';

      await Printing.sharePdf(bytes: await pdf.save(), filename: fname);
    } finally {
      // この画面側では _running を finally で戻しているのでここでは何もしない
    }
  }

  // ========= CSV 出力 =========
  Future<void> _exportCsv(DateTime start, DateTime endExclusive) async {
    // PDF と同じロジックでデータを取得・計算しつつ、1レコード = 1行の CSV にする

    // 手数料設定
    final tSnap = await FirebaseFirestore.instance
        .collection(widget.ownerId)
        .doc(widget.tenantId)
        .get();
    final tData = tSnap.data() ?? {};
    final feeCfg = (tData['fee'] as Map?)?.cast<String, dynamic>() ?? const {};
    final storeCfg =
        (tData['storeDeduction'] as Map?)?.cast<String, dynamic>() ?? const {};
    final feePercent = feeCfg['percent'] as num?;
    final feeFixed = feeCfg['fixed'] as num?;
    final storePercent = storeCfg['percent'] as num?;
    final storeFixed = storeCfg['fixed'] as num?;

    final qs = await FirebaseFirestore.instance
        .collection(widget.ownerId)
        .doc(widget.tenantId)
        .collection('tips')
        .where('status', isEqualTo: 'succeeded')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('createdAt', descending: false)
        .limit(5000)
        .get();

    if (qs.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '対象期間にデータがありません',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    int estimateStripeFee(int v) => (v * 34) ~/ 1000;

    // CSV ビルダー
    final buf = StringBuffer();
    // ヘッダ行
    buf.writeln(
      [
        '決済ID',
        '日時',
        '通貨',
        '金額',
        '運営手数料',
        //'Stripe手数料',
        '店舗控除',
        '店舗受取額',
        //'スタッフID',
        'スタッフ名',
        'スタッフ受取額',
      ].map(_csvEscape).join(','),
    );

    String fmtDT(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    for (final doc in qs.docs) {
      final d = doc.data();
      final currency = (d['currency'] as String?)?.toUpperCase() ?? 'JPY';
      if (currency != 'JPY') continue;

      final amount = (d['amount'] as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;

      final feesMap = (d['fees'] as Map?)?.cast<String, dynamic>();
      final appFeeStored =
          (feesMap?['platform'] as num?)?.toInt() ??
          (d['appFee'] as num?)?.toInt();
      final appFee =
          appFeeStored ??
          _calcFee(amount, percent: feePercent, fixed: feeFixed);

      final stripeFeeStored = ((feesMap?['stripe'] as Map?)?['amount'] as num?)
          ?.toInt();
      final stripeFee = stripeFeeStored ?? estimateStripeFee(amount);

      final split = (d['split'] as Map?)?.cast<String, dynamic>();
      int storeCut;
      if (split != null) {
        final storeAmount = (split['storeAmount'] as num?)?.toInt();
        if (storeAmount != null) {
          storeCut = storeAmount;
        } else {
          final pApplied = (split['percentApplied'] as num?)?.toDouble();
          final fApplied = (split['fixedApplied'] as num?)?.toDouble();
          storeCut = _calcFee(amount, percent: pApplied, fixed: fApplied);
        }
      } else {
        storeCut = _calcFee(amount, percent: storePercent, fixed: storeFixed);
      }

      final rec = (d['recipient'] as Map?)?.cast<String, dynamic>();
      final staffId =
          (d['employeeId'] as String?) ?? (rec?['employeeId'] as String?);
      final staffName =
          (d['employeeName'] as String?) ??
          (rec?['employeeName'] as String?) ??
          '';
      final isStaff = staffId != null && staffId.isNotEmpty;

      final netMap = (d['net'] as Map?)?.cast<String, dynamic>();
      final netToStoreSaved = (netMap?['toStore'] as num?)?.toInt();
      final netToStaffSaved = (netMap?['toStaff'] as num?)?.toInt();

      final netToStore =
          netToStoreSaved ??
          (isStaff ? storeCut : (amount - appFee - stripeFee).clamp(0, amount));
      final netToStaff =
          netToStaffSaved ??
          (isStaff
              ? (amount - appFee - stripeFee - storeCut).clamp(0, amount)
              : 0);

      final ts = d['createdAt'];
      final when = (ts is Timestamp) ? ts.toDate() : DateTime.now();
      final memo = (d['memo'] as String?) ?? '';

      buf.writeln(
        [
          doc.id,
          fmtDT(when),
          currency,
          amount.toString(),
          appFee.toString(),
          stripeFee.toString(),
          storeCut.toString(),
          netToStore.toString(),
          staffId ?? '',
          staffName,
          netToStaff.toString(),
          memo,
        ].map(_csvEscape).join(','),
      );
    }

    final csvStr = buf.toString();
    final bytes = utf8.encode('\uFEFF$csvStr');

    // ファイル名
    String ymdFile(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final fname =
        'monthly_report_${ymdFile(start)}_to_${ymdFile(endExclusive.subtract(const Duration(days: 1)))}.csv';

    if (kIsWeb) {
      // Web: ブラウザでダウンロード
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..download = fname;
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } else {
      // モバイル: TODO: path_provider + share_plus 等で保存 or 共有
      // 例）
      // final dir = await getApplicationDocumentsDirectory();
      // final file = File('${dir.path}/$fname');
      // await file.writeAsBytes(bytes);
      // await Share.shareXFiles([XFile(file.path)], text: '月次チップ明細CSV');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSVを出力しました', style: TextStyle(fontFamily: 'LINEseed')),
        backgroundColor: Color(0xFFFCC400),
      ),
    );
  }

  // CSV の 1セル用エスケープ
  String _csvEscape(String v) {
    if (v.contains('"') || v.contains(',') || v.contains('\n')) {
      final escaped = v.replaceAll('"', '""');
      return '"$escaped"';
    }
    return v;
  }

  // ===== PDFセル & サマリー行（元コードを流用） =====
  pw.Widget _cell(String text, {bool bold = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Align(
        alignment: alignRight
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  pw.TableRow _trSummary(String left, String right) => pw.TableRow(
    children: [_cell(left, bold: true), _cell(right, alignRight: true)],
  );

  @override
  Widget build(BuildContext context) {
    final tenantLabel = widget.tenantName ?? widget.tenantId;

    String fmtDate(DateTime? d) {
      if (d == null) return '未選択';
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('明細出力')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '店舗: $tenantLabel',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'LINEseed',
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              '対象期間',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'LINEseed',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickRange,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Colors.black87,
                side: const BorderSide(color: Colors.black87, width: 1.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (() {
                        if (_from == null || _to == null) return '期間を選択';
                        return '${fmtDate(_from)} 〜 ${fmtDate(_to)}';
                      })(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 出力形式
            const Text(
              '出力形式',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'LINEseed',
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_OutputKind>(
              segments: const [
                ButtonSegment(
                  value: _OutputKind.pdf,
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf),
                ),
                ButtonSegment(
                  value: _OutputKind.csv,
                  label: Text('CSV'),
                  icon: Icon(Icons.table_view),
                ),
              ],
              selected: {_output},
              onSelectionChanged: (s) {
                setState(() => _output = s.first);
              },
            ),
            const SizedBox(height: 24),

            // 出力ボタン
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _running ? null : _onTapExport,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  _running ? '出力中…' : 'この条件で出力する',
                  style: const TextStyle(fontFamily: 'LINEseed'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFCC400),
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black, width: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
