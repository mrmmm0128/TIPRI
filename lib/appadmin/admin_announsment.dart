// lib/admin/admin_announcement_page.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum _TargetScope { all, tenantIds, filters, selectByName }

class AdminAnnouncementPage extends StatefulWidget {
  const AdminAnnouncementPage({super.key});

  @override
  State<AdminAnnouncementPage> createState() => _AdminAnnouncementPageState();
}

class _AdminAnnouncementPageState extends State<AdminAnnouncementPage> {
  // ===== Brand / Styles =====
  static const brandYellow = Color(0xFFFCC400);

  InputDecoration _blackThickInput(
    String label, {
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool alignLabelWithHint = false,
    int? minLines,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(
        color: Colors.black87,
        fontFamily: 'LINEseed',
      ),
      hintStyle: const TextStyle(color: Colors.black54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 3),
      ),
    );
  }

  ButtonStyle get _brandFilled => FilledButton.styleFrom(
    backgroundColor: brandYellow,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    side: const BorderSide(color: Colors.black, width: 3),
    textStyle: const TextStyle(
      fontFamily: 'LINEseed',
      fontWeight: FontWeight.w800,
    ),
  );

  ButtonStyle get _brandOutlined => OutlinedButton.styleFrom(
    foregroundColor: Colors.black,
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black, width: 3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(
      fontFamily: 'LINEseed',
      fontWeight: FontWeight.w700,
    ),
  );

  // ===== Controllers / States =====
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tenantIdsCtrl = TextEditingController();

  // 新規: 店舗名検索
  final _nameSearchCtrl = TextEditingController();
  bool _searching = false;
  List<Map<String, String>> _searchResults = []; // [{tenantId, ownerUid, name}]
  final Set<String> _selectedTenantIds = {}; // tenantId 選択セット

  _TargetScope _scope = _TargetScope.all;
  bool _filterActiveOnly = true;
  bool _filterChargesEnabledOnly = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _urlCtrl.dispose();
    _tenantIdsCtrl.dispose();
    _nameSearchCtrl.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  List<String> _parseTenantIds(String raw) {
    if (raw.trim().isEmpty) return const [];
    final parts = raw
        .split(RegExp(r'[\s,、\n\r\t]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    parts.sort();
    return parts;
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Container(width: 6, height: 18, color: Colors.black),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'LINEseed',
            ),
          ),
        ],
      ),
    );
  }

  // ===== Targets resolve / commit =====
  Future<List<Map<String, String>>> _resolveTargets({
    required _TargetScope scope,
    required List<String> tenantIds,
    required bool activeOnly,
    required bool chargesEnabledOnly,
  }) async {
    final idxCol = FirebaseFirestore.instance.collection('tenantIndex');
    final List<Map<String, String>> out = [];

    if (scope == _TargetScope.tenantIds) {
      // 個別ID指定
      for (final id in tenantIds) {
        final doc = await idxCol.doc(id).get();
        if (!doc.exists) continue;
        final data = doc.data()!;
        final uid = (data['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;

        if (activeOnly && ((data['status'] as String?) ?? '') != 'active') {
          continue;
        }
        if (chargesEnabledOnly &&
            !(((data['connect'] as Map?)?['charges_enabled']) == true)) {
          continue;
        }
        out.add({'tenantId': id, 'ownerUid': uid});
      }
      return out;
    }

    if (scope == _TargetScope.selectByName) {
      // チェックで選ばれたものをそのまま採用
      for (final id in _selectedTenantIds) {
        final doc = await idxCol.doc(id).get();
        if (!doc.exists) continue;
        final data = doc.data()!;
        final uid = (data['uid'] as String?) ?? '';
        if (uid.isEmpty) continue;
        out.add({'tenantId': id, 'ownerUid': uid});
      }
      return out;
    }

    // all / filters は全件を取得してクライアントフィルタ
    final snap = await idxCol.get();
    for (final d in snap.docs) {
      final data = d.data();
      final uid = (data['uid'] as String?) ?? '';
      if (uid.isEmpty) continue;

      if (activeOnly && ((data['status'] as String?) ?? '') != 'active') {
        continue;
      }
      if (chargesEnabledOnly &&
          !(((data['connect'] as Map?)?['charges_enabled']) == true)) {
        continue;
      }
      out.add({'tenantId': d.id, 'ownerUid': uid});
    }
    return out;
  }

  Future<void> _commitAlertsInBatches(
    List<Map<String, String>> targets, {
    required Map<String, dynamic> alertPayloadBase,
  }) async {
    const limit = 480; // 余裕をみて 480/バッチ
    for (int i = 0; i < targets.length; i += limit) {
      final slice = targets.sublist(i, math.min(i + limit, targets.length));
      final batch = FirebaseFirestore.instance.batch();

      for (final t in slice) {
        final ownerUid = t['ownerUid']!;
        final tenantId = t['tenantId']!;
        final ref = FirebaseFirestore.instance
            .collection(ownerUid)
            .doc(tenantId)
            .collection('alerts')
            .doc();
        batch.set(ref, {
          ...alertPayloadBase,
          'sentAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final url = _urlCtrl.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タイトルと本文は必須です')));
      return;
    }

    // 対象抽出
    List<String> tenantIds = const [];
    if (_scope == _TargetScope.tenantIds) {
      tenantIds = _parseTenantIds(_tenantIdsCtrl.text);
      if (tenantIds.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配信する店舗IDを入力してください')));
        return;
      }
    }
    if (_scope == _TargetScope.selectByName && _selectedTenantIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('送信先を1件以上選択してください')));
      return;
    }

    setState(() => _sending = true);
    try {
      final targets = await _resolveTargets(
        scope: _scope,
        tenantIds: tenantIds,
        activeOnly: _scope == _TargetScope.filters ? _filterActiveOnly : false,
        chargesEnabledOnly: _scope == _TargetScope.filters
            ? _filterChargesEnabledOnly
            : false,
      );

      if (targets.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配信対象が見つかりませんでした')));
        setState(() => _sending = false);
        return;
      }

      // alerts ペイロード（既存の読み側と整合）
      final currentUser = FirebaseAuth.instance.currentUser;
      final alertPayloadBase = <String, dynamic>{
        'type': 'admin_announcement',
        'title': title,
        'message': body, // ← 既存の読み手が使うフィールド
        if (url.isNotEmpty) 'url': url,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': {'uid': currentUser?.uid, 'email': currentUser?.email},
      };

      await _commitAlertsInBatches(targets, alertPayloadBase: alertPayloadBase);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('配信しました（${targets.length} 件）')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ========= 店舗名検索 =========
  Future<void> _searchByName() async {
    final q = _nameSearchCtrl.text.trim().toLowerCase();
    setState(() {
      _searching = true;
      _searchResults = [];
    });

    try {
      // ※件数多い場合は Functions で nameLower の prefix 検索推奨
      final snap = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .get();

      final List<Map<String, String>> rows = [];
      for (final d in snap.docs) {
        final data = d.data();
        final name = (data['name'] as String? ?? '').trim();
        final uid = (data['uid'] as String? ?? '').trim();
        if (uid.isEmpty || name.isEmpty) continue;
        if (q.isEmpty || name.toLowerCase().contains(q)) {
          rows.add({'tenantId': d.id, 'ownerUid': uid, 'name': name});
        }
      }
      rows.sort((a, b) => a['name']!.compareTo(b['name']!));

      setState(() => _searchResults = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('検索に失敗: $e')));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _buildSelectByNameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '店舗名で検索して選択',
          style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'LINEseed'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameSearchCtrl,
                onSubmitted: (_) => _searchByName(),
                style: const TextStyle(fontFamily: 'LINEseed'),
                cursorColor: Colors.black,
                decoration: _blackThickInput(
                  '店舗名の一部で検索',
                  hint: '例: 渋谷, ramen, ...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: _brandFilled,
              onPressed: _searching ? null : _searchByName,
              icon: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? '検索中…' : '検索'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 検索結果リスト
        if (_searchResults.isEmpty)
          const Text('検索結果はここに表示されます')
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.black12),
              itemBuilder: (context, i) {
                final r = _searchResults[i];
                final tid = r['tenantId']!;
                final name = r['name']!;
                final selected = _selectedTenantIds.contains(tid);
                return CheckboxListTile(
                  dense: true,
                  value: selected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedTenantIds.add(tid);
                      } else {
                        _selectedTenantIds.remove(tid);
                      }
                    });
                  },
                  title: Text(
                    name,
                    style: const TextStyle(fontFamily: 'LINEseed'),
                  ),
                  subtitle: Text('tenantId: $tid'),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
        const SizedBox(height: 8),

        // 選択件数＆全選択/解除
        Row(
          children: [
            Text('選択中: ${_selectedTenantIds.length}件'),
            const Spacer(),
            OutlinedButton(
              style: _brandOutlined,
              onPressed: () {
                final ids = _searchResults.map((e) => e['tenantId']!).toList();
                setState(() => _selectedTenantIds.addAll(ids));
              },
              child: const Text('すべて選択'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: _brandOutlined,
              onPressed: () => setState(() => _selectedTenantIds.clear()),
              child: const Text('選択解除'),
            ),
          ],
        ),
      ],
    );
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final isSelect = _scope == _TargetScope.selectByName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'お知らせ配信',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontFamily: 'LINEseed',
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,

        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          // 画面幅いっぱいだけど、可読性のため最大幅は少し制限
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== 入力フォーム =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _sectionTitle('お知らせ内容'),
                    TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(fontFamily: 'LINEseed'),
                      cursorColor: Colors.black,
                      decoration: _blackThickInput('タイトル *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyCtrl,
                      minLines: 5,
                      maxLines: 10,
                      style: const TextStyle(fontFamily: 'LINEseed'),
                      cursorColor: Colors.black,
                      decoration: _blackThickInput(
                        '本文 *',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(fontFamily: 'LINEseed'),
                      cursorColor: Colors.black,
                      decoration: _blackThickInput('任意のURL（詳細ページ等）'),
                    ),
                  ],
                ),
              ),

              // ===== 配信対象 =====
              _sectionTitle('配信対象'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    RadioListTile<_TargetScope>(
                      value: _TargetScope.all,
                      groupValue: _scope,
                      onChanged: (v) => setState(() => _scope = v!),
                      title: const Text(
                        '全店舗',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                    ),
                    // RadioListTile<_TargetScope>(
                    //   value: _TargetScope.tenantIds,
                    //   groupValue: _scope,
                    //   onChanged: (v) => setState(() => _scope = v!),
                    //   title: const Text(
                    //     '店舗IDを指定',
                    //     style: TextStyle(fontFamily: 'LINEseed'),
                    //   ),
                    //   subtitle: Column(
                    //     crossAxisAlignment: CrossAxisAlignment.start,
                    //     children: [
                    //       const SizedBox(height: 8),
                    //       TextField(
                    //         controller: _tenantIdsCtrl,
                    //         minLines: 2,
                    //         maxLines: 4,
                    //         enabled: _scope == _TargetScope.tenantIds,
                    //         style: const TextStyle(fontFamily: 'LINEseed'),
                    //         cursorColor: Colors.black,
                    //         decoration: _blackThickInput(
                    //           'カンマ / スペース / 改行区切りで入力',
                    //           hint: '例: tenA, tenB tenC',
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // ),
                    RadioListTile<_TargetScope>(
                      value: _TargetScope.selectByName,
                      groupValue: _scope,
                      onChanged: (v) => setState(() => _scope = v!),
                      title: const Text(
                        '店舗名で検索して選択',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                    ),
                    if (isSelect) ...[
                      const SizedBox(height: 8),
                      _buildSelectByNameSection(),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ===== 送信ボタン =====
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: _brandFilled,
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.black,
                            ),
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending ? '送信中…' : '配信する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
