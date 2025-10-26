import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // クリップボード
import 'package:yourpay/tenant/method/image_scrol.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_detail.dart';
import 'package:yourpay/tenant/widget/store_staff/staff_entry.dart';
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
      builder: (_) => _addStaffDialog(
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
    //final mq = MediaQuery.of(context);
    const fabHeight = 44.0;

    final primaryBtnStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, fabHeight),
      backgroundColor: Color(0xFFFCC400),
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      side: BorderSide(color: Colors.black, width: 3),
    );

    return _connected
        ? Theme(
            data: _withLineSeed(Theme.of(context)),
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                                      style: TextStyle(fontFamily: 'LINEseed'),
                                    ),
                                    backgroundColor: Color(0xFFFCC400),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('全スタッフQRコード'),
                            ),
                            const SizedBox(width: 7),
                            FilledButton.icon(
                              style: primaryBtnStyle,
                              onPressed: _openAddEmployeeDialog,
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('スタッフ追加'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection(widget.ownerId!)
                            .doc(widget.tenantId)
                            .collection('employees')
                            .orderBy('createdAt', descending: true)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Text('読み込みエラー: ${snap.error}'),
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'まだ社員がいません',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _openAddEmployeeDialog,
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('最初の社員を追加'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black87,
                                      side: const BorderSide(
                                        color: Colors.black87,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final entries = List.generate(docs.length, (i) {
                            final doc = docs[i];
                            final d = docs[i].data() as Map<String, dynamic>;
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
                            padding: EdgeInsets.only(bottom: 0),
                            child: StaffGalleryGrid(entries: entries),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                // Positioned(
                //   right: 16,
                //   bottom: fabBottomMargin + safeBottom,
                //   child: FilledButton.icon(
                //     style: primaryBtnStyle,
                //     onPressed: _openAddEmployeeDialog,
                //     icon: const Icon(Icons.person_add_alt_1),
                //     label: const Text('スタッフ追加'),
                //   ),
                // ),
              ],
            ),
          )
        : Scaffold(
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
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: Color(0xFFFCC400), // 枠線だけアクセント
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
              ),
            ),
          );
  }
}

// ignore: must_be_immutable, camel_case_types
class _addStaffDialog extends StatefulWidget {
  final String currentTenantId;

  // 親からは初期値のみ受け取る
  final String initialName;
  final String initialEmail;
  final String initialComment;
  final String ownerId;

  bool addingEmp;
  Uint8List? empPhotoBytes;
  String? empPhotoName;
  String? prefilledPhotoUrlFromGlobal;

  // 状態反映（親へ通知）
  final void Function(
    bool adding,
    Uint8List? bytes,
    String? name,
    String? prefilledUrl,
  )
  onLocalStateChanged;

  // ハンドラ（親から注入）
  final String Function(String value) normalizeEmail;
  final bool Function(String value) validateEmail;
  final Future<Map<String, dynamic>?> Function(String email) lookupGlobalStaff;
  final Future<QueryDocumentSnapshot<Map<String, dynamic>>?> Function(
    String tenantId,
    String email,
  )
  findTenantDupByEmail;
  final Future<bool?> Function({
    required BuildContext context,
    required Map<String, dynamic> existing,
  })
  confirmDuplicateDialog;
  final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> Function()
  loadMyTenants;

  _addStaffDialog({
    required this.currentTenantId,
    required this.initialName,
    required this.initialEmail,
    required this.initialComment,
    required this.addingEmp,
    required this.empPhotoBytes,
    required this.empPhotoName,
    required this.prefilledPhotoUrlFromGlobal,
    required this.onLocalStateChanged,
    required this.normalizeEmail,
    required this.validateEmail,
    required this.lookupGlobalStaff,
    required this.findTenantDupByEmail,
    required this.confirmDuplicateDialog,
    required this.loadMyTenants,
    required this.ownerId,
  });

  @override
  State<_addStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_addStaffDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // このダイアログ専用の TextEditingController（ここで生成・破棄）
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _commentCtrl;

  // ── ダイアログ内ローカル状態 ─────────────────────
  Uint8List? _localPhotoBytes;
  String? _localPhotoName;
  String? _localPrefilledPhotoUrl;

  // タブ2（他店舗から取り込み）用
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _myTenants = [];
  String? _selectedTenantId; // 現在の店舗以外
  String _otherSearch = ''; // 名前/メールの部分一致（ローカルフィルタ）
  final _tenantSearchCtrl = TextEditingController(); // 店舗ピッカー内の検索

  late final ScrollController _otherEmpListCtrl;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    _nameCtrl = TextEditingController(text: widget.initialName);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _commentCtrl = TextEditingController(text: widget.initialComment);

    // ローカル初期化
    _localPhotoBytes = widget.empPhotoBytes;
    _localPhotoName = widget.empPhotoName;
    _localPrefilledPhotoUrl = widget.prefilledPhotoUrlFromGlobal;

    // NEW

    _otherEmpListCtrl = ScrollController();

    _prepareMyTenants();
  }

  @override
  void dispose() {
    _tab.dispose();
    _tenantSearchCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _commentCtrl.dispose();

    // NEW

    _otherEmpListCtrl.dispose();

    super.dispose();
  }

  Future<void> _prepareMyTenants() async {
    final tenants = await widget.loadMyTenants();
    if (!mounted) return;
    setState(() {
      _myTenants = tenants
          .where((d) => d.id != widget.currentTenantId)
          .toList();
      _selectedTenantId = _myTenants.isEmpty ? null : _myTenants.first.id;
    });
  }

  String _detectContentType(String? filename) {
    final ext = (filename ?? '').split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickPhoto() async {
    if (widget.addingEmp) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    try {
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.readStream != null) {
        final chunks = <int>[];
        await for (final c in f.readStream!) {
          chunks.addAll(c);
        }
        bytes = Uint8List.fromList(chunks);
      }
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '画像の読み込みに失敗しました',
                style: TextStyle(fontFamily: 'LINEseed'),
              ),
              backgroundColor: Color(0xFFFCC400),
            ),
          );
        }
        return;
      }

      // ローカル状態を更新（即プレビュー反映）
      setState(() {
        _localPhotoBytes = bytes;
        _localPhotoName = f.name;
        _localPrefilledPhotoUrl = null; // 手元画像を優先
      });

      // 親にも通知（必要なら）
      widget.onLocalStateChanged(false, bytes, f.name, null);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '画像選択エラー: $e',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    }
  }

  // ============= タブ1：新規/グローバル取り込み =============
  Future<void> _searchGlobalByEmail() async {
    final email = widget.normalizeEmail(_emailCtrl.text);
    if (email.isEmpty || !widget.validateEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '検索には正しいメールアドレスが必要です',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }
    final data = await widget.lookupGlobalStaff(email);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '一致するスタッフは見つかりませんでした',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
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
          title: const Text('プロフィールを取り込みますか？'),
          content: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: (data['photoUrl'] ?? '').toString().isNotEmpty
                    ? NetworkImage((data['photoUrl'] as String))
                    : null,
                child: ((data['photoUrl'] ?? '') as String).isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['name'] ?? '') as String? ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (data['email'] ?? '') as String? ?? '',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    if ((data['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        (data['comment'] as String),
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              child: const Text('閉じる'),
            ),
            FilledButton(
              onPressed: () {
                // フィールドに反映
                _nameCtrl.text = (data['name'] as String?) ?? _nameCtrl.text;
                _commentCtrl.text =
                    (data['comment'] as String?) ?? _commentCtrl.text;

                final url = (data['photoUrl'] as String?) ?? '';

                // ローカル状態を URL 優先に切り替え
                setState(() {
                  _localPhotoBytes = null;
                  _localPhotoName = null;
                  _localPrefilledPhotoUrl = url;
                });

                // 親にも通知（任意）
                widget.onLocalStateChanged(false, null, null, url);

                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Color(0xFFFCC400),
                foregroundColor: Colors.black,
                side: BorderSide(color: Colors.black, width: 3),
              ),
              child: const Text('取り込む'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitCreate() async {
    if (widget.addingEmp) return;
    final name = _nameCtrl.text.trim();
    final email = widget.normalizeEmail(_emailCtrl.text);
    final comment = _commentCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '名前を入力してください',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }
    if (email.isNotEmpty && !widget.validateEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '正しいメールアドレスを入力してください',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    // 現在の店舗で同じメールがいるか
    if (email.isNotEmpty) {
      final dup = await widget.findTenantDupByEmail(
        widget.currentTenantId,
        email,
      );
      if (dup != null) {
        final same = await widget.confirmDuplicateDialog(
          context: context,
          existing: {
            'name': dup.data()['name'],
            'email': dup.data()['email'],
            'photoUrl': dup.data()['photoUrl'],
          },
        );
        if (same == true) {
          if (!mounted) return;
          Navigator.pop(context); // ダイアログを閉じる

          // TODO: ここであなたの StaffDetailScreen に遷移してください
          // Navigator.push(
          //   context,
          //   MaterialPageRoute(
          //     builder: (_) => StaffDetailScreen(
          //       tenantId: widget.currentTenantId,
          //       employeeId: dup.id,
          //     ),
          //   ),
          // );
          return;
        }
        // 別人として続行
      }
    }

    // 追加
    _createEmployee(
      tenantId: widget.currentTenantId,
      name: name,
      email: email,
      comment: comment,
      ownerId: widget.ownerId,
    );
  }

  Future<void> _createEmployee({
    required String tenantId,
    required String name,
    required String email,
    required String comment,
    required String ownerId,
  }) async {
    // 親へ進捗通知（ローカル状態で）
    widget.onLocalStateChanged(
      true,
      _localPhotoBytes,
      _localPhotoName,
      _localPrefilledPhotoUrl,
    );

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final user = FirebaseAuth.instance.currentUser!;
      final empRef = FirebaseFirestore.instance
          .collection(ownerId)
          .doc(tenantId)
          .collection('employees')
          .doc();

      // 写真アップロード（ローカル状態を使用）
      String photoUrl = '';
      if (_localPhotoBytes != null) {
        final contentType = _detectContentType(_localPhotoName);
        final ext = contentType.split('/').last;
        final storageRef = FirebaseStorage.instance.ref().child(
          '$uid/$tenantId/employees/${empRef.id}/photo.$ext',
        );
        await storageRef.putData(
          _localPhotoBytes!,
          SettableMetadata(contentType: contentType),
        );
        photoUrl = await storageRef.getDownloadURL();
      } else if ((_localPrefilledPhotoUrl ?? '').isNotEmpty) {
        photoUrl = _localPrefilledPhotoUrl!;
      }

      await empRef.set({
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': {'uid': user.uid, 'email': user.email},
      });

      // グローバル staff/{email} を軽く upsert
      if (email.isNotEmpty) {
        await FirebaseFirestore.instance.collection('staff').doc(email).set({
          'email': email,
          if (name.isNotEmpty) 'name': name,
          if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,
          if (comment.isNotEmpty) 'comment': comment,
          'tenants': FieldValue.arrayUnion([tenantId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '社員を追加しました',
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
              '追加に失敗: $e',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
      }
    } finally {
      // 親へ完了通知（ローカル状態で）
      widget.onLocalStateChanged(
        false,
        _localPhotoBytes,
        _localPhotoName,
        _localPrefilledPhotoUrl,
      );
    }
  }

  // ============= タブ2：他店舗から取り込み =============
  String _selectedTenantName() {
    if (_selectedTenantId == null) return '店舗を選択';
    final idx = _myTenants.indexWhere((d) => d.id == _selectedTenantId);
    if (idx < 0) return '店舗を選択';
    final name = (_myTenants[idx].data()['name'] ?? '(no name)').toString();
    return name.isEmpty ? '(no name)' : name;
  }

  Future<void> _openTenantPickerDialog() async {
    _tenantSearchCtrl.text = '';
    if (!mounted) return;

    if (_myTenants.isEmpty) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (ctx) => AlertDialog(
          title: const Text('店舗を選択'),
          content: const Text('あなたがメンバーの他店舗が見つかりませんでした'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: false).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) {
        String localQuery = '';
        final listCtrl = ScrollController(); // ← ListView/Scrollbar共用

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = _myTenants.where((d) {
              if (localQuery.isEmpty) return true;
              final name = (d.data()['name'] ?? '').toString().toLowerCase();
              return name.contains(localQuery);
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFFF5F5F5),
              surfaceTintColor: Colors.transparent,
              title: const Text(
                '店舗を選択',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  width: 560,
                  height: 420, // ★ ダイアログ内の高さを固定
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // ★ ここに Expanded を置かない
                    children: [
                      TextField(
                        controller: _tenantSearchCtrl,
                        decoration: InputDecoration(
                          hintText: '店舗名で検索',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setLocal(() {
                          localQuery = v.trim().toLowerCase();
                        }),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        // ★ リスト側も固定高さ（例: 320）
                        height: 320,
                        child: Scrollbar(
                          controller: listCtrl,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: listCtrl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            primary: false,
                            itemCount: filtered.isEmpty ? 1 : filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              if (filtered.isEmpty) {
                                return const ListTile(
                                  title: Text('該当する店舗がありません'),
                                );
                              }
                              final t = filtered[i];
                              final name = (t.data()['name'] ?? '(no name)')
                                  .toString();
                              final selected = t.id == _selectedTenantId;
                              return ListTile(
                                dense: true,
                                title: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.black87,
                                      )
                                    : null,
                                onTap: () {
                                  if (!mounted) return;
                                  setState(() => _selectedTenantId = t.id);
                                  Navigator.of(ctx, rootNavigator: false).pop();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: false).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                  child: const Text('閉じる'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _otherTenantsTab() {
    if (_myTenants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'あなたがメンバーの他店舗が見つかりませんでした',
          style: TextStyle(color: Colors.black87),
        ),
      );
    }

    // 選択済み店舗のストリーム（未選択時はプレースホルダ表示）
    final uidVar = FirebaseAuth.instance.currentUser?.uid;
    final selectedId = _selectedTenantId;
    final employeesStream = (selectedId == null || uidVar == null)
        ? null
        : FirebaseFirestore.instance
              .collection(uidVar)
              .doc(selectedId)
              .collection('employees')
              .orderBy('createdAt', descending: true)
              .snapshots();

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final narrow = w < 560; // ← 狭いときは縦並びや下段ボタンに切替

        return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // 店舗選択 + 検索（狭い時は縦に並べて見切れ防止）
            if (!narrow)
              Row(
                children: [
                  Expanded(
                    child: _TenantPickerField(
                      onTap: _openTenantPickerDialog,
                      labelText: _selectedTenantName(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LocalSearchField(
                      onChanged: (v) =>
                          setState(() => _otherSearch = v.trim().toLowerCase()),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _TenantPickerField(
                    onTap: _openTenantPickerDialog,
                    labelText: _selectedTenantName(),
                  ),
                  const SizedBox(height: 8),
                  _LocalSearchField(
                    onChanged: (v) =>
                        setState(() => _otherSearch = v.trim().toLowerCase()),
                  ),
                ],
              ),
            const SizedBox(height: 8),

            // リスト（店舗未選択なら案内）
            if (employeesStream == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'まず「店舗を選択」をタップして候補を選んでください',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              )
            else
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: employeesStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('読み込みエラー: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    var items = docs
                        .map((d) => d.data() as Map<String, dynamic>)
                        .toList();

                    if (_otherSearch.isNotEmpty) {
                      items = items.where((m) {
                        final name = (m['name'] ?? '').toString().toLowerCase();
                        final email = (m['email'] ?? '')
                            .toString()
                            .toLowerCase();
                        return name.contains(_otherSearch) ||
                            email.contains(_otherSearch);
                      }).toList();
                    }

                    // 空でもScroll位置を持たせる
                    final count = (items.isEmpty) ? 1 : items.length;
                    return Scrollbar(
                      controller: _otherEmpListCtrl,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _otherEmpListCtrl,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: count,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('該当スタッフがいません')),
                            );
                          }
                          final m = items[i];
                          final name = (m['name'] ?? '') as String? ?? 'スタッフ';
                          final email = (m['email'] ?? '') as String? ?? '';
                          final photoUrl =
                              (m['photoUrl'] ?? '') as String? ?? '';
                          final comment = (m['comment'] ?? '') as String? ?? '';

                          // 取り込み処理（共通化）
                          void _import() {
                            _nameCtrl.text = name;
                            _emailCtrl.text = email;
                            _commentCtrl.text = comment;
                            setState(() {
                              _localPhotoBytes = null;
                              _localPhotoName = null;
                              _localPrefilledPhotoUrl = photoUrl;
                            });
                            widget.onLocalStateChanged(
                              false,
                              null,
                              null,
                              photoUrl,
                            );
                            _tab.animateTo(0);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'フォームに取り込みました（取り込み先は現在の店舗）',
                                  style: TextStyle(fontFamily: 'LINEseed'),
                                ),
                                backgroundColor: Color(0xFFFCC400),
                              ),
                            );
                          }

                          // 狭い幅ではボタンを下段フル幅にして見切れ防止
                          if (narrow) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0x11000000),
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: photoUrl.isNotEmpty
                                            ? NetworkImage(photoUrl)
                                            : null,
                                        child: photoUrl.isEmpty
                                            ? const Icon(Icons.person)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _EmpTexts(
                                          name: name,
                                          email: email,
                                          comment: comment,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed: _import,
                                      icon: const Icon(Icons.download),
                                      label: const Text('取り込む'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // 広い幅：従来の横並び（でもオーバーフローしないよう余白管理）
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0x11000000),
                              ),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundImage: photoUrl.isNotEmpty
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _EmpTexts(
                                    name: name,
                                    email: email,
                                    comment: comment,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 120,
                                  ),
                                  child: FilledButton.tonalIcon(
                                    onPressed: _import,
                                    icon: const Icon(Icons.download),
                                    label: const Text('取り込む'),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '※ 取り込み先は「現在の店舗」です。保存ボタンで確定します。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        );
      },
    );
  }

  ThemeData _withLineSeed(ThemeData base) =>
      base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'LINEseed'));

  @override
  Widget build(BuildContext context) {
    // 表示は常にローカル状態を参照
    final ImageProvider<Object>? photoProvider = (_localPhotoBytes != null)
        ? MemoryImage(_localPhotoBytes!)
        : ((_localPrefilledPhotoUrl?.isNotEmpty ?? false)
              ? NetworkImage(_localPrefilledPhotoUrl!)
              : null);

    return Theme(
      data: _withLineSeed(Theme.of(context)).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: Colors.black87,
          onPrimary: Colors.white,
          surfaceTint: Colors.transparent,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.black87,
          selectionColor: Color(0x33000000),
          selectionHandleColor: Colors.black87,
        ),
      ),
      child: AlertDialog(
        backgroundColor: const Color(0xFFF5F5F5),
        surfaceTintColor: Colors.transparent,
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '社員を追加',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4), // ← 白い外枠を残す
              child: TabBar(
                controller: _tab,
                isScrollable: false, // 幅いっぱい均等
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                indicatorPadding: const EdgeInsets.all(2), // ← 内側に2pxマージン
                indicatorSize: TabBarIndicatorSize.tab,
                // “_ModeChip”の見た目をindicatorで再現（黄色＋黒ぶち）
                indicator: ShapeDecoration(
                  color: const Color(0xFFFCC400), // アクティブ黄
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.black, width: 4),
                  ),
                ),
                labelColor: Colors.white, // アクティブ文字色
                unselectedLabelColor: Colors.black87,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(child: _TabLabel('新規 / グローバル')),
                  Tab(child: _TabLabel('他店舗から取り込み')),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 640,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.black87),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      // タブ1：新規 / グローバル取り込み
                      SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.addingEmp ? null : _pickPhoto,
                              child: CircleAvatar(
                                radius: 40,
                                backgroundImage: photoProvider,
                                backgroundColor: Colors.black26,
                                child: photoProvider == null
                                    ? const Icon(Icons.camera_alt, size: 28)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameCtrl,
                              decoration: _inputDeco('名前（必須）'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDeco(
                                'メールアドレス（任意・検索可）',
                                suffix: IconButton(
                                  tooltip: 'メールで検索（グローバル）',
                                  icon: const Icon(Icons.search),
                                  onPressed: widget.addingEmp
                                      ? null
                                      : _searchGlobalByEmail,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _commentCtrl,
                              maxLines: 2,
                              decoration: _inputDeco(
                                'コメント（任意）',
                                hint: '得意分野や一言メモなど',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '名前は必須。写真・メール・コメントは任意です。',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // タブ2：他店舗から取り込み
                      _otherTenantsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: widget.addingEmp ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.black87),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: widget.addingEmp ? null : _submitCreate,
            style: FilledButton.styleFrom(
              backgroundColor: Color(0xFFFCC400),
              foregroundColor: Colors.black,
              side: BorderSide(color: Colors.black, width: 3),
            ),
            child: widget.addingEmp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('追加'),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black26),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black87, width: 1.2),
      ),
      suffixIcon: suffix,
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String text;
  const _TabLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown, // 枠内で自動縮小（オーバーフロー防止）
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: "LINEseed"),
        ),
      ),
    );
  }
}

/// 店舗ピッカー（見切れ対策：suffixIconで矢印／右に十分な余白）
class _TenantPickerField extends StatelessWidget {
  final VoidCallback onTap;
  final String labelText;
  const _TenantPickerField({required this.onTap, required this.labelText});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        isFocused: false,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ).copyWith(right: 44), // ← 矢印ぶんの右余白を確保
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.arrow_drop_down),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            labelText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // ← 長い店名でも見切れない
          ),
        ),
      ),
    );
  }
}

/// ローカル検索（安全な省略表示）
class _LocalSearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _LocalSearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        labelText: '名前/メールで絞り込み（ローカル）',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}

/// 名前／メール／コメント（省略・行数制御を統一）
class _EmpTexts extends StatelessWidget {
  final String name;
  final String email;
  final String comment;
  const _EmpTexts({
    required this.name,
    required this.email,
    required this.comment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        if (email.isNotEmpty)
          Text(
            email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54),
          ),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            comment,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black87),
          ),
        ],
      ],
    );
  }
}
