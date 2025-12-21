// lib/tenant/store_detail_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/tenant/method/logout.dart';
import 'package:yourpay/tenant/newTenant/tenant_switch_bar_drawer.dart';
import 'package:yourpay/tenant/store_detail/tabs/srore_home_tab.dart';
import 'package:yourpay/tenant/store_detail/tabs/store_qr_tab.dart';
import 'package:yourpay/tenant/store_detail/tabs/store_setting_tab.dart';
import 'package:yourpay/tenant/store_detail/tabs/store_staff_tab.dart';
import 'package:yourpay/tenant/newTenant/tenant_switch_bar.dart';
import 'package:yourpay/tenant/newTenant/onboardingSheet.dart';
import 'package:yourpay/tenant/widget/store_detail/alert_dialog.dart';
import 'package:yourpay/tenant/widget/store_detail/initialfee_cashback.dart';

class StoreDetailScreen extends StatefulWidget {
  const StoreDetailScreen({super.key});
  @override
  State<StoreDetailScreen> createState() => _StoreDetailSScreenState();
}

class _StoreDetailSScreenState extends State<StoreDetailScreen> {
  // ---- global guards (インスタンスを跨いで1回だけ動かすためのフラグ) ----
  static bool _globalOnboardingOpen = false;
  static bool _globalStripeEventHandled = false;

  // ---- state ----
  final amountCtrl = TextEditingController(text: '1000');

  bool loading = false;
  int _currentIndex = 0;

  // 管理者判定
  static const Set<String> _kAdminEmails = {
    'appfromkomeda@gmail.com',
    'tiprilogin@gmail.com',
  };
  bool _isAdmin = false;
  final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  String? tenantId;
  String? tenantName;
  String? ownerUid;
  bool invited = false;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _empNameCtrl = TextEditingController();
  final _empEmailCtrl = TextEditingController();

  bool _onboardingOpen = false; // インスタンス内ガード

  bool _argsApplied = false; // ルート引数適用済み
  bool _tenantInitialized = false; // 初回テナント確定済み
  bool _stripeHandled = false; // インスタンス内のStripeイベント処理済み

  // Stripeイベントの保留（初期化完了後に1回だけ処理）
  String? _pendingStripeEvt;
  String? _pendingStripeTenant;
  late User user;
  bool _initialFeePopupChecked = false; // このテナントで一度チェック済みか
  bool _showInitialFeePopup = false; // 実際に表示するかどうか

  bool _accountSetting = false;

  // 初期テナント解決用 Future（※毎buildで新規作成しない）
  Future<Map<String, String?>?>? _initialTenantFuture;

  Future<void> initialize() async {
    final doc = await FirebaseFirestore.instance
        .collection(ownerUid!) // ← コレクション名は合わせて
        .doc(tenantId)
        .get();

    final data = doc.data();
    print(tenantId);

    _accountSetting = data != null && data.containsKey('account_cashback');
    print(_accountSetting);
  }

  // ====== 追加：未読数ストリーム ======
  Stream<int>? _unreadCountStream(String ownerUid, String tenantId) {
    try {
      final q = FirebaseFirestore.instance
          .collection(ownerUid)
          .doc(tenantId)
          .collection('alerts')
          .where('read', isEqualTo: false);

      // スナップショットの length を count として返す（軽量用途）
      return q.snapshots().map((snap) => snap.docs.length);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAndMaybeShowInitialFeePopup() async {
    if (tenantId == null || ownerUid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(ownerUid!) // オーナーごとのコレクション
          .doc(tenantId!)
          .get();

      final data = doc.data();
      final initialFee = data?['initial_fee'] == true;

      if (!mounted) return;
      if (initialFee) {
        setState(() {
          _showInitialFeePopup = true;
        });
      }
    } catch (e) {
      // 失敗しても致命的ではないのでログだけにするなど
      debugPrint('initial_fee popup check failed: $e');
    }
  }

  Map<String, String> _queryFromHashAndSearch() {
    final u = Uri.base;
    final map = <String, String>{}..addAll(u.queryParameters);
    final frag = u.fragment; // 例: "/store?event=...&t=..."
    final qi = frag.indexOf('?');
    if (qi >= 0) {
      map.addAll(Uri.splitQueryString(frag.substring(qi + 1)));
    }
    return map;
  }

  // ---- theme (白黒) ----
  ThemeData _bwTheme(BuildContext context) {
    final base = Theme.of(context);
    const lineSeedFamily = 'LINEseed';

    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: Colors.black,
        secondary: Colors.black,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black87,
      ),
      dialogBackgroundColor: Colors.white,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      textTheme: base.textTheme.apply(
        bodyColor: Colors.black87,
        displayColor: Colors.black87,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: Colors.black87),
        hintStyle: const TextStyle(color: Colors.black54),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border(Colors.black12),
        enabledBorder: border(Colors.black12),
        focusedBorder: border(Colors.black),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedLabelStyle: TextStyle(
          fontFamily: lineSeedFamily,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: lineSeedFamily,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 初回だけ Future を生成（以降は使い回す）
    user = FirebaseAuth.instance.currentUser!;
    // if (!_tenantInitialized) {
    //   _initialTenantFuture = _resolveInitialTenant(user);
    // }
    _initialize();
  }

  Future<void> _initialize() async {
    user = FirebaseAuth.instance.currentUser!;
    if (!_tenantInitialized) {
      _initialTenantFuture = _resolveInitialTenant(user);
    }
    setState(() {
      tenantId;
    });
    ownerUid = user.uid;
    await _checkAdmin();
    await initialize();
  }

  // ★ 初期化完了前は setState しないで代入のみ。完了後に変化があれば setState。
  Future<void> _checkAdmin() async {
    final token = await user.getIdTokenResult(); // 強制リフレッシュしない
    final email = (user.email ?? '').toLowerCase();

    final newIsAdmin =
        (token.claims?['admin'] == true) || _kAdminEmails.contains(email);

    if (!_tenantInitialized) {
      _isAdmin = newIsAdmin;
      return;
    }
    if (mounted && _isAdmin != newIsAdmin) {
      setState(() => _isAdmin = newIsAdmin);
    }
  }

  // ---- 店舗作成ダイアログ（TenantSwitcherBar と同等の仕様）----
  Future<void> createTenantDialog() async {
    final nameCtrl = TextEditingController();
    final agentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45, // ほんの少し濃く
      useRootNavigator: true,
      builder: (_) => Theme(
        data: _bwTheme(context),
        child: WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            // ★★★ ここがポイント：黒く太い枠線 + 角丸
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: const BorderSide(color: Colors.black, width: 3), // ← 太い黒枠
            ),
            clipBehavior: Clip.antiAlias, // 角丸に沿ってクリップ
            elevation: 0, // 影は消して枠を主役に
            backgroundColor: const Color(0xFFF5F5F5),
            surfaceTintColor: Colors.transparent,

            // タイトル・本文はそのまま（強めたいなら太字済み）
            titleTextStyle: const TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.w700, // 少し強め
              fontFamily: 'LINEseed',
            ),
            contentTextStyle: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontFamily: 'LINEseed',
            ),

            // ここから下は元のまま（必要ならそのまま流用）
            title: const Text('新しい店舗を作成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black87),
                  decoration: const InputDecoration(
                    labelText: '店舗名',
                    hintText: '例）渋谷店',
                    labelStyle: TextStyle(color: Colors.black87),
                    hintStyle: TextStyle(color: Colors.black54),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.black26,
                        width: 1.2,
                      ), // ほんの少し太く
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.black87,
                        width: 1.6,
                      ), // フォーカス時も気持ち太く
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: agentCtrl,
                  style: const TextStyle(color: Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'キャンペーンコード',
                    hintText: '代理店の方からお聞きください',
                    labelStyle: TextStyle(color: Colors.black87),
                    hintStyle: TextStyle(color: Colors.black54),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black26, width: 1.2),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black87, width: 1.6),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black87, // 黒系で統一
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  '作成',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Color(0xFFFCC400), // 主ボタンは黒地に白文字
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(width: 3, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    // TextField 実体を拾う
    final name = nameCtrl.text.trim();
    final agentCode = agentCtrl.text.trim();
    if (name.isEmpty) return;
    // 代理店コードの事前確認
    bool shouldLinkAgency = false;
    if (agentCode.isEmpty) {
      final proceed = await _confirmProceedWithoutAgency(
        context,
        title: '代理店コードが未入力です',
        message: '代理店と未連携のまま店舗を作成してよろしいですか？\n代理店の方から連携されている場合は、必ず入力ください',
        proceedLabel: '未連携で作成',
      );
      if (!proceed) return;
    } else {
      final exists = await _agencyCodeExists(agentCode);
      if (!exists) {
        final proceed = await _confirmProceedWithoutAgency(
          context,
          title: '代理店コードが見つかりません',
          message: '入力されたコード「$agentCode」は有効ではない可能性があります。\n未連携のまま作成しますか？',
          proceedLabel: '未連携で作成',
        );
        print("a");
        if (!proceed) return;
      } else {
        shouldLinkAgency = true;
      }
    }
    print("a");

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ログインが必要です', style: TextStyle(fontFamily: 'LINEseed')),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    // draft で作成 + tenantIndex へ登録
    final col = FirebaseFirestore.instance.collection(u.uid);
    final newRef = col.doc();
    final tenantIdNew = newRef.id;
    await FirebaseFirestore.instance
        .collection('tenantIndex')
        .doc(tenantIdNew)
        .set({'uid': u.uid, 'name': name});
    await newRef.set({
      'name': name,
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'agency': {'code': agentCode, 'linked': false},
      'members': [u.uid],
      'createdBy': {'uid': u.uid, 'email': u.email},
    }, SetOptions(merge: true));

    // 代理店リンク
    if (shouldLinkAgency) {
      await _tryLinkAgencyByCode(
        code: agentCode,
        ownerUid: u.uid,
        tenantRef: newRef,
        tenantName: name,
        scaffoldContext: context,
      );
    }

    // 画面状態更新
    if (!mounted) return;
    setState(() {
      tenantId = tenantIdNew;
      tenantName = name;
      ownerUid = u.uid;
      invited = false;
    });

    // オンボーディング開始（v2）
    await startOnboarding(tenantIdNew, name);
  }

  Future<bool> _agencyCodeExists(String code) async {
    final qs = await FirebaseFirestore.instance
        .collection('agencies')
        .where('code', isEqualTo: code)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    return qs.docs.isNotEmpty;
  }

  Future<bool> _confirmProceedWithoutAgency(
    BuildContext context, {
    required String title,
    required String message,
    String proceedLabel = '続行',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(proceedLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _tryLinkAgencyByCode({
    required String code,
    required String ownerUid,
    required DocumentReference<Map<String, dynamic>> tenantRef,
    required String tenantName,
    required BuildContext scaffoldContext,
  }) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('agencies')
          .where('code', isEqualTo: code)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (qs.docs.isEmpty) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text(
              '代理店コードが見つかりませんでした',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
        return;
      }
      final agent = qs.docs.first;
      final agentId = agent.id;
      final commission =
          (agent.data()['commissionPercent'] as num?)?.toInt() ?? 0;

      await tenantRef.set({
        'agency': {
          'code': code,
          'agentId': agentId,
          'commissionPercent': commission,
          'linked': true,
          'linkedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('agencies')
          .doc(agentId)
          .collection('contracts')
          .doc(tenantRef.id)
          .set({
            'tenantId': tenantRef.id,
            'tenantName': tenantName,
            'ownerUid': ownerUid,
            'contractedAt': FieldValue.serverTimestamp(),
            'status': 'draft',
          }, SetOptions(merge: true));
    } catch (e) {
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text(
            '代理店リンクに失敗しました: $e',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    }
  }

  Future<void> startOnboarding(String tenantId, String tenantName) async {
    if (_onboardingOpen || _globalOnboardingOpen) return;
    _onboardingOpen = true;
    _globalOnboardingOpen = true;

    try {
      final size = MediaQuery.of(context).size;
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useRootNavigator: true,
        useSafeArea: true,
        barrierColor: Colors.black38,
        backgroundColor: Colors.white,
        constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) {
          return Theme(
            data: _bwTheme(context),
            child: OnboardingSheet(
              tenantId: tenantId,
              tenantName: tenantName,
              functions: functions,
            ),
          );
        },
      );
    } finally {
      _onboardingOpen = false;
      _globalOnboardingOpen = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsApplied) {
      _argsApplied = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final id = args['tenantId'] as String?;
        final nameArg = args['tenantName'] as String?;
        final oUid = args['ownerUid'] as String?; // ← 追加（あれば優先）

        if (id != null && id.isNotEmpty) {
          tenantId = id;
          tenantName = nameArg;
          ownerUid = oUid ?? ownerUid;
          _tenantInitialized = true;

          if (_pendingStripeEvt != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleStripeEventNow();
            });
          }
        }
      }
    }

    // Stripe 戻りURLを確認（初期化前は保留、後で1回だけ処理）
    if (!_stripeHandled && !_globalStripeEventHandled) {
      final q = _queryFromHashAndSearch();
      final evt = q['event'];
      final t = q['t'] ?? q['tenantId'];
      final hasStripeEvent =
          (evt == 'initial_fee_paid' || evt == 'initial_fee_canceled');

      if (hasStripeEvent) {
        _stripeHandled = true;
        _globalStripeEventHandled = true;
        _pendingStripeEvt = evt;
        _pendingStripeTenant = t;

        if (_tenantInitialized) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleStripeEventNow(),
          );
        }
      }
    }
  }

  // ---- 初回テナント推定（Future内で完結。setStateはしない）----
  Future<Map<String, String?>?> _resolveInitialTenant(User user) async {
    if (tenantId != null) return {'id': tenantId, 'name': tenantName};
    try {
      final token = await user.getIdTokenResult(true);
      final idFromClaims = token.claims?['tenantId'] as String?;
      if (idFromClaims != null) {
        String? name;
        try {
          final doc = await FirebaseFirestore.instance
              .collection(user.uid)
              .doc(idFromClaims)
              .get();
          if (doc.exists) name = (doc.data()?['name'] as String?);
          final data = doc.data();

          _accountSetting =
              data != null && data.containsKey('account_cashback');
        } catch (_) {}

        return {'id': idFromClaims, 'name': name};
      }
    } catch (_) {}
    try {
      final col = FirebaseFirestore.instance.collection(user.uid);
      final qs1 = await col
          .where('members', arrayContains: user.uid)
          .limit(1)
          .get();
      if (qs1.docs.isNotEmpty) {
        final d = qs1.docs.first;
        final data = d.data();

        _accountSetting = data.containsKey('account_cashback');
        return {'id': d.id, 'name': (d.data()['name'] as String?)};
      }
      final qs2 = await col
          .where('createdBy.uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (qs2.docs.isNotEmpty) {
        final d = qs2.docs.first;
        final data = d.data();

        _accountSetting = data.containsKey('account_cashback');
        return {'id': d.id, 'name': (d.data()['name'] as String?)};
      }
    } catch (_) {}
    return null;
  }

  // ---- Stripeイベントを“今”実行（初期化後に1回だけ）----
  Future<void> _handleStripeEventNow() async {
    final evt = _pendingStripeEvt;
    final t = _pendingStripeTenant;
    _pendingStripeEvt = null;
    _pendingStripeTenant = null;

    if (t != null && t.isNotEmpty) {
      if (mounted) {
        setState(() => tenantId = t);
      } else {
        tenantId = t;
      }
    }
    if (evt == 'initial_fee_paid' && tenantId != null && mounted) {
      await startOnboarding(tenantId!, tenantName ?? '');
    }
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    _empNameCtrl.dispose();
    _empEmailCtrl.dispose();
    super.dispose();
  }

  // ====== 追加：AppBar の通知アイコン（未読バッジ付き） ======
  Widget _buildNotificationsAction() {
    if (tenantId == null || ownerUid == null) {
      return IconButton(
        onPressed: null,
        icon: const Icon(Icons.notifications_outlined),
      );
    }
    return StreamBuilder<int>(
      stream: _unreadCountStream(ownerUid!, tenantId!),
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            TenantAlertsButton(tenantId: tenantId!),
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

  @override
  Widget build(BuildContext context) {
    // ★ ここで固定ユーザーを取得（以降は auth の stream で再ビルドしない）
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Theme(
        data: _bwTheme(context),
        child: const Scaffold(body: Center(child: Text('ログインが必要です'))),
      );
    }

    // まだ初期テナント未確定なら、一度だけ作った Future で描画
    if (!_tenantInitialized) {
      return Theme(
        data: _bwTheme(context),
        child: FutureBuilder<Map<String, String?>?>(
          future: _initialTenantFuture,
          builder: (context, tSnap) {
            if (tSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final resolved = tSnap.data;
            _tenantInitialized = true;
            if (resolved != null) {
              tenantId = resolved['id'];
              tenantName = resolved['name'];
            }

            // 初期化完了後、保留中のStripeイベントを“1回だけ”適用
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _handleStripeEventNow(),
            );

            return _buildScaffold(context, user);
          },
        ),
      );
    }

    // 初期化済みなら通常描画（FutureBuilderを通さない）
    return Theme(data: _bwTheme(context), child: _buildScaffold(context, user));
  }

  // ---- Scaffoldの本体（安定化のため分離）----
  Widget _buildScaffold(BuildContext context, User user) {
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 480;

    final hasTenant = tenantId != null;
    const _downShift = 10.0;
    if (hasTenant && !_initialFeePopupChecked) {
      _initialFeePopupChecked = true;
      // build 中に setState しないよう、microtask で後回し
      Future.microtask(_loadAndMaybeShowInitialFeePopup);
    }

    return SafeArea(
      child: Scaffold(
        backgroundColor: _currentIndex == 3
            ? const Color.fromARGB(255, 236, 236, 236) // 設定タブのとき：今のグレー
            : Colors.white,
        key: _scaffoldKey,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          automaticallyImplyLeading: false,
          elevation: 0,
          // ずらした分だけ高さを少し増やす（はみ出し防止）
          toolbarHeight: 53 + _downShift,
          titleSpacing: 2,
          surfaceTintColor: Colors.transparent,

          // ▼ title をまとめて下にずらす
          title: Padding(
            padding: const EdgeInsets.only(top: _downShift, bottom: _downShift),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14.0, top: 6),
                  child: Image.asset("assets/posters/tipri.png", height: 32),
                ),
                if (_isAdmin) const SizedBox(width: 8),
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/admin'),
                    icon: const Icon(Icons.admin_panel_settings, size: 18),
                    label: const Text(
                      '管理者画面',
                      style: TextStyle(fontFamily: 'LINEseed'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black26),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // ▼ actions 側もまとめて下にずらす
          actions: [
            Padding(
              padding: EdgeInsets.only(top: _downShift, right: 5),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.of(context).size.width * 0.7)
                      .clamp(280.0, 560.0)
                      .toDouble(),
                ),
                child: MediaQuery.of(context).size.width < 480
                    ? const SizedBox.shrink()
                    : TenantSwitcherBar(
                        currentTenantId: tenantId,
                        currentTenantName: tenantName,
                        compact: false,
                        onChangedEx: (id, name, oUid, isInvited) {
                          if (id == tenantId && oUid == ownerUid) return;
                          setState(() {
                            tenantId = id;
                            tenantName = name;
                            ownerUid = oUid;
                            invited = isInvited;
                            _initialFeePopupChecked = false;
                            _showInitialFeePopup = false;
                          });
                        },
                      ),
              ),
            ),
            if (MediaQuery.of(context).size.width < 480)
              Padding(
                padding: EdgeInsets.only(top: _downShift, right: 10.0),
                child: IconButton(
                  tooltip: '店舗を切り替え',
                  icon: const Icon(Icons.menu, size: 32),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(top: _downShift),
                child: _buildNotificationsAction(),
              ),
          ],

          bottom: const PreferredSize(
            preferredSize: Size.zero,
            child: SizedBox.shrink(),
          ),
        ),
        endDrawer: isNarrow
            ? TenantSwitchDrawer(
                currentTenantId: tenantId,
                currentTenantName: tenantName,

                onChangedEx: (id, name, oUid, isInvited) {
                  setState(() {
                    tenantId = id;
                    tenantName = name;
                    ownerUid = oUid;
                    invited = isInvited;
                    _initialFeePopupChecked = false;
                    _showInitialFeePopup = false;
                  });
                },
                onCreateTenant: createTenantDialog,
                onOpenOnboarding: (tid, name, owner) =>
                    startOnboarding(tid, name ?? ''),
              )
            : null,
        body: Stack(
          children: [
            hasTenant
                ? IndexedStack(
                    index: _currentIndex,
                    children: [
                      StoreHomeTab(
                        tenantId: tenantId!,
                        tenantName: tenantName,
                        ownerId: ownerUid!,
                      ),
                      StoreQrTab(
                        tenantId: tenantId!,
                        tenantName: tenantName,
                        ownerId: ownerUid!,
                      ),
                      StoreStaffTab(tenantId: tenantId!, ownerId: ownerUid!),
                      StoreSettingsTab(tenantId: tenantId!, ownerId: ownerUid!),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Center(
                        child: Text(
                          '店舗が見つかりませんでした\n右上のメニュー内「店舗の作成」から始めよう',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LogoutButton(),
                    ],
                  ),

            // ★ 初期費用ポップアップ（初回 & initial_fee=true のときだけ）
            if (hasTenant && _showInitialFeePopup && !_accountSetting)
              Positioned(
                left: 16,
                right: 16,
                bottom: 88, // BottomNavigationBar の少し上あたり
                child: InitialFeeCashbackPopup(
                  onTap: () {
                    // 例: 設定タブへ飛ばして閉じる
                    setState(() {
                      _currentIndex = 3; // 「設定」タブ
                      _showInitialFeePopup = false;
                    });
                  },
                  onClose: () {
                    setState(() {
                      _showInitialFeePopup = false;
                    });
                  },
                ),
              ),
          ],
        ),

        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.black54,
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
            BottomNavigationBarItem(icon: Icon(Icons.qr_code_2), label: '印刷'),
            BottomNavigationBarItem(icon: Icon(Icons.group), label: 'スタッフ'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
          ],
        ),
      ),
    );
  }
}
