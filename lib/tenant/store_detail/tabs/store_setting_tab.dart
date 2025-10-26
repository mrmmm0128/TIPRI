import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yourpay/tenant/method/image_scrol.dart';
import 'package:yourpay/tenant/widget/store_setting/b_plan.dart';
import 'package:yourpay/tenant/widget/store_setting/subscription_card.dart';
import 'package:yourpay/tenant/widget/store_staff/show_video_preview.dart';
import 'package:yourpay/tenant/widget/store_setting/c_plan.dart';
import 'package:yourpay/tenant/widget/store_setting/trial_progress_bar.dart';
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
  bool _isCompactWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w < 900; // ~ タブレットまでをポップアップ対象に
  }

  late final ScrollController _scrollCtrl = ScrollController();

  String? _selectedPlan;
  String? _pendingPlan;
  bool _changingPlan = false;
  bool _updatingPlan = false;
  late final ValueNotifier<String> _tenantIdVN;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;

  final _lineUrlCtrl = TextEditingController();
  final _reviewUrlCtrl = TextEditingController();
  bool _savingExtras = false;

  final _storePercentCtrl = TextEditingController();
  final _storeFixedCtrl = TextEditingController();
  bool _savingStoreCut = false;

  final _storePercentFocus = FocusNode();
  bool _loggingOut = false;

  String? _thanksPhotoUrl;
  String? _thanksVideoUrl;
  bool _uploadingPhoto = false;
  bool _uploadingVideo = false;
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
  }

  @override
  void didUpdateWidget(covariant StoreSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親から tenantId が変わった時だけ再読込（タップでメニュー開いただけでは変わらない）
    if (oldWidget.tenantId != widget.tenantId) {
      setState(() {
        _connected = null; // ローディング表示へ
        _selectedPlan = null; // 表示を最新に
        _lineUrlCtrl.clear();
        _reviewUrlCtrl.clear();
        _storePercentCtrl.clear();
        _storeFixedCtrl.clear();
        _tenantIdVN.value = widget.tenantId;
      });

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

  Stream<int>? _unreadCountStream(String ownerUid, String tenantId) {
    try {
      final q = FirebaseFirestore.instance
          .collection(ownerUid)
          .doc(tenantId)
          .collection('alerts')
          .where('read', isEqualTo: false);
      return q.snapshots().map((snap) => snap.docs.length);
    } catch (_) {
      return null;
    }
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

  Widget _buildNotificationsAction() {
    if (widget.ownerId == null) {
      return IconButton(
        onPressed: null,
        icon: const Icon(Icons.notifications_outlined),
      );
    }
    return StreamBuilder<int>(
      stream: _unreadCountStream(widget.ownerId!, widget.tenantId),
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: _openAlertsPanel,
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'お知らせ',
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 16,
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // -------- Handlers --------
  void _enterChangeMode() {
    setState(() {
      _changingPlan = true;
      _pendingPlan = _selectedPlan;
    });
  }

  void _cancelChangeMode() {
    setState(() {
      _changingPlan = false;
      _pendingPlan = null;
    });
  }

  void _onPlanChanged(String v) {
    if (!_changingPlan) return;
    setState(() => _pendingPlan = v);
  }

  static Future<void> showTipriInfoDialog(BuildContext context) async {
    // 表示する画像（あなたのアセットパスに合わせて変更）
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 480;
    List<String> assets = [];
    if (!isNarrow) {
      assets = <String>[
        'assets/pdf/PC_1.jpg',
        'assets/pdf/PC_2.jpg',
        'assets/pdf/PC_3.jpg',
        'assets/pdf/PC_4.jpg',
        'assets/pdf/PC_5.jpg',
        'assets/pdf/PC_6.jpg',
      ];
    } else {
      assets = <String>[
        'assets/pdf/1.jpg',
        'assets/pdf/2.jpg',
        'assets/pdf/3.jpg',
        'assets/pdf/4.jpg',
        'assets/pdf/5.jpg',
        'assets/pdf/6.jpg',
        'assets/pdf/7.jpg',
      ];
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final maxWidth = size.width < 480
            ? size.width
            : 560.0; // スマホは画面幅、タブレット/PCは最大560
        final height = size.height * 0.82; // 画面高の8割

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: height,
              ),
              child: SizedBox(
                width: maxWidth,
                height: height,
                child: Column(
                  children: [
                    // ヘッダ
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                      child: Row(
                        children: [
                          const Text(
                            'チップリについて',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '閉じる',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.black87),

                    // 本体ビューア
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ImagesScroller(assets: assets, borderRadius: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openStoreDeductionSheet(
    DocumentReference<Map<String, dynamic>> tenantRef,
    Map<String, dynamic> data,
  ) async {
    // pending の表示用
    final pending =
        (data['storeDeductionPending'] as Map?)?.cast<String, dynamic>() ??
        const {};
    DateTime? eff;
    final ts = pending['effectiveFrom'];
    if (ts is Timestamp) eff = ts.toDate();
    eff ??= _firstDayOfNextMonth();

    // 既存の controller / focusNode をそのまま使う
    _storePercentFocus.requestFocus();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, localSetState) {
                bool saving = _savingStoreCut; // 初期値は親の状態を参照

                Future<void> save() async {
                  if (saving) return;
                  localSetState(() => saving = true);
                  try {
                    await _saveStoreCut(tenantRef);
                    if (mounted) Navigator.pop(ctx); // 閉じる
                  } finally {
                    localSetState(() => saving = false);
                  }
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                      Row(
                        children: [
                          const Text(
                            'スタッフから差し引く金額',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '閉じる',
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 注意表示
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.schedule,
                              size: 18,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'この変更は「今月分の明細」から自動適用されます。',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontFamily: "LINEseed",
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 入力欄
                      TextField(
                        key: const ValueKey('storePercentField'),
                        focusNode: _storePercentFocus,
                        controller: _storePercentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'スタッフから店舗が差し引く金額（％）',
                          hintText: '例: 10 または 12.5',
                          suffixText: '%',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onSubmitted: (_) => save(),
                      ),

                      const SizedBox(height: 7),

                      // 現在値
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: tenantRef.snapshots(),
                        builder: (context, snap2) {
                          final d2 = snap2.data?.data() ?? {};
                          final active = (d2['storeDeduction'] as Map?) ?? {};
                          final activePercent = (active['percent'] ?? 0)
                              .toString();
                          return Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '現在：$activePercent%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: "LINEseed",
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // アクション
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: saving ? null : save,
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('保存'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Color(0xFFFCC400),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                side: BorderSide(color: Colors.black, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // 管理者を招待（メール）
  Future<void> _inviteAdminDialog(
    DocumentReference<Map<String, dynamic>> tenantRef,
  ) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('管理者を招待', style: TextStyle(color: Colors.black87)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'メールアドレス'),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
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
              side: BorderSide(color: Colors.black, width: 3),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('招待'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _functions.httpsCallable('inviteTenantAdmin').call({
          'tenantId': widget.tenantId,
          'email': ctrl.text.trim(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '招待を送信しました',
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
              '招待に失敗: $e',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    }
  }

  // ====== 追加：通知詳細シート + 個別既読化 ======
  Future<void> _openAlertDetailAndMarkRead({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
  }) async {
    // 個別既読化
    try {
      await docRef.set({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;

    final msg = (data['message'] as String?)?.trim() ?? 'お知らせ';
    final title = (data['title'] as String?)?.trim() ?? 'タイトル';
    final details = (data['details'] as String?)?.trim(); // 任意の詳細が入る想定
    final payload = (data['payload'] as Map?)
        ?.cast<String, dynamic>(); // 追加情報がある場合
    final createdAt = data['createdAt'];
    String when = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate().toLocal();
      when =
          '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final maxW = size.width < 480 ? size.width : 560.0;
        final maxH = size.height * 0.8;

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications, color: Colors.black87),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'LINEseed',
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: Colors.black87),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        msg,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'LINEseed',
                        ),
                      ),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          when,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (details != null && details.isNotEmpty) ...[
                              Text(
                                details,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (payload != null && payload.isNotEmpty) ...[
                              const Text(
                                '詳細情報',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: SelectableText(
                                  _prettyJson(payload),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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

  Future<void> logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      // 画面スタックを全消しして /login (BootGate) へ
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ログアウトに失敗: $e',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
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

    setState(() => _updatingPlan = true);
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
      if (mounted) setState(() => _updatingPlan = false);
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

      // もし階層に入っているなら例：
      // final subStatus = (data?['subscription'] as Map<String, dynamic>?)?['status'] as String?;
      // final isActive = (subStatus?.trim().toLowerCase() == 'active');

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

  Future<void> _openAlertsPanel() async {
    final tid = widget.tenantId;

    // 1) ownerUid を tenantIndex から取得（招待テナント対応）
    String? ownerUid;
    try {
      final idx = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tid)
          .get();
      ownerUid = idx.data()?['uid'] as String?;
    } catch (_) {}
    // 自分オーナーのケースのフォールバック
    ownerUid ??= FirebaseAuth.instance.currentUser?.uid;

    if (ownerUid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '通知の取得に失敗しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    // 2) alerts を新しい順で取得
    final col = FirebaseFirestore.instance
        .collection(ownerUid)
        .doc(tid)
        .collection('alerts');

    final qs = await col.orderBy('createdAt', descending: true).limit(50).get();

    final alerts = qs.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    // 3) 未読を既読に（表示するタイミングで一括マーク）
    if (alerts.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in qs.docs) {
        final read = (d.data()['read'] as bool?) ?? false;
        if (!read) {
          batch.set(d.reference, {
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      await batch.commit();
    }

    if (!mounted) return;

    // 一覧 BottomSheet（「すべて既読」／タップで詳細）
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      'お知らせ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final qs = await col
                            .where('read', isEqualTo: false)
                            .get();
                        final batch = FirebaseFirestore.instance.batch();
                        for (final d in qs.docs) {
                          batch.set(d.reference, {
                            'read': true,
                            'readAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        }
                        await batch.commit();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _openAlertsPanel();
                      },
                      icon: const Icon(Icons.done_all),
                      label: const Text('すべて既読'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: col
                        .orderBy('createdAt', descending: true)
                        .limit(100)
                        .snapshots(),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('読み込みエラー: ${snap.error}'));
                      }
                      final docs = snap.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('新しいお知らせはありません'),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: docs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.black87),
                        itemBuilder: (ctx, i) {
                          final d = docs[i];
                          final m = d.data();
                          final msg =
                              (m['message'] as String?)?.trim() ?? 'お知らせ';
                          final read = (m['read'] as bool?) ?? false;
                          final createdAt = m['createdAt'];
                          String when = '';
                          if (createdAt is Timestamp) {
                            final dt = createdAt.toDate().toLocal();
                            when =
                                '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
                                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          }
                          return ListTile(
                            leading: Icon(
                              read
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: read ? Colors.black45 : Colors.orange,
                            ),
                            title: Text(
                              msg,
                              style: TextStyle(
                                fontFamily: 'LINEseed',
                                fontWeight: read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: when.isEmpty ? null : Text(when),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 6,
                            ),
                            onTap: () => _openAlertDetailAndMarkRead(
                              docRef: d.reference,
                              data: m,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _prettyJson(Map<String, dynamic> m) {
    try {
      final entries = m.entries.map((e) => '• ${e.key}: ${e.value}').join('\n');
      return entries.isEmpty ? '(なし)' : entries;
    } catch (_) {
      return m.toString();
    }
  }

  // -------- Build --------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_connected == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 黒基調のローカルテーマ（あなたの元のまま）
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
                        // ===== ここから下はあなたの UI をそのまま（参照だけ tenantRef/publicThankRef を使う） =====
                        ownerIsMe
                            ? Column(
                                children: [
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
                                  const SizedBox(height: 10),
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
                                                            vertical: 7,
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
                                              _buildNotificationsAction(),
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
                                                      vertical: 7,
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
                            : const SizedBox(height: 4),
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
                        const SizedBox(height: 8),

                        CardShell(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    PlanChip(label: '現在', dark: true),
                                    Text(
                                      'プラン $currentPlan',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),

                                    // 説明ボタン（狭い時は次行へ自動回避）
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            showTipriInfoDialog(context),
                                        icon: const Icon(Icons.info_outline),
                                        label: const Text(
                                          'チップリについて',
                                          style: TextStyle(
                                            color: Color(0xFFFCC400),
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.black87,
                                        ),
                                      ),
                                    ),

                                    if (periodEnd != null)
                                      Text(
                                        '${periodEndBool ? '終了予定' : '次回の請求'}: '
                                        '${periodEnd.year}/${periodEnd.month.toString().padLeft(2, '0')}/${periodEnd.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                if (trialStatus == "trialing")
                                  TrialProgressBar(
                                    trialStart: trialStart,
                                    trialEnd: trialEnd!,
                                    totalDays: 30,
                                    onTap: () {},
                                  ),
                                if (trialStatus == "none")
                                  Text("トライアル期間は終了しました"),

                                const SizedBox(height: 12),

                                Builder(
                                  builder: (_) {
                                    final effectivePickerValue = _changingPlan
                                        ? (_pendingPlan ?? currentPlan)
                                        : currentPlan;
                                    return Stack(
                                      children: [
                                        AbsorbPointer(
                                          absorbing: !_changingPlan,
                                          child: Opacity(
                                            opacity: _changingPlan ? 1.0 : 0.8,
                                            child: PlanPicker(
                                              selected: effectivePickerValue,
                                              onChanged: _onPlanChanged,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                const SizedBox(height: 16),

                                if (currentPlan == "B") ...[
                                  buildBPerksSection(
                                    tenantRef: FirebaseFirestore.instance
                                        .collection(uid)
                                        .doc(widget.tenantId),
                                    thanksRef: FirebaseFirestore.instance
                                        .collection('publicThanks')
                                        .doc(widget.tenantId),
                                    lineUrlCtrl: _lineUrlCtrl,
                                    primaryBtnStyle: FilledButton.styleFrom(
                                      backgroundColor: Color(0xFFFCC400),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: Colors.black,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ],

                                if (currentPlan == 'C') ...[
                                  buildCPerksSection(
                                    tenantRef: tenantRef,
                                    lineUrlCtrl: _lineUrlCtrl,
                                    reviewUrlCtrl: _reviewUrlCtrl,
                                    uploadingPhoto: _uploadingPhoto,
                                    uploadingVideo: _uploadingVideo,
                                    savingExtras: _savingExtras,
                                    thanksPhotoPreviewBytes:
                                        _thanksPhotoPreviewBytes,
                                    thanksPhotoUrlLocal: _thanksPhotoUrl,
                                    thanksVideoUrlLocal: _thanksVideoUrl,
                                    onSaveExtras: () => _saveExtras(tenantRef),
                                    onPreviewVideo: showVideoPreview,
                                    primaryBtnStyle: primaryBtnStyle,
                                    thanksRef: publicThankRef,
                                  ),
                                ],

                                const SizedBox(height: 16),

                                if (!_changingPlan) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          style: primaryBtnStyle,
                                          onPressed: widget.ownerId! != uid
                                              ? () {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'オーナーのみ変更可能です',
                                                        style: TextStyle(
                                                          fontFamily:
                                                              'LINEseed',
                                                        ),
                                                      ),
                                                      backgroundColor: Color(
                                                        0xFFFCC400,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              : _updatingPlan
                                              ? null
                                              : _enterChangeMode,
                                          icon: const Icon(Icons.tune),
                                          label: currentPlan == ""
                                              ? const Text('サブスクのプランを追加')
                                              : periodEndBool
                                              ? const Text('サブスクのプランを更新')
                                              : const Text('サブスクのプランを変更'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          style: primaryBtnStyle,
                                          onPressed:
                                              (_updatingPlan ||
                                                  (_pendingPlan == null) ||
                                                  (_pendingPlan == currentPlan))
                                              ? null
                                              : () => _changePlan(
                                                  tenantRef,
                                                  _pendingPlan!,
                                                ),
                                          icon: _updatingPlan
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(Icons.check_circle),
                                          label: Text(
                                            (_pendingPlan == currentPlan)
                                                ? '変更なし'
                                                : 'このプランに変更',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        style: outlinedBtnStyle,
                                        onPressed: _updatingPlan
                                            ? null
                                            : _cancelChangeMode,
                                        icon: const Icon(Icons.close),
                                        label: const Text('やめる'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        if (_isCompactWidth(context)) ...[
                          // スマホ・タブレット：ボタンだけ出して、押下でポップアップ
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

                          CardShell(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'スタッフにチップを満額渡しますか？',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontFamily: "LINEseed",
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // 現在の設定だけ軽く見せる
                                  StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>
                                  >(
                                    stream: tenantRef.snapshots(),
                                    builder: (context, snap2) {
                                      final d2 = snap2.data?.data() ?? {};
                                      final active =
                                          (d2['storeDeduction'] as Map?) ?? {};
                                      final activePercent =
                                          (active['percent'] ?? 0).toString();
                                      return Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '現在：$activePercent%',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: () => _openStoreDeductionSheet(
                                        tenantRef,
                                        data,
                                      ),
                                      icon: const Icon(Icons.tune),
                                      label: const Text('設定を開く'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Color(0xFFFCC400),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.black,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
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
                          CardShell(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'スタッフにチップを満額渡しますか？',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontFamily: "LINEseed",
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const SizedBox(height: 8),

                                  Builder(
                                    builder: (context) {
                                      final pending =
                                          (data['storeDeductionPending']
                                                  as Map?)
                                              ?.cast<String, dynamic>() ??
                                          const {};
                                      DateTime? eff;
                                      final ts = pending['effectiveFrom'];
                                      if (ts is Timestamp) eff = ts.toDate();
                                      eff ??= _firstDayOfNextMonth();

                                      return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(
                                            0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.black12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.schedule,
                                              size: 18,
                                              color: Colors.orange,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'この変更は「今月分の明細」から自動適用されます。',
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontFamily: "LINEseed",
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const ValueKey(
                                            'storePercentField',
                                          ),
                                          focusNode: _storePercentFocus,
                                          controller: _storePercentCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'スタッフから店舗が差し引く金額（％）',
                                            hintText: '例: 10 または 12.5',
                                            suffixText: '%',
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'[0-9.]'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),

                                  StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>
                                  >(
                                    stream: tenantRef.snapshots(),
                                    builder: (context, snap2) {
                                      final d2 = snap2.data?.data() ?? {};
                                      final active =
                                          (d2['storeDeduction'] as Map?) ?? {};

                                      final activePercent =
                                          (active['percent'] ?? 0).toString();

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.info_outline,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '現在：$activePercent%',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: "LINEseed",
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 12),
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: _savingStoreCut
                                          ? null
                                          : () => _saveStoreCut(tenantRef),
                                      icon: _savingStoreCut
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.save),
                                      label: const Text('店舗が差し引く金額割合を保存'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Color(0xFFFCC400),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.black,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

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

                        CardShell(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                StreamBuilder<QuerySnapshot>(
                                  stream: tenantRef
                                      .collection('invites')
                                      .where('status', isEqualTo: 'pending')
                                      .snapshots(),
                                  builder: (context, invSnap) {
                                    final invites =
                                        invSnap.data?.docs ?? const [];
                                    if (invSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: LinearProgressIndicator(),
                                      );
                                    }
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '承認待ちの招待',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                            fontFamily: "LINEseed",
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (invites.isEmpty)
                                          const Text(
                                            '承認待ちはありません',
                                            style: TextStyle(
                                              color: Colors.black54,
                                              fontFamily: "LINEseed",
                                            ),
                                          )
                                        else
                                          ...invites.map((d) {
                                            final m =
                                                d.data()
                                                    as Map<String, dynamic>;
                                            final email =
                                                (m['emailLower'] as String?) ??
                                                '';
                                            final expTs = m['expiresAt'];
                                            final exp = expTs is Timestamp
                                                ? expTs.toDate()
                                                : null;
                                            return ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.pending_actions,
                                                color: Colors.orange,
                                              ),
                                              title: Text(
                                                email,
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              subtitle: exp == null
                                                  ? null
                                                  : Text(
                                                      '有効期限: ${exp.year}/${exp.month.toString().padLeft(2, '0')}/${exp.day.toString().padLeft(2, '0')}',
                                                      style: const TextStyle(
                                                        color: Colors.black54,
                                                        fontFamily: "LINEseed",
                                                      ),
                                                    ),
                                              trailing: Wrap(
                                                spacing: 8,
                                                children: [
                                                  TextButton.icon(
                                                    onPressed: () async {
                                                      await _functions
                                                          .httpsCallable(
                                                            'inviteTenantAdmin',
                                                          )
                                                          .call({
                                                            'tenantId': tid,
                                                            'email': email,
                                                          });
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '招待メールを再送しました',
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'LINEseed',
                                                            ),
                                                          ),
                                                          backgroundColor:
                                                              Color(0xFFFCC400),
                                                        ),
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.send,
                                                    ),
                                                    label: const Text('再送'),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed: () async {
                                                      await _functions
                                                          .httpsCallable(
                                                            'cancelTenantAdminInvite',
                                                          )
                                                          .call({
                                                            'tenantId': tid,
                                                            'inviteId': d.id,
                                                          });
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '招待を取り消しました',
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'LINEseed',
                                                            ),
                                                          ),
                                                          backgroundColor:
                                                              Color(0xFFFCC400),
                                                        ),
                                                      );
                                                    },
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                    label: const Text('取消'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        const Divider(
                                          height: 24,
                                          color: Colors.black87,
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                StreamBuilder<QuerySnapshot>(
                                  stream: tenantRef
                                      .collection('members')
                                      .snapshots(),
                                  builder: (context, memSnap) {
                                    final members = memSnap.data?.docs ?? [];
                                    final dataMap = data;

                                    if (memSnap.hasData && members.isNotEmpty) {
                                      return AdminList(
                                        entries: members.map((m) {
                                          final md =
                                              m.data() as Map<String, dynamic>;
                                          return AdminEntry(
                                            uid: m.id,
                                            email:
                                                (md['email'] as String?) ?? '',
                                            name:
                                                (md['displayName']
                                                    as String?) ??
                                                '',
                                          );
                                        }).toList(),
                                        onRemove: (uidToRemove) {
                                          // ✅ ここでオーナーのみ削除を許可
                                          if (widget.ownerId !=
                                              FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '削除できるのはオーナーのみです',
                                                  style: TextStyle(
                                                    fontFamily: 'LINEseed',
                                                  ),
                                                ),
                                                backgroundColor: Color(
                                                  0xFFFCC400,
                                                ),
                                              ),
                                            );
                                            return;
                                          }

                                          _removeAdmin(tenantRef, uidToRemove);
                                        },
                                      );
                                    }

                                    final uids =
                                        (dataMap['memberUids'] as List?)
                                            ?.cast<String>() ??
                                        const <String>[];
                                    if (uids.isEmpty) {
                                      return const ListTile(
                                        title: Text(
                                          '管理者がいません',
                                          style: TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '右上の追加ボタンから招待できます',
                                          style: TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                      );
                                    }

                                    return AdminList(
                                      entries: uids
                                          .map(
                                            (u) => AdminEntry(
                                              uid: u,
                                              email: '',
                                              name: '',
                                            ),
                                          )
                                          .toList(),
                                      onRemove: (uidToRemove) {
                                        if (widget.ownerId !=
                                            FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '削除できるのはオーナーのみです',
                                                style: TextStyle(
                                                  fontFamily: 'LINEseed',
                                                ),
                                              ),
                                              backgroundColor: Color(
                                                0xFFFCC400,
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        _removeAdmin(tenantRef, uidToRemove);
                                      },
                                    );
                                  },
                                ),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _inviteAdminDialog(tenantRef),
                                    icon: const Icon(Icons.person_add_alt_1),
                                    label: const Text('管理者を追加（メール招待）'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 200,
                          margin: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Color(0xFFFCC400),
                            border: Border.all(width: 3, color: Colors.black),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: logout,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 20,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: Colors.black,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'ログアウト',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: "LINEseed",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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

                                  // 情報ボタン（色は既存を踏襲：ラベル #FCC400、前景は黒）
                                  SizedBox(
                                    width: double.infinity,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          showTipriInfoDialog(context),

                                      label: const Text('チップリについて'),
                                      style: TextButton.styleFrom(
                                        side: BorderSide(
                                          width: 3,
                                          color: Colors.black,
                                        ),
                                        foregroundColor: Colors.black87,
                                        backgroundColor: Color(0xFFFCC400),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: const BorderSide(
                                            color: Color(
                                              0xFFFCC400,
                                            ), // 枠線だけアクセント
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    width: 250,
                    margin: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFFFCC400),
                      border: Border.all(width: 3, color: Colors.black),
                      borderRadius: BorderRadius.circular(999),
                    ),

                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: logout,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 20,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout, color: Colors.black87, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'ログアウト',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontFamily: "LINEseed",
                              ),
                            ),
                          ],
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

// // --- 小物 ---
// class _InfoLine extends StatelessWidget {
//   final String text;
//   const _InfoLine(this.text);
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: const [
//         Icon(Icons.info_outline, size: 16, color: Colors.black54),
//         SizedBox(width: 6),
//         Expanded(
//           child: Text('', style: TextStyle(color: Colors.black54)),
//         ),
//       ],
//     ).copyWithText(text);
//   }
// }

// extension on Row {
//   Row copyWithText(String t) {
//     final children = List<Widget>.from(this.children);
//     children[2] = Expanded(
//       child: Text(t, style: const TextStyle(color: Colors.black54)),
//     );
//     return Row(children: children);
//   }
// }
