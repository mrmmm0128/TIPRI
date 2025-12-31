import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/tenant/newTenant/onboardingSheet.dart';

class TenantSwitcherBar extends StatefulWidget {
  final String? currentTenantId;
  final String? currentTenantName;
  final bool compact; // ← 追加: AppBar用に幅を節約

  final void Function(
    String tenantId,
    String? tenantName,
    String ownerUid,
    bool invited,
  )?
  onChangedEx;

  /// 余白（控えめにデフォルト調整）
  final EdgeInsetsGeometry padding;

  const TenantSwitcherBar({
    super.key,

    this.onChangedEx, // ★追加
    this.currentTenantId,
    this.currentTenantName,
    this.padding = const EdgeInsets.fromLTRB(10, 4, 10, 4),
    this.compact = false,
  });

  @override
  State<TenantSwitcherBar> createState() => _TenantSwitcherBarState();
}

class _TenantSwitcherBarState extends State<TenantSwitcherBar> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  String? _selectedId; // 旧：tenantId ベースの選択（互換用途）
  String? _selectedKey; // ★新：ownerUid/tenantId の複合キー
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // メモ化した参照
  late final CollectionReference<Map<String, dynamic>> _tenantCol;

  // 結合ストリーム（自分のテナント + 招待テナント）
  late final Stream<List<_TenantRow>> _combinedStream;
  late final StreamController<List<_TenantRow>> _combinedCtrl;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _invitedDocSubs = {}; // key = "$ownerUid/$tenantId"
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ownedSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _invitedIndexSub;
  final Map<String, _TenantRow> _rows = {}; // key = "$ownerUid/$tenantId"

  // 複合キー
  String _keyOf(String ownerUid, String tenantId) => '$ownerUid/$tenantId';

  @override
  void initState() {
    super.initState();

    // 初期選択は props からのみ同期（親が決める・旧互換）
    _selectedId = widget.currentTenantId;

    // ユーザーが未ログインなら以降の処理は行わない（nullチェック）
    final uid = _uid;
    if (uid != null) {
      _tenantCol = FirebaseFirestore.instance.collection(uid);
      _combinedCtrl = StreamController<List<_TenantRow>>.broadcast();
      _combinedStream = _combinedCtrl.stream;

      void emit() {
        final list = _rows.values.toList()
          ..sort(
            (a, b) => (a.data['name'] ?? '').toString().toLowerCase().compareTo(
              (b.data['name'] ?? '').toString().toLowerCase(),
            ),
          );
        _combinedCtrl.add(list);
      }

      // (1) 自分のテナント  ← invited を除外
      _ownedSub = _tenantCol
          .where(FieldPath.documentId, isNotEqualTo: 'invited') // 除外
          .orderBy(FieldPath.documentId) // 必須
          .snapshots()
          .listen((qs) {
            // まず自分のキー領域を消してから追加
            _rows.removeWhere((k, _) => k.startsWith('$uid/'));
            for (final d in qs.docs) {
              final key = _keyOf(uid, d.id);
              _rows[key] = _TenantRow(
                ownerUid: uid,
                tenantId: d.id,
                data: d.data(),
                invited: false,
              );
            }
            emit();
          });

      // (2) 招待インデックス /<uid>/invited を購読し、各オーナー配下の実体をさらに購読
      final invitedRef = FirebaseFirestore.instance
          .collection(uid)
          .doc('invited');
      _invitedIndexSub = invitedRef.snapshots().listen((doc) {
        final map = (doc.data()?['tenants'] as Map<String, dynamic>?) ?? {};
        final should = <String>{};

        map.forEach((tenantId, v) {
          final ownerUid = (v is Map ? v['ownerUid'] : null)?.toString() ?? '';
          if (ownerUid.isEmpty) return;
          final key = _keyOf(ownerUid, tenantId);
          should.add(key);

          if (_invitedDocSubs.containsKey(key)) return;

          _invitedDocSubs[key] = FirebaseFirestore.instance
              .collection(ownerUid)
              .doc(tenantId)
              .snapshots()
              .listen((ds) {
                if (ds.exists) {
                  _rows[key] = _TenantRow(
                    ownerUid: ownerUid,
                    tenantId: ds.id,
                    data: ds.data() ?? {},
                    invited: true,
                  );
                } else {
                  _rows.remove(key);
                }
                emit();
              });
        });

        // 不要になった購読を解除
        for (final key
            in _invitedDocSubs.keys
                .where((k) => !should.contains(k))
                .toList()) {
          _invitedDocSubs.remove(key)?.cancel();
          _rows.remove(key);
        }
        emit();
      });
    } else {
      _tenantCol = FirebaseFirestore.instance.collection('_');
      _combinedCtrl = StreamController<List<_TenantRow>>();
      _combinedStream = const Stream.empty();
    }
  }

  @override
  void dispose() {
    for (final s in _invitedDocSubs.values) {
      s.cancel();
    }
    _invitedDocSubs.clear();
    _ownedSub?.cancel();
    _invitedIndexSub?.cancel();
    try {
      _combinedCtrl.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TenantSwitcherBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親が選択IDを更新したら、その値をそのまま反映（build中に通知はしない）
    if (oldWidget.currentTenantId != widget.currentTenantId) {
      _selectedId = widget.currentTenantId;
    }
  }

  // ---- ここが肝：白×黒テーマ（ポップアップ用のローカルテーマ）----
  ThemeData bwTheme(BuildContext context) {
    final base = Theme.of(context);
    final cs = base.colorScheme;
    OutlineInputBorder _border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    return base.copyWith(
      colorScheme: cs.copyWith(
        primary: Colors.black,
        secondary: Colors.black,
        surface: Colors.white,
        onSurface: Colors.black87,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        background: Colors.white,
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
        border: _border(Colors.black12),
        enabledBorder: _border(Colors.black12),
        focusedBorder: _border(Colors.black),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Color(0xFFFCC400),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.black45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black87),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: Colors.black12,
        labelStyle: const TextStyle(color: Colors.black87),
        side: const BorderSide(color: Colors.black26),
        showCheckmark: false,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.black,
      ),
      dividerColor: Colors.black12,
    );
  }

  Future<void> createTenantDialog() async {
    final nameCtrl = TextEditingController();
    final agentCtrl = TextEditingController(); // 代理店コード

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      useRootNavigator: true,
      builder: (_) => Theme(
        data: Theme.of(context).copyWith(
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

        child: WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: const BorderSide(color: Colors.black, width: 3), // ← 太い黒枠
            ),
            backgroundColor: const Color(0xFFF5F5F5),
            surfaceTintColor: Colors.transparent,
            titleTextStyle: const TextStyle(
              color: Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            contentTextStyle: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
            title: const Text(
              '新しい店舗を作成',
              style: TextStyle(fontFamily: 'LINEseed'),
            ),
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

                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black26),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black87, width: 1.2),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 代理店コード入力（任意）
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
                      borderSide: BorderSide(color: Colors.black26),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black87, width: 1.2),
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
                style: TextButton.styleFrom(foregroundColor: Colors.black87),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Color(0xFFFCC400), // 主ボタンは黒地に白文字
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(width: 3, color: Colors.black),
                  ),
                ),
                child: const Text(
                  '作成',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    final name = nameCtrl.text.trim();
    final agentCode = agentCtrl.text.trim();
    if (name.isEmpty) return;

    // ❶ 代理店コードの事前チェック＆確認ダイアログ
    bool shouldTryLinkAgency = false;
    if (agentCode.isEmpty) {
      final proceed = await _confirmProceedWithoutAgency(
        context,
        title: '代理店コードが未入力です',
        message: '代理店と未連携のまま店舗を作成してよろしいですか？\n代理店の方から連携されている場合は、必ず入力ください',
        proceedLabel: '未連携で作成',
      );
      if (!proceed) return;
      shouldTryLinkAgency = false;
    } else {
      final exists = await _agencyCodeExists(agentCode);
      if (!exists) {
        final proceed = await _confirmProceedWithoutAgency(
          context,
          title: '代理店コードが見つかりません',
          message:
              '入力されたコード「$agentCode」は有効ではない可能性があります。\n'
              '代理店と未連携のまま店舗を作成してよろしいですか？',
          proceedLabel: '未連携で作成',
        );
        if (!proceed) return;
        shouldTryLinkAgency = false;
      } else {
        shouldTryLinkAgency = true;
      }
    }

    final uid = _uid; // 既存のログイン中ユーザーUID
    if (uid == null) return;

    final tenantsCol = FirebaseFirestore.instance.collection(uid);

    // ❷ 最初に「draft」で本体ドキュメントを作成（このIDを最後まで使う）
    final newRef = tenantsCol.doc(); // 自動ID
    final tenantId = newRef.id;

    final tenantIdDoc = FirebaseFirestore.instance
        .collection("tenantIndex")
        .doc(tenantId);
    await tenantIdDoc.set({"name": name});

    await newRef.set({
      'name': name,
      'members': [uid],
      'status': 'draft', // 下書き保存
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'agency': {'code': agentCode, 'linked': false},
    }, SetOptions(merge: true));

    final callable = _functions.httpsCallable('createTenantAndNotify');
    final resp = await callable.call({
      'storeName': name,
      if (agentCode.isNotEmpty) 'agentCode': agentCode,
    });

    // ❸ 代理店リンク（見つかった場合のみ実施）
    if (shouldTryLinkAgency) {
      await _tryLinkAgencyByCode(
        code: agentCode,
        ownerUid: uid,
        tenantRef: newRef,
        tenantName: name,
        scaffoldContext: context,
      );
    }

    // ❹ UI更新 & 親へ通知（★キーも更新）
    if (!mounted) return;
    setState(() {
      _selectedId = tenantId; // 旧互換
      _selectedKey = _keyOf(uid, tenantId); // 新
    });

    if (widget.onChangedEx != null) {
      widget.onChangedEx!(tenantId, name, uid, false);
    } else {}

    // ❺ オンボーディング開始（同じ tenantId を渡す）
    await startOnboarding(tenantId, name);

    // ❻ オンボーディング後の状態確認（draftのままでも下書きは残る）
    final snap = await newRef.get();
    if (!mounted) return;

    if (!snap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFCC400),
          content: Text(
            'オンボーディングは完了していません（本登録は未保存）',
            style: TextStyle(color: Colors.black, fontFamily: 'LINEseed'),
          ),
        ),
      );
      return;
    }
  }

  /// 代理店コードが存在するかを事前チェック（status=active のみ有効）
  Future<bool> _agencyCodeExists(String code) async {
    final qs = await FirebaseFirestore.instance
        .collection('agencies')
        .where('code', isEqualTo: code)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    return qs.docs.isNotEmpty;
  }

  /// 「代理店未連携で続行しますか？」の確認ダイアログ
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

  /// 代理店コードから agencies を逆引きし、見つかれば tenant にリンク & contracts を作成
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
        // コードは保存済み（'agency.code'）なので、ここでは未リンクのままにする
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(
            content: Text(
              '代理店コードが見つかりませんでした',
              style: TextStyle(fontFamily: "LINEseed"),
            ),
            backgroundColor: Color(0xFFFCC400),
          ),
        );
        return;
      }

      final agentDoc = qs.docs.first;
      final agentId = agentDoc.id;
      final commissionPercent =
          (agentDoc.data()['commissionPercent'] as num?)?.toInt() ?? 0;

      // tenant の agency 情報を更新（linked=true）
      await tenantRef.set({
        'agency': {
          'code': code,
          'agentId': agentId,
          'commissionPercent': commissionPercent,
          'linked': true,
          'linkedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 代理店配下の contracts にも作成（draft 状態）
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

      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text(
            '代理店「$agentId」とリンクしました',
            style: TextStyle(fontFamily: "LINEseed"),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
        SnackBar(
          content: Text(
            '代理店リンクに失敗しました: $e',
            style: TextStyle(fontFamily: "LINEseed"),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    }
  }

  Future<void> startOnboarding(String tenantId, String tenantName) async {
    final size = MediaQuery.of(context).size;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      useSafeArea: true, // ノッチ/セーフエリア考慮
      barrierColor: Colors.black38,
      backgroundColor: Colors.white,
      // ★ これで横幅フル
      constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return Theme(
          data: bwTheme(context),
          child: OnboardingSheet(
            tenantId: tenantId,
            tenantName: tenantName,
            functions: _functions,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: StreamBuilder<List<_TenantRow>>(
        stream: _combinedStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _itemContainer(
              child: Text(
                'エラー',
                style: const TextStyle(
                  color: Colors.red,
                  fontFamily: 'LINEseed',
                  fontSize: 12,
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return _itemContainer(
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey,
                ),
              ),
            );
          }

          final rows = snap.data!;

          // 現在選択中の行を決定
          _TenantRow? selectedRow;
          if (_selectedKey != null) {
            selectedRow = rows.cast<_TenantRow?>().firstWhere(
              (r) => _keyOf(r!.ownerUid, r.tenantId) == _selectedKey,
              orElse: () => null,
            );
          } else if (_selectedId != null) {
            final uid = _uid;
            selectedRow = rows.cast<_TenantRow?>().firstWhere(
              (r) => r!.tenantId == _selectedId && r.ownerUid == uid,
              orElse: () => rows.cast<_TenantRow?>().firstWhere(
                (r) => r!.tenantId == _selectedId,
                orElse: () => null,
              ),
            );
            if (selectedRow != null) {
              _selectedKey = _keyOf(selectedRow.ownerUid, selectedRow.tenantId);
            }
          }

          // 行がない場合
          if (rows.isEmpty) {
            return GestureDetector(
              onTap: createTenantDialog,
              child: _itemContainer(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, size: 18, color: Colors.black54),
                    SizedBox(width: 8),
                    Text(
                      '店舗を作成',
                      style: TextStyle(
                        fontFamily: 'LINEseed',
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final selectedName = selectedRow?.data['name']?.toString() ?? '店舗を選択';
          final selectedIsDraft = (selectedRow?.data['status'] == 'nonactive');

          return Theme(
            data: bwTheme(context).copyWith(
              // ポップアップメニューのスタイル調整
              popupMenuTheme: PopupMenuThemeData(
                color: Colors.white,
                surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.2),
              ),
            ),
            child: PopupMenuButton<String>(
              offset: const Offset(0, 50),
              tooltip: '店舗切り替え',
              onSelected: (key) async {
                if (key == '__CREATE__') {
                  await createTenantDialog();
                  return;
                }
                if (key == '__RESUME__') {
                  if (_selectedId != null) {
                    await startOnboarding(_selectedId!, selectedName);
                  }
                  return;
                }

                // テナント切り替え処理
                if (key == _selectedKey) return;

                // 1) UI即時反映
                setState(() => _selectedKey = key);

                // 2) データ解決
                final row = rows.firstWhere(
                  (e) => _keyOf(e.ownerUid, e.tenantId) == key,
                  orElse: () => rows.first,
                );
                final data = row.data;
                final name = (data['name'] ?? '') as String?;
                final ownerUid = row.ownerUid;
                final tenantId = row.tenantId;
                final invited = row.invited;

                // 3) 旧互換ID更新
                _selectedId = tenantId;

                // 4) 下書きならダイアログ (既存ロジック踏襲)
                if (data['status'] == 'nonactive') {
                  final initStatus =
                      (data['initialFee'] as Map?)?['status'] ?? 'unpaid';
                  final subStatus =
                      (data['subscription'] as Map?)?['status'] ?? 'inactive';
                  final plan =
                      (data['subscription'] as Map?)?['plan'] as String?;

                  // ダイアログ表示ロジックは長いので関数化した方が良いが、
                  // ここでは一旦そのまま既存ロジックを流用しつつ非同期呼び出し
                  // (buildメソッド内ではないのでcontext使用に注意)
                  if (!mounted) return;

                  // ※ ここで setState等は不要だが、非同期処理後にアクションがあるため確認
                  final shouldResume = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      title: const Text(
                        '下書きがあります',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('この店舗の登録は完了していません。再開しますか？'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              _statusChip('初期費用', initStatus == 'paid'),
                              _statusChip(
                                'サブスク',
                                subStatus == 'active',
                                trailing: plan != null ? '($plan)' : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text(
                            'あとで',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFCC400),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            '再開する',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (shouldResume == true) {
                    await startOnboarding(tenantId, name ?? '');
                  }
                }

                // 5) 通知
                widget.onChangedEx?.call(tenantId, name, ownerUid, invited);
              },
              itemBuilder: (context) {
                final List<PopupMenuEntry<String>> splitItems = [];

                // --- アクション (Draftの場合など) ---
                if (selectedIsDraft && selectedRow != null) {
                  splitItems.add(
                    PopupMenuItem<String>(
                      value: '__RESUME__',
                      height: 40,
                      child: Row(
                        children: const [
                          Icon(
                            Icons.play_circle_fill,
                            color: Color(0xFFFCC400),
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '登録を再開する',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  splitItems.add(const PopupMenuDivider(height: 1));
                }

                // --- テナント一覧 ---
                // 名前順ソート済みと想定
                for (final r in rows) {
                  final key = _keyOf(r.ownerUid, r.tenantId);
                  final isSelected = key == _selectedKey;
                  final name = r.data['name']?.toString() ?? '(No Name)';
                  // Draft表示
                  final isDraft = (r.data['status'] == 'nonactive');

                  splitItems.add(
                    PopupMenuItem<String>(
                      value: key,
                      height: 48,
                      child: Row(
                        children: [
                          if (isSelected)
                            const Icon(
                              Icons.check,
                              color: Colors.blueAccent,
                              size: 18,
                            )
                          else
                            const SizedBox(width: 18), // indent
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: Colors.black87,
                                    fontFamily: 'LINEseed',
                                  ),
                                ),
                                if (r.invited)
                                  Text(
                                    '招待された店舗',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isDraft)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '下書き',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                // --- 新規作成 ---
                splitItems.add(const PopupMenuDivider(height: 1));
                splitItems.add(
                  const PopupMenuItem<String>(
                    value: '__CREATE__',
                    height: 48,
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18, color: Colors.black87),
                        SizedBox(width: 12),
                        Text('新しい店舗を作成', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                );

                return splitItems;
              },
              // トリガー部分（モダンウィジェット）
              child: _itemContainer(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // アイコン
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selectedRow?.invited == true
                            ? Icons.storefront_outlined
                            : Icons.store, // 区別つけても良い
                        size: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // テナント名,
                    Flexible(
                      child: Text(
                        selectedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'LINEseed',
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Draftバッジ
                    if (selectedIsDraft)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFCC400),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),

                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // モダンなコンテナスタイル（白ベース、角丸、淡いボーダー）
  Widget _itemContainer({required Widget child}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // Pill shape
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: child,
    );
  }

  // 進捗の見える Chip
  Widget _statusChip(String label, bool done, {String? trailing}) {
    return Chip(
      side: const BorderSide(color: Colors.black26),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle : Icons.pause_circle_filled, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label${trailing ?? ''}',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
        ],
      ),
      backgroundColor: done ? const Color(0x1100AA00) : const Color(0x11AAAAAA),
    );
  }
}

class _TenantRow {
  final String ownerUid;
  final String tenantId;
  final Map<String, dynamic> data;
  final bool invited; // 招待テナントなら true
  const _TenantRow({
    required this.ownerUid,
    required this.tenantId,
    required this.data,
    required this.invited,
  });
}
