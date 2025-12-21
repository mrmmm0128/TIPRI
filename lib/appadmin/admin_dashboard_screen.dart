import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/admin_announsment.dart';
import 'package:yourpay/appadmin/cashback_list.dart';
import 'package:yourpay/appadmin/sunscription_delete_apply.dart';
import 'package:yourpay/appadmin/tenant/tenant_list_view.dart';
import 'package:yourpay/appadmin/util.dart';

enum AdminViewMode { tenants, agencies }

enum AgenciesTab { agents }

// ★ 追加：三値フィルタ
enum Tri { any, yes, no }

/// 運営ダッシュボード（トップ → 店舗詳細）
class AdminDashboardHome extends StatefulWidget {
  const AdminDashboardHome({super.key});

  @override
  State<AdminDashboardHome> createState() => _AdminDashboardHomeState();
}

class _AdminDashboardHomeState extends State<AdminDashboardHome> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  DatePreset _preset = DatePreset.thisMonth;
  DateTimeRange? _customRange;

  bool _filterActiveOnly = false;
  bool _filterChargesEnabledOnly = false;

  SortBy _sortBy = SortBy.revenueDesc;

  // ★ 追加：三値フィルタの状態
  Tri _fInitial = Tri.any; // 初期費用 paid
  Tri _fSub = Tri.any; // sub.status in {active, trialing}
  Tri _fConnect = Tri.any; // connect.charges_enabled

  // tenantId -> (sum, count) キャッシュ
  final Map<String, Revenue> _revCache = {};
  DateTime? _rangeStart, _rangeEndEx;

  AdminViewMode _viewMode = AdminViewMode.tenants;
  AgenciesTab agenciesTab = AgenciesTab.agents;

  @override
  void initState() {
    super.initState();
    _applyPreset();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _setAgentPasswordFor(
    String agentId,
    String password,
    String code,
    String email,
  ) async {
    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('adminSetAgencyPassword');
      await fn.call({
        'agentId': agentId,
        'password': password,
        'login': code,
        'email': email,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('パスワードを設定しました')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('設定に失敗: ${e.message ?? e.code}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('設定に失敗: $e')));
    }
  }

  Future<void> _createAgencyDialog() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final code = TextEditingController();
    final percent = TextEditingController(text: '10');
    final pass1 = TextEditingController();
    final pass2 = TextEditingController();
    bool showPass1 = false;
    bool showPass2 = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 3),
          ),
          titleTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: const TextStyle(color: Colors.black),
          title: const Text('代理店を作成'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: '代理店名 *',
                    border: OutlineInputBorder(),
                  ),
                  controller: name,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'メール',
                    border: OutlineInputBorder(),
                  ),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '代理店コード',
                    border: OutlineInputBorder(),
                  ),
                  controller: code,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pass1,
                  obscureText: !showPass1,
                  decoration: InputDecoration(
                    labelText: '初期パスワード（任意・8文字以上）',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPass1 ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setSB(() => showPass1 = !showPass1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pass2,
                  obscureText: !showPass2,
                  decoration: InputDecoration(
                    labelText: '確認用パスワード',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPass2 ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setSB(() => showPass2 = !showPass2),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '※ パスワードを空のまま作成すると、パスワード設定はスキップされます。',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.black, width: 3),
                ),
                backgroundColor: Color(0xFFFCC400),
                foregroundColor: Colors.black,
                overlayColor: Colors.black12,
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Color(0xFFFCC400),
                foregroundColor: Colors.black,
                overlayColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.black, width: 3),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('作成'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      if (name.text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('代理店名は必須です')));
        return;
      }

      final p = int.tryParse(percent.text.trim()) ?? 0;
      final now = FieldValue.serverTimestamp();

      final docRef = await FirebaseFirestore.instance
          .collection('agencies')
          .add({
            'name': name.text.trim(),
            'email': email.text.trim(),
            'code': code.text.trim(),
            'commissionPercent': p,
            'status': 'active',
            'createdAt': now,
            'updatedAt': now,
          });

      if (!mounted) return;

      final pw = pass1.text.trim();
      final pw2 = pass2.text.trim();
      if (pw.isNotEmpty || pw2.isNotEmpty) {
        if (pw.length < 8) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('パスワードは8文字以上にしてください')));
        } else if (pw != pw2) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('パスワードが一致しません')));
        } else {
          await _setAgentPasswordFor(
            docRef.id,
            pw,
            code.text.trim(),
            email.text.trim(),
          );
        }
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('作成しました')));
    }
  }

  // ====== 期間プリセット ======
  void _applyPreset() {
    final now = DateTime.now();
    DateTime start, endEx;

    switch (_preset) {
      case DatePreset.today:
        start = DateTime(now.year, now.month, now.day);
        endEx = start.add(const Duration(days: 1));
        break;
      case DatePreset.yesterday:
        endEx = DateTime(now.year, now.month, now.day);
        start = endEx.subtract(const Duration(days: 1));
        break;
      case DatePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        endEx = DateTime(now.year, now.month + 1, 1);
        break;
      case DatePreset.lastMonth:
        final firstThis = DateTime(now.year, now.month, 1);
        endEx = firstThis;
        start = DateTime(firstThis.year, firstThis.month - 1, 1);
        break;
      case DatePreset.custom:
        if (_customRange != null) {
          start = DateTime(
            _customRange!.start.year,
            _customRange!.start.month,
            _customRange!.start.day,
          );
          endEx = DateTime(
            _customRange!.end.year,
            _customRange!.end.month,
            _customRange!.end.day,
          ).add(const Duration(days: 1));
        } else {
          start = DateTime(now.year, now.month, 1);
          endEx = DateTime(now.year, now.month + 1, 1);
        }
        break;
    }

    setState(() {
      _rangeStart = start;
      _rangeEndEx = endEx;
      _revCache.clear();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked != null) {
      setState(() {
        _preset = DatePreset.custom;
        _customRange = picked;
      });
      _applyPreset();
    }
  }

  Future<Revenue> _loadRevenueForTenant({
    required String tenantId,
    required String ownerUid,
  }) async {
    final key =
        '${tenantId}_${_rangeStart?.millisecondsSinceEpoch}_${_rangeEndEx?.millisecondsSinceEpoch}';
    if (_revCache.containsKey(key)) return _revCache[key]!;

    if (_rangeStart == null || _rangeEndEx == null) {
      final none = const Revenue(sum: 0, count: 0);
      _revCache[key] = none;
      return none;
    }

    final qs = await FirebaseFirestore.instance
        .collection(ownerUid)
        .doc(tenantId)
        .collection('tips')
        .where('status', isEqualTo: 'succeeded')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_rangeStart!),
        )
        .where('createdAt', isLessThan: Timestamp.fromDate(_rangeEndEx!))
        .limit(5000)
        .get();

    int sum = 0;
    for (final d in qs.docs) {
      final m = d.data();
      final cur = (m['currency'] as String?)?.toUpperCase() ?? 'JPY';
      if (cur != 'JPY') continue;
      final v = (m['amount'] as num?)?.toInt() ?? 0;
      if (v > 0) sum += v;
    }

    final data = Revenue(sum: sum, count: qs.docs.length);
    _revCache[key] = data;
    return data;
  }

  String _yen(int v) => '¥${v.toString()}';
  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Widget _triFilterChip({
    required String label,
    required Tri value,
    required ValueChanged<Tri> onChanged,
  }) {
    Tri next(Tri v) =>
        v == Tri.any ? Tri.yes : (v == Tri.yes ? Tri.no : Tri.any);

    String text(Tri v) => switch (v) {
      Tri.any => '$label:すべて',
      Tri.yes => '$label:あり',
      Tri.no => '$label:なし',
    };

    IconData icon(Tri v) => switch (v) {
      Tri.any => Icons.filter_list,
      Tri.yes => Icons.check,
      Tri.no => Icons.close,
    };

    final isActive = value != Tri.any;
    final t = Theme.of(context).textTheme.labelMedium ?? const TextStyle();

    return Material(
      color: isActive ? Colors.black : Color(0xFFFCC400),
      shape: const StadiumBorder(
        side: BorderSide(color: Colors.black, width: 3),
      ),
      child: InkWell(
        onTap: () => onChanged(next(value)),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon(
              //   icon(value),
              //   size: 16,
              //   color: isActive ? Colors.white : Colors.black,
              // ),
              // const SizedBox(width: 6),
              Text(
                text(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: .2,
                  color: isActive ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTheme = Theme.of(context).copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: TextStyle(color: Colors.black),
        hintStyle: TextStyle(color: Colors.black54),
        border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black54),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 2),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: Colors.black),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        background: Colors.white,
        onBackground: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.black12,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Colors.black),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Colors.black),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: Colors.black,
        disabledColor: Colors.white,
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        side: const BorderSide(color: Colors.black),
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected)
                ? Colors.black
                : Colors.white,
          ),
          foregroundColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected)
                ? Colors.white
                : Colors.black,
          ),
          side: MaterialStateProperty.all(
            const BorderSide(color: Colors.black),
          ),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '運営ダッシュボード',
            style: TextStyle(fontFamily: "LINEseed", fontSize: 16),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: IconButton(
                tooltip: 'お知らせ配信',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminAnnouncementPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.campaign_outlined),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: IconButton(
                tooltip: 'キャッシュバック確認',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CashbackListPage()),
                  );
                },
                icon: const Icon(Icons.payments_outlined),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: IconButton(
                tooltip: '解約申請一覧',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionCancelListPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.cancel_schedule_send_outlined),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 画面切替（店舗一覧 / 代理店）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        segmentedButtonTheme: SegmentedButtonThemeData(
                          style: ButtonStyle(
                            // 背景色（選択時：黄色／未選択：白）
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              return states.contains(WidgetState.selected)
                                  ? const Color(0xFFFCC400)
                                  : Colors.white;
                            }),
                            // 文字＆アイコン色（常に黒）
                            foregroundColor: const WidgetStatePropertyAll(
                              Colors.black,
                            ),
                            // 枠線（選択時は太め）
                            side: WidgetStateProperty.resolveWith((states) {
                              return BorderSide(color: Colors.black, width: 3);
                            }),
                            // 角丸・余白
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            // ホバー/押下の波紋色など
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.black12,
                            ),
                            textStyle: WidgetStatePropertyAll(
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: .2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: SegmentedButton<AdminViewMode>(
                        segments: const [
                          ButtonSegment(
                            value: AdminViewMode.tenants,
                            label: Text('店舗一覧'),
                          ),
                          ButtonSegment(
                            value: AdminViewMode.agencies,
                            label: Text('代理店'),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (s) =>
                            setState(() => _viewMode = s.first),
                        showSelectedIcon: false, // ← チェックアイコンを消したい場合
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),
                  if (_viewMode == AdminViewMode.agencies)
                    FilledButton.icon(
                      onPressed: _createAgencyDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('代理店を追加'),
                      style: ButtonStyle(
                        // 背景：テーマカラー（例：secondary）
                        backgroundColor: WidgetStatePropertyAll(
                          Color(0xFFFCC400),
                        ),
                        // 文字・アイコン：黒
                        foregroundColor: const WidgetStatePropertyAll(
                          Colors.black,
                        ),

                        // 太い黒枠
                        side: const WidgetStatePropertyAll(
                          BorderSide(color: Colors.black, width: 3),
                        ),

                        // 角丸・余白
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),

                        // 押下/ホバー時のオーバーレイ
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.black12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 既存の共通フィルタ（期間・キーワード等）
            if (_viewMode != AdminViewMode.agencies) ...[
              Filters(
                searchCtrl: _searchCtrl,
                preset: _preset,
                onPresetChanged: (p) {
                  setState(() => _preset = p);
                  if (p == DatePreset.custom) {
                    _pickCustomRange();
                  } else {
                    _applyPreset();
                  }
                },
                rangeStart: _rangeStart,
                rangeEndEx: _rangeEndEx,
                activeOnly: _filterActiveOnly,
                onToggleActive: (v) => setState(() => _filterActiveOnly = v),
                chargesEnabledOnly: _filterChargesEnabledOnly,
                onToggleCharges: (v) =>
                    setState(() => _filterChargesEnabledOnly = v),
                sortBy: _sortBy,
                onSortChanged: (s) => setState(() => _sortBy = s),
              ),
            ],

            // ★ 追加：三値フィルタ（店舗一覧ビューのときだけ表示）
            if (_viewMode == AdminViewMode.tenants)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _triFilterChip(
                      label: '初期費用',
                      value: _fInitial,
                      onChanged: (v) => setState(() => _fInitial = v),
                    ),
                    _triFilterChip(
                      label: 'サブスク登録',
                      value: _fSub,
                      onChanged: (v) => setState(() => _fSub = v),
                    ),
                    _triFilterChip(
                      label: 'Connect',
                      value: _fConnect,
                      onChanged: (v) => setState(() => _fConnect = v),
                    ),
                    // TextButton.icon(
                    //   onPressed: () => setState(() {
                    //     _fInitial = Tri.any;
                    //     _fSub = Tri.any;
                    //     _fConnect = Tri.any;
                    //   }),
                    //   icon: const Icon(Icons.refresh),
                    //   label: const Text('リセット'),
                    // ),
                  ],
                ),
              ),

            const Divider(height: 1),

            Expanded(
              child: _viewMode == AdminViewMode.tenants
                  ? TenantsListView(
                      query: _query,
                      filterActiveOnly: _filterActiveOnly,
                      filterChargesEnabledOnly: _filterChargesEnabledOnly,
                      sortBy: _sortBy,
                      rangeStart: _rangeStart,
                      rangeEndEx: _rangeEndEx,
                      loadRevenueForTenant: _loadRevenueForTenant,
                      yen: _yen,
                      ymd: _ymd,

                      // ★ 追加：三値フィルタを渡す
                      initialPaid: _fInitial,
                      subActive: _fSub,
                      connectCreated: _fConnect,
                    )
                  : AgenciesView(
                      query: _query,
                      tab: agenciesTab,
                      onTabChanged: (t) => setState(() => agenciesTab = t),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
