import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yourpay/tenant/method/image_scrol.dart';
import 'package:yourpay/tenant/widget/store_staff/add_staff_dialog.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_detail.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_entry.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_reorder_dialog.dart';
import 'dart:async';

class StoreStaffTab extends StatefulWidget {
  final String tenantId;
  final String? ownerId;
  const StoreStaffTab({super.key, required this.tenantId, this.ownerId});

  @override
  State<StoreStaffTab> createState() => _StoreStaffTabState();
}

class _StoreStaffTabState extends State<StoreStaffTab> {
  // 取り込み用（グローバル/他店舗）
  String? _prefilledPhotoUrlFromGlobal;
  Uint8List? _empPhotoBytes;
  String? _empPhotoName;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tenantStatusSub;
  bool _addingEmp = false;
  bool _connected = false;
  bool _loggingOut = false;

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

  @override
  void initState() {
    super.initState();
    _loadConnectedOnce();
  }

  @override
  void didUpdateWidget(covariant StoreStaffTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親から tenantId が変わった時だけ再読込（タップでメニュー開いただけでは変わらない）
    if (oldWidget.tenantId != widget.tenantId) {
      setState(() {});
      _startWatchTenantStatus();
    }
  }

  @override
  void dispose() {
    _tenantStatusSub?.cancel(); // ← 追加：購読を確実に解放
    super.dispose();
  }

  // 公開ページのベースURL（末尾スラなし）
  String get _publicBase {
    final u = Uri.base; //
    final isHttp =
        (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
    if (isHttp) {
      return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    }
    const fallback = String.fromEnvironment(
      'PUBLIC_BASE',
      defaultValue: 'https://tipri.jp',
    );
    return fallback;
  }

  Future<void> _loadConnectedOnce() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.ownerId!)
          .doc(widget.tenantId)
          .get();

      final status = doc.data()?['status'] as String?;
      final isActive = status == 'active';

      if (mounted) {
        setState(() => _connected = isActive);
      }
    } catch (e) {
      if (mounted) setState(() => _connected = false);
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

  String _allStaffUrl() => '$_publicBase/#/qr-all?t=${widget.tenantId}';

  // ---------- 便利関数 ----------
  String _normalizeEmail(String v) => v.trim().toLowerCase();

  bool _validateEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    return s.contains('@') && s.contains('.');
  }

  Future<Map<String, dynamic>?> _lookupGlobalStaff(String email) async {
    final id = _normalizeEmail(email);
    if (id.isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection('staff')
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final data = (doc.data() ?? {})..['id'] = doc.id;
    return data.cast<String, dynamic>();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findTenantDupByEmail(
    String tenantId,
    String email,
  ) async {
    final q = await FirebaseFirestore.instance
        .collection(widget.ownerId!)
        .doc(tenantId)
        .collection('employees')
        .where('email', isEqualTo: _normalizeEmail(email))
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : q.docs.first;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadMyTenants() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final qs = await FirebaseFirestore.instance.collection(uid).get();
    return qs.docs;

    // ※ メンバー絞り込みを後で入れるなら、ここで doc.data()['members'] を見てローカルで filter してください。
  }

  Future<bool?> _confirmDuplicateDialog({
    required BuildContext context,
    required Map<String, dynamic> existing,
  }) {
    final name = (existing['name'] ?? '') as String? ?? '';
    final email = (existing['email'] ?? '') as String? ?? '';
    final photoUrl = (existing['photoUrl'] ?? '') as String? ?? '';
    return showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: _withLineSeed(Theme.of(context)).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: Colors.black87,
            onPrimary: Colors.white,
            surfaceTint: Colors.transparent,
          ),
        ),
        child: AlertDialog(
          backgroundColor: const Color(0xFFF5F5F5),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(color: Colors.black87),
          title: const Text('同一人物の可能性があります'),
          content: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'スタッフ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(email, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              child: const Text('別人として追加'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Color(0xFFFCC400),
                foregroundColor: Colors.black,
                side: BorderSide(color: Colors.black, width: 3),
              ),
              child: const Text('同一人物（既存を見る）'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- ダイアログ：スタッフ追加（タブ付き） ----------
  Future<void> _openAddEmployeeDialog() async {
    // 事前リセット（写真まわりのみ）
    _empPhotoBytes = null;
    _empPhotoName = null;
    _prefilledPhotoUrlFromGlobal = null;
    _addingEmp = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => addStaffDialog(
        currentTenantId: widget.tenantId,
        // 親は初期値だけ渡す（コントローラはダイアログが所有）
        initialName: '',
        initialEmail: '',
        initialComment: '',
        addingEmp: _addingEmp,
        prefilledPhotoUrlFromGlobal: _prefilledPhotoUrlFromGlobal,
        empPhotoBytes: _empPhotoBytes,
        empPhotoName: _empPhotoName,
        onLocalStateChanged: (adding, bytes, name, prefilledUrl) {
          if (!mounted) return;
          setState(() {
            _addingEmp = adding;
            _empPhotoBytes = bytes;
            _empPhotoName = name;
            _prefilledPhotoUrlFromGlobal = prefilledUrl;
          });
        },
        // 検索系/重複チェックのハンドラ
        normalizeEmail: _normalizeEmail,
        validateEmail: _validateEmail,
        lookupGlobalStaff: _lookupGlobalStaff,
        findTenantDupByEmail: _findTenantDupByEmail,
        confirmDuplicateDialog: _confirmDuplicateDialog,
        loadMyTenants: _loadMyTenants,
        ownerId: widget.ownerId!,
      ),
    );
  }

  static Future<void> showTipriInfoDialog(BuildContext context) async {
    // 表示する画像（あなたのアセットパスに合わせて変更）
    final assets = <String>[
      'assets/pdf/tipri_page-0001.jpg',
      'assets/pdf/tipri_page-0002.jpg',
      'assets/pdf/tipri_page-0003.jpg',
      'assets/pdf/tipri_page-0004.jpg',
      'assets/pdf/tipri_page-0005.jpg',
    ];

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
                    const Divider(height: 1),

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

  ThemeData _withLineSeed(ThemeData base) =>
      base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'LINEseed'));

  @override
  Widget build(BuildContext context) {
    const fabHeight = 44.0;

    final primaryBtnStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, fabHeight),
      backgroundColor: const Color(0xFFFCC400),
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      side: const BorderSide(color: Colors.black, width: 3),
    );

    // ===== Stripe 未接続時 =====
    if (!_connected) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
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
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        child: Column(
                          children: [
                            const Text(
                              'サブスクリプションを登録しよう',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '登録するとチップ受け取りや詳細レポートが有効になります。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () => showTipriInfoDialog(context),
                                icon: const Icon(Icons.info_outline),
                                label: const Text('チップリについて'),
                                style: TextButton.styleFrom(
                                  side: const BorderSide(
                                    width: 3,
                                    color: Colors.black,
                                  ),
                                  foregroundColor: Colors.black87,
                                  backgroundColor: const Color(0xFFFCC400),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ===== 接続済み：スタッフタブ =====
    return Theme(
      data: _withLineSeed(Theme.of(context)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 480; // スマホ判定ざっくり

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: isNarrow ? 12 : 16),

              // === 上部ヘッダ（スマホ / PC でレイアウトを変える）===
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 16),
                child: isNarrow
                    // ----- スマホ向け：縦積み + ボタンは2つ横並びで幅いっぱい -----
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'スタッフ',
                            style: TextStyle(
                              fontFamily: 'LINEseed',
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'スタッフごとのQRコードやプロフィールを管理できます',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8DC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFCC400),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.black87,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'チップ支払者にも同様の順番で表示されます',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black87,
                                    fontFamily: 'LINEseed',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: primaryBtnStyle,
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: _allStaffUrl()),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'URLをコピーしました',
                                          style: TextStyle(
                                            fontFamily: 'LINEseed',
                                          ),
                                        ),
                                        backgroundColor: Color(0xFFFCC400),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.qr_code_2, size: 18),
                                  label: const Text('全スタッフQR'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: primaryBtnStyle,
                                  onPressed: _openAddEmployeeDialog,
                                  icon: const Icon(
                                    Icons.person_add_alt_1,
                                    size: 18,
                                  ),
                                  label: const Text('スタッフ追加'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                foregroundColor: Colors.black87,
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () => showStaffReorderDialog(
                                context: context,
                                ownerId: widget.ownerId!,
                                tenantId: widget.tenantId,
                              ),
                              icon: const Icon(Icons.swap_vert, size: 18),
                              label: const Text('並び替え変更'),
                            ),
                          ),
                        ],
                      )
                    // ----- タブレット/PC向け：左にタイトル、右に2ボタン -----
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'スタッフ',
                                style: TextStyle(
                                  fontFamily: 'LINEseed',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'スタッフごとのQRコードやプロフィールを管理できます',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8DC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFFCC400),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.black87,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'チップ支払者にも同様の順番で表示されます',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87,
                                        fontFamily: 'LINEseed',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                style: primaryBtnStyle,
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _allStaffUrl()),
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'URLをコピーしました',
                                        style: TextStyle(
                                          fontFamily: 'LINEseed',
                                        ),
                                      ),
                                      backgroundColor: Color(0xFFFCC400),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.qr_code_2, size: 18),
                                label: const Text('全スタッフQRコード'),
                              ),
                              FilledButton.icon(
                                style: primaryBtnStyle,
                                onPressed: _openAddEmployeeDialog,
                                icon: const Icon(
                                  Icons.person_add_alt_1,
                                  size: 18,
                                ),
                                label: const Text('スタッフ追加'),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, fabHeight),
                                  foregroundColor: Colors.black87,
                                  side: const BorderSide(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                ),
                                onPressed: () => showStaffReorderDialog(
                                  context: context,
                                  ownerId: widget.ownerId!,
                                  tenantId: widget.tenantId,
                                ),
                                icon: const Icon(Icons.swap_vert, size: 18),
                                label: const Text('並び替え変更'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),

              SizedBox(height: isNarrow ? 8 : 12),

              // === スタッフ一覧（白カード）===
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isNarrow ? 8 : 12,
                    0,
                    isNarrow ? 8 : 12,
                    isNarrow ? 4 : 8,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isNarrow ? 14 : 18),
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection(widget.ownerId!)
                          .doc(widget.tenantId)
                          .collection('employees')
                          .orderBy('sortOrder', descending: false)
                          .snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('読み込みエラー: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snap.data!.docs;
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'まだスタッフが登録されていません',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontFamily: 'LINEseed',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '右上の「スタッフ追加」から、最初のスタッフを登録しましょう。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _openAddEmployeeDialog,
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('最初のスタッフを追加'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black87,
                                    side: const BorderSide(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final entries = List.generate(docs.length, (i) {
                          final doc = docs[i];
                          final d = doc.data() as Map<String, dynamic>;
                          final empId = doc.id;
                          return StaffEntry(
                            index: i + 1,
                            name: (d['name'] ?? '') as String,
                            email: (d['email'] ?? '') as String,
                            photoUrl: (d['photoUrl'] ?? '') as String,
                            comment: (d['comment'] ?? '') as String,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StaffDetailScreen(
                                    tenantId: widget.tenantId,
                                    employeeId: empId,
                                    ownerId: widget.ownerId!,
                                  ),
                                ),
                              );
                            },
                          );
                        });

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: StaffGalleryGrid(entries: entries),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
