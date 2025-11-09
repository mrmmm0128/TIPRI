//import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ignore: must_be_immutable, camel_case_types
class addStaffDialog extends StatefulWidget {
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

  addStaffDialog({
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
  State<addStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<addStaffDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // このダイアログ専用の TextEditingController（ここで生成・破棄）
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _commentCtrl;

  bool _isSubmitting = false;

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
                backgroundColor: const Color(0xFFFCC400),
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 3),
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
          return;
        }
        // 別人として続行
      }
    }

    // 追加
    await _createEmployee(
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

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      // ★ ここで 1 フレーム UI に譲る（描画→スピナー表示）
      await Future<void>.delayed(Duration.zero);
      await _submitCreate();
    } finally {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
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
                  height: 420, // ダイアログ内の高さを固定（この子は別ダイアログなのでOK）
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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

    // 画面サイズ・キーボード分を考慮して本文の最大高さを決める
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final keyboard = mq.viewInsets.bottom; // キーボード高さ
    final maxBodyH = ((screenH - keyboard) * 0.72).clamp(360.0, screenH * 0.9);

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
        // 低身長画面で余白を詰めて入りやすく
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                // Material3 では MaterialStateProperty を使う
                overlayColor: MaterialStateProperty.all<Color>(
                  Colors.transparent,
                ),
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                indicatorPadding: const EdgeInsets.all(2), // ← 内側に2pxマージン
                indicatorSize: TabBarIndicatorSize.tab,
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
          height: maxBodyH.toDouble(), // ← 上限ではなく「確定の高さ」を渡す
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.black87),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Expanded(
                  // 👇 ここで全体を1つの SingleChildScrollView に包む
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: 520, // ← 任意：見た目の高さの目安（固定でなくてもOK）
                      child: TabBarView(
                        controller: _tab,
                        physics:
                            const NeverScrollableScrollPhysics(), // ← 外側だけスクロール
                        children: [
                          // タブ1：普通のColumn（スクロールしない）
                          Column(
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

                          // タブ2
                          _otherTenantsTab(),
                        ],
                      ),
                    ),
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
          FilledButton.icon(
            onPressed: _isSubmitting ? null : _handleSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFCC400),
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 3),
            ),
            // ← アイコン枠を常に同じ幅にしてレイアウトのブレを防ぐ
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.black, // 黄背景でも見えるように
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('追加', style: TextStyle(color: Colors.black87)),
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
          style: const TextStyle(fontFamily: 'LINEseed'),
        ),
      ),
    );
  }
}

class _TenantPickerField extends StatelessWidget {
  final VoidCallback onTap;
  final String labelText;
  const _TenantPickerField({required this.onTap, required this.labelText});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ).copyWith(right: 44), // 矢印ぶんの右余白を確保
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.arrow_drop_down),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          filled: true,
          fillColor: Colors.white,
          labelText: '店舗を選択',
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            labelText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // 長い店名でも見切れない
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
        filled: true,
        fillColor: Colors.white,
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
