import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yourpay/tenant/method/logout.dart';
import 'package:yourpay/tenant/widget/store_detail/alert_dialog.dart';
import 'package:yourpay/tenant/widget/store_setting/store_admin.dart';
import 'package:yourpay/tenant/widget/store_setting/store_dedution.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_change.dart';
import 'dart:async';

class StoreSettingsTab extends StatefulWidget {
  final String tenantId;
  final String? ownerId;

  const StoreSettingsTab({super.key, required this.tenantId, this.ownerId});

  @override
  State<StoreSettingsTab> createState() => _StoreSettingsTabState();
}

class _StoreSettingsTabState extends State<StoreSettingsTab>
    with AutomaticKeepAliveClientMixin {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  DateTime? _effectiveFromLocal; // 予約の適用開始（未指定なら翌月1日 0:00）
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tenantStatusSub;
  late final ScrollController _scrollCtrl = ScrollController();
  String? _selectedPlan;

  //bool _updatingPlan = false;

  late final ValueNotifier<String> _tenantIdVN;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;
  //Stream<int>? _unreadCountStreamCache; // ← 追加

  final _lineUrlCtrl = TextEditingController();
  final _reviewUrlCtrl = TextEditingController();
  bool _savingExtras = false;

  final _storePercentCtrl = TextEditingController();
  final _storeFixedCtrl = TextEditingController();
  bool _savingStoreCut = false;

  final _storePercentFocus = FocusNode();

  String? _thanksPhotoUrl;
  String? _thanksVideoUrl;
  final bool _uploadingPhoto = false;
  final bool _uploadingVideo = false;
  Uint8List? _thanksPhotoPreviewBytes;
  bool ownerIsMe = true;

  bool? _connected = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _effectiveFromLocal = _firstDayOfNextMonth();
    _loadConnectedOnce();
    _tenantIdVN = ValueNotifier(widget.tenantId);
    if (widget.ownerId == uid) {
      ownerIsMe = true;
    } else {
      ownerIsMe = false;
    }
    // // ★ 初期テナントの未読数 Stream をキャッシュ
    // if (widget.ownerId != null) {
    //   _unreadCountStreamCache = _buildUnreadCountStream(
    //     widget.ownerId!,
    //     widget.tenantId,
    //   );
    // }
  }

  @override
  void didUpdateWidget(covariant StoreSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.tenantId != widget.tenantId) {
      setState(() {
        _connected = null;
        _selectedPlan = null;
        _lineUrlCtrl.clear();
        _reviewUrlCtrl.clear();
        _storePercentCtrl.clear();
        _storeFixedCtrl.clear();
        _tenantIdVN.value = widget.tenantId;
      });

      // if (widget.ownerId != null) {
      //   _unreadCountStreamCache = _buildUnreadCountStream(
      //     widget.ownerId!,
      //     widget.tenantId,
      //   );
      // } else {
      //   _unreadCountStreamCache = null;
      // }

      _startWatchTenantStatus();
    }
  }

  @override
  void dispose() {
    _tenantStatusSub?.cancel(); // ←抜けてたら念のため
    _lineUrlCtrl.dispose();
    _reviewUrlCtrl.dispose();
    _storePercentCtrl.dispose();
    _storeFixedCtrl.dispose();
    _tenantIdVN.dispose();
    _scrollCtrl.dispose(); // ★ 追加
    super.dispose();
  }

  void _startWatchTenantStatus() {
    _tenantStatusSub?.cancel();
    final ownerId = widget.ownerId;
    final tenantId = widget.tenantId;
    if (ownerId == null || tenantId.isEmpty) return;

    final tenantRef = FirebaseFirestore.instance
        .collection(ownerId)
        .doc(tenantId);

    _tenantStatusSub = tenantRef.snapshots().listen((snap) {
      final data = snap.data();
      bool next = false;

      if (data != null) {
        // 1) subscription.status を優先、なければ status を使う
        final subStatus = (data['subscription'] as Map?)?['status'] as String?;
        final rootStatus = data['status'] as String?;
        final s = (subStatus ?? rootStatus)?.trim().toLowerCase();

        // active / trialing / 過去の未払い状態(past_due, unpaid)は “接続中” とみなす
        next =
            s != null &&
            ['active', 'trialing', 'past_due', 'unpaid'].contains(s);
      }

      if (_connected != next && mounted) {
        setState(() => _connected = next);
      }
    });
  }

  // 管理者を外す（確認ダイアログ付き）
  Future<void> _removeAdmin(
    DocumentReference<Map<String, dynamic>> tenantRef,
    String uid,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('管理者を削除', style: TextStyle(color: Colors.black87)),
        content: Text(
          'このメンバーを管理者から外しますか？',
          style: const TextStyle(color: Colors.black87),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.black87)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFFFCC400),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _functions.httpsCallable('removeTenantMember').call({
          'tenantId': widget.tenantId,
          'targetUid': uid,
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '削除に失敗: $e',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    }
  }

  DateTime _firstDayOfNextMonth([DateTime? base]) {
    final b = base ?? DateTime.now();
    final y = (b.month == 12) ? b.year + 1 : b.year;
    final m = (b.month == 12) ? 1 : b.month + 1;
    return DateTime(y, m, 1);
  }

  Future<void> _saveStoreCut(
    DocumentReference<Map<String, dynamic>> tenantRef,
  ) async {
    final percentText = _storePercentCtrl.text.trim();
    // final fixedText = _storeFixedCtrl.text.trim();

    double p = double.tryParse(percentText.replaceAll('％', '')) ?? 0.0;
    //int f = int.tryParse(fixedText.replaceAll('円', '')) ?? 0;

    if (p.isNaN || p < 0) p = 0;
    if (p > 100) p = 100;

    var eff = _effectiveFromLocal ?? _firstDayOfNextMonth();
    final now = DateTime.now();
    if (eff.isBefore(now)) {
      eff = now;
    }

    setState(() => _savingStoreCut = true);
    try {
      await tenantRef.set({
        'storeDeduction': {
          'percent': p,

          //'effectiveFrom': Timestamp.fromDate(eff),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '店舗が差し引く金額割合を保存しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '店舗控除の保存に失敗: $e',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingStoreCut = false);
    }
  }

  Future<bool?> _confirmImmediateCharge(
    BuildContext context,
    String newPlan,
  ) async {
    bool agreed = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white60,
          title: const Text('プラン変更の確認'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'プランを今すぐ変更し、既存の支払方法を用いて本日から1か月分の料金を即時にお支払いします。\n'
                '現在のプランの未経過分の返金は行われません。',
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx, setState) {
                  return CheckboxListTile(
                    dense: true,
                    title: const Text('上記に同意します'),
                    value: agreed,
                    onChanged: (v) => setState(() => agreed = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, agreed),
              child: Text('変更'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changePlan(
    DocumentReference<Map<String, dynamic>> tenantRef,
    String newPlan,
  ) async {
    // まず同意を取得
    final ok = await _confirmImmediateCharge(context, newPlan);
    if (ok != true) return;

    //setState(() => _updatingPlan = true);
    try {
      final tSnap = await tenantRef.get();
      final tData = tSnap.data();

      final sub = (tData?['subscription'] as Map<String, dynamic>?) ?? {};
      final subId = sub['stripeSubscriptionId'] as String?;
      //final status = (sub['status'] as String?) ?? '';

      // サブスク未契約 → Checkout へ
      if (subId == null || subId.isEmpty) {
        final res = await _functions
            .httpsCallable('createSubscriptionCheckout')
            .call(<String, dynamic>{
              'tenantId': widget.tenantId,
              'plan': newPlan,
            });
        final data = res.data as Map;
        final url = data['url'] as String?;
        if (url == null) throw 'Checkout URLが取得できませんでした。';
        await launchUrlString(url, webOnlyWindowName: '_self');
        return;
      }

      // ここから既存サブスクの即日切替
      // ※ trial中かどうかはサーバ側で trial_end/behavior を適切に処理するためフラグ渡しは不要
      final res = await _functions.httpsCallable('changeSubscriptionPlan').call(
        <String, dynamic>{
          'subscriptionId': subId,
          'newPlan': newPlan,
          'tenantId': widget.tenantId, // 突き合わせ安全性UP（サーバ側コード対応済み）
        },
      );

      final Map data = res.data as Map;

      // 正常完了（自動課金も成功）
      if (data['ok'] == true && data['requiresAction'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'プランを $newPlan に変更しました。',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
        return;
      }

      // SCA（要追加認証）や未決済 → 案内を出して Hosted Invoice Page へ
      if (data['requiresAction'] == true) {
        final hosted = data['hostedInvoiceUrl'] as String?;
        final payUrl = data['paymentIntentNextActionUrl'] as String?;
        final msg = '追加認証またはお支払いの完了が必要です。表示されるページで手続きを行ってください。';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: TextStyle(fontFamily: 'LINEseed')),
            backgroundColor: Color(0xFFFCC400),
          ),
        );

        // Hosted Invoice Page があれば優先して開く
        final jump = hosted ?? payUrl;
        if (jump != null) {
          await launchUrlString(jump, webOnlyWindowName: '_self');
          return;
        }
      }

      // ここに来るのは想定外
      throw 'サーバ応答が不正または支払いが完了していません。';
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'プラン変更に失敗: $e',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } finally {
      //if (mounted) setState(() => _updatingPlan = false);
    }
  }

  Future<void> _loadConnectedOnce() async {
    final ownerId = widget.ownerId;
    final tenantId = widget.tenantId;

    if (ownerId == null) {
      if (mounted) setState(() => _connected = false);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection(ownerId)
          .doc(tenantId)
          .get();

      if (!snap.exists) {
        if (mounted) setState(() => _connected = false);
        return;
      }

      final data = snap.data(); // Map<String, dynamic>?
      final status = data?['status']; // dynamic

      // 文字列 "active" を想定。大文字/空白ゆらぎにも軽く対応
      final isActive =
          (status is String) && status.trim().toLowerCase() == 'active';

      if (mounted) setState(() => _connected = isActive);
    } catch (e) {
      if (mounted) setState(() => _connected = false);
    }
  }

  Future<void> _saveExtras(
    DocumentReference<Map<String, dynamic>> tenantRef,
  ) async {
    setState(() => _savingExtras = true);
    try {
      await tenantRef.set({
        'subscription': {
          'extras': {
            'lineOfficialUrl': _lineUrlCtrl.text.trim(),
            'googleReviewUrl': _reviewUrlCtrl.text.trim(),
          },
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '特典リンクを保存しました',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '保存に失敗: $e',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingExtras = false);
    }
  }

  // -------- Build --------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_connected == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    final base = Theme.of(context);
    final themed = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'LINEseed'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'LINEseed'),
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.black87,
        secondary: Colors.black87,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        surfaceTint: Colors.transparent,

        // ★ Material背景系も揃えるならここも
        background: const Color(0xFFF7F7F7),
        surface: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.black87,
        selectionColor: Color(0x33000000),
        selectionHandleColor: Colors.black87,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.black87,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: const TextStyle(color: Colors.black87),
        floatingLabelStyle: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: Colors.black54),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black87, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: Colors.white,
        contentTextStyle: const TextStyle(color: Colors.black87),
        actionTextColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          fontFamily: 'LINEseed',
        ),
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontFamily: 'LINEseed',
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );

    final primaryBtnStyle = FilledButton.styleFrom(
      backgroundColor: Color(0xFFFCC400),
      foregroundColor: Colors.black,
      side: BorderSide(color: Colors.black, width: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    final outlinedBtnStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.black87,
      side: const BorderSide(color: Colors.black87),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return _connected!
        ? Theme(
            data: themed,
            child: ValueListenableBuilder<String>(
              valueListenable: _tenantIdVN,
              builder: (context, tid, _) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                // ★ 選択された tid から毎回“そのときだけ”参照を作る
                final tenantRef = FirebaseFirestore.instance
                    .collection(widget.ownerId!)
                    .doc(tid);

                final publicThankRef = FirebaseFirestore.instance
                    .collection("publicThanks")
                    .doc(tid);

                // ★ 正しい Stream（Doc の snapshots）を渡す
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: tenantRef.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('読み込みエラー: ${snap.error}'));
                    }

                    final data = snap.data?.data() ?? <String, dynamic>{};

                    final sub =
                        (data['subscription'] as Map?)
                            ?.cast<String, dynamic>() ??
                        {};
                    final currentPlan = (sub['plan'] as String?) ?? 'A';

                    final raw = sub['currentPeriodEnd'];
                    DateTime? periodEnd;

                    if (raw is Timestamp) {
                      periodEnd = raw.toDate();
                    } else if (raw is int) {
                      // 10桁=秒, 13桁=ミリ秒 を自動判定
                      final isSeconds = raw < 100000000000; // 1e11 未満なら秒
                      periodEnd = DateTime.fromMillisecondsSinceEpoch(
                        isSeconds ? raw * 1000 : raw,
                      );
                    } else if (raw is num) {
                      final v = raw.toInt();
                      final isSeconds = v < 100000000000;
                      periodEnd = DateTime.fromMillisecondsSinceEpoch(
                        isSeconds ? v * 1000 : v,
                      );
                    } else if (raw is String && raw.isNotEmpty) {
                      // ISO文字列ならこれでOK。秒/ミリ秒の数値文字列なら int にして上と同様に処理してもOK
                      periodEnd = DateTime.tryParse(raw);
                    } else {
                      periodEnd = null;
                    }

                    final periodEndBool = sub["cancelAtPeriodEnd"] ?? false;

                    final extras =
                        (sub['extras'] as Map?)?.cast<String, dynamic>() ?? {};
                    _selectedPlan ??= currentPlan;
                    if (_lineUrlCtrl.text.isEmpty) {
                      _lineUrlCtrl.text =
                          extras['lineOfficialUrl'] as String? ?? '';
                    }
                    if (_reviewUrlCtrl.text.isEmpty) {
                      _reviewUrlCtrl.text =
                          extras['googleReviewUrl'] as String? ?? '';
                    }

                    final store =
                        (data['storeDeduction'] as Map?)
                            ?.cast<String, dynamic>() ??
                        {};
                    if (_storePercentCtrl.text.isEmpty &&
                        store['percent'] != null) {
                      _storePercentCtrl.text = '${store['percent']}';
                    }

                    final trialMap = (sub['trial'] as Map?)
                        ?.cast<String, dynamic>();
                    DateTime? trialStart;
                    DateTime? trialEnd;
                    String? trialStatus;
                    if (trialMap != null) {
                      final tsStart = trialMap['trialStart'];
                      final tsEnd = trialMap['trialEnd'];
                      final tsStatus = trialMap["status"];
                      if (tsStart is Timestamp) {
                        trialStart = tsStart.toDate();
                      }
                      if (tsEnd is Timestamp) {
                        trialEnd = tsEnd.toDate();
                      }
                      if (tsEnd is Timestamp) {
                        trialStatus = tsStatus;
                      }
                    }
                    final size = MediaQuery.of(context).size;
                    final isNarrow = size.width < 480;

                    return ListView(
                      key: const PageStorageKey('store_settings_list'), // ★ 追加
                      controller: _scrollCtrl, // ★ 追加
                      children: [
                        ownerIsMe
                            ? Column(
                                children: [
                                  const SizedBox(height: 20),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 25,
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Color(0xFFFCC400),
                                          foregroundColor: Colors.black,
                                          side: BorderSide(
                                            color: Colors.black,
                                            width: 3,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 7,
                                          ),
                                        ),
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          '/account',
                                          arguments: {
                                            "tenantId": widget.tenantId,
                                          },
                                        ),
                                        icon: const Icon(Icons.manage_accounts),
                                        label: const Text('アカウント情報を確認'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  isNarrow
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 25,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              if (widget.ownerId! == uid) ...[
                                                Expanded(
                                                  child: FilledButton.icon(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor: Color(
                                                        0xFFFCC400,
                                                      ),
                                                      foregroundColor:
                                                          Colors.black,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      side: BorderSide(
                                                        color: Colors.black,
                                                        width: 3,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 16,
                                                            vertical: 10,
                                                          ),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pushNamed(
                                                          context,
                                                          '/tenant',
                                                          arguments: {
                                                            "tenantId":
                                                                widget.tenantId,
                                                          },
                                                        ),
                                                    icon: const Icon(
                                                      Icons
                                                          .store_mall_directory_outlined,
                                                    ),
                                                    label: const Text(
                                                      'テナント情報を確認',
                                                    ),
                                                  ),
                                                ),
                                              ],

                                              const SizedBox(width: 5),
                                              TenantAlertsButton(
                                                tenantId: widget.tenantId,
                                              ),
                                            ],
                                          ),
                                        )
                                      : widget.ownerId! == uid
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 25,
                                          ),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Color(
                                                  0xFFFCC400,
                                                ),
                                                foregroundColor: Colors.black,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.black,
                                                  width: 3,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              onPressed: () =>
                                                  Navigator.pushNamed(
                                                    context,
                                                    '/tenant',
                                                    arguments: {
                                                      "tenantId":
                                                          widget.tenantId,
                                                    },
                                                  ),
                                              icon: const Icon(
                                                Icons
                                                    .store_mall_directory_outlined,
                                              ),
                                              label: const Text('テナント情報を確認'),
                                            ),
                                          ),
                                        )
                                      : const SizedBox(height: 1),
                                ],
                              )
                            : const SizedBox(height: 0),
                        const SizedBox(height: 16),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Text(
                            'サブスクリプション',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),

                        SubscriptionPlanCard(
                          currentPlan: currentPlan,
                          periodEnd: periodEnd,
                          periodEndBool: periodEndBool,
                          trialStatus: trialStatus,
                          trialStart: trialStart,
                          trialEnd: trialEnd,
                          tenantId: widget.tenantId,
                          ownerId: widget.ownerId,
                          uid: uid,
                          tenantRef: tenantRef,
                          publicThankRef: publicThankRef,
                          lineUrlCtrl: _lineUrlCtrl,
                          reviewUrlCtrl: _reviewUrlCtrl,
                          uploadingPhoto: _uploadingPhoto,
                          uploadingVideo: _uploadingVideo,
                          savingExtras: _savingExtras,
                          thanksPhotoPreviewBytes: _thanksPhotoPreviewBytes,
                          thanksPhotoUrl: _thanksPhotoUrl,
                          thanksVideoUrl: _thanksVideoUrl,
                          onSaveExtras: () => _saveExtras(tenantRef),
                          onChangePlan: (newPlan) =>
                              _changePlan(tenantRef, newPlan),
                          primaryBtnStyle: primaryBtnStyle,
                          outlinedBtnStyle: outlinedBtnStyle,
                          // onShowTipriInfo: () => showTipriInfoDialog(context),
                        ),

                        const SizedBox(height: 24),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Text(
                            "スタッフから差し引く金額を設定",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              fontFamily: "LINEseed",
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        StoreDeductionInlineCard(
                          tenantRef: tenantRef,
                          storePercentCtrl: _storePercentCtrl,
                          storePercentFocus: _storePercentFocus,
                          savingStoreCut: _savingStoreCut,
                          onSave: () => _saveStoreCut(tenantRef),
                        ),

                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Text(
                            '管理者一覧',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              fontFamily: "LINEseed",
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        AdminSectionCard(
                          tenantRef: tenantRef,
                          tenantId: tid,
                          ownerId: widget.ownerId,
                          functions: _functions,
                          dataMap: data,
                          onRemoveAdmin: (uidToRemove) =>
                              _removeAdmin(tenantRef, uidToRemove),
                        ),

                        const SizedBox(height: 16),
                        LogoutButton(),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                );
              },
            ),
          )
        : Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: Material(
                        elevation: 6,
                        color: Colors.white,
                        shadowColor: const Color(0x14000000),
                        borderRadius: BorderRadius.circular(20),

                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                20,
                                20,
                                16,
                              ),
                              child: Column(
                                children: [
                                  // アイコンのアクセント（黒地に白）

                                  // タイトル
                                  const Text(
                                    'サブスクリプションを登録しよう',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // 補足文（任意で一行足してリッチに）
                                  const Text(
                                    '登録するとチップ受け取りや詳細レポートが有効になります。',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  LogoutButton(),
                ],
              ),
            ),
          );
  }
}
