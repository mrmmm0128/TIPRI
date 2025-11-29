import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourpay/appadmin/agent/contracts_list_for_agent.dart';
import 'package:yourpay/appadmin/agent/share/QR.dart';
import 'package:yourpay/appadmin/agent/agency_member_manage.dart';

enum _ConnectState { complete, processing, needAction, none }

class AgencyDetailPage extends StatefulWidget {
  final String agentId;
  final bool agent;

  const AgencyDetailPage({
    super.key,
    required this.agentId,
    required this.agent,
  });

  @override
  State<AgencyDetailPage> createState() => _AgencyDetailPageState();
}

class _AgencyDetailPageState extends State<AgencyDetailPage> {
  static const brandYellow = Color(0xFFFCC400);

  final TextEditingController _searchCtrl = TextEditingController();
  bool _onboardingBusy = false;
  Tri _fInitial = Tri.any;
  Tri _fSub = Tri.any;
  Tri _fConnect = Tri.any;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ===== レスポンシブ共通 =====
  double _hpad(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 480) return 12; // phone
    if (w < 840) return 16; // tablet / small window
    return 24; // desktop wide
  }

  // ===== 共通UI =====

  // ピル型チップ（黒枠 / ピル / 省略耐性）
  Widget _pillChip({
    required String text,
    required Color bg,
    Color fg = Colors.black,
    IconData? icon,
    bool bold = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: .2,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  // セクション見出し（左に太バー）
  Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) {
    final hp = _hpad(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
      child: Row(
        children: [
          Container(width: 6, height: 18, color: Colors.black),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ラベル:値（レスポンシブに幅可変）
  Widget _kv(BuildContext context, String k, String v) {
    final hp = _hpad(context);
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 520;
    final minKey = isNarrow ? 96.0 : (w < 840 ? 140.0 : 180.0);
    final maxKey = isNarrow ? 160.0 : (w < 840 ? 240.0 : 320.0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hp, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: minKey, maxWidth: maxKey),
            child: Text(k, style: const TextStyle(color: Colors.black54)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  // 3値チップ：太枠・アクティブはブランド黄・黒文字/アイコン・フル幅対応
  Widget _triFilterChip({
    required String label,
    required Tri value,
    required ValueChanged<Tri> onChanged,
  }) {
    const brandYellow = Color(0xFFFCC400);

    Tri next(Tri v) =>
        v == Tri.any ? Tri.yes : (v == Tri.yes ? Tri.no : Tri.any);
    String text(Tri v) => switch (v) {
      Tri.any => '$label: すべて',
      Tri.yes => '$label: あり',
      Tri.no => '$label: なし',
    };
    final isActive = value != Tri.any;

    return SizedBox(
      height: 40,
      width: double.infinity,
      child: Material(
        color: isActive ? Colors.black : brandYellow,
        shape: const StadiumBorder(
          side: BorderSide(color: Colors.black, width: 4),
        ),
        child: InkWell(
          onTap: () => onChanged(next(value)),
          customBorder: const StadiumBorder(),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    text(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 代理店ステータス日本語化
  (Color bg, IconData icon, String jp) _agencyStatusVisual(String raw) {
    final v = raw.toLowerCase();
    if (v == 'active') {
      return (brandYellow, Icons.check_circle, '有効');
    } else if (v == 'pending' || v == 'review' || v == 'awaiting') {
      return (const Color(0xFFFFE0B2), Icons.warning_amber_rounded, '確認中');
    } else if (v == 'suspended' || v == 'inactive' || v == 'disabled') {
      return (const Color(0xFFFFCDD2), Icons.block, '無効');
    }
    return (Colors.white, Icons.info_outline, raw);
  }

  // ===== Actions =====

  Future<void> _upsertConnectAndOnboardForAgency(BuildContext context) async {
    if (_onboardingBusy) return;
    setState(() => _onboardingBusy = true);
    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('upsertAgencyConnectedAccount');

      final res = await fn.call({
        'agentId': widget.agentId,
        'account': {'country': 'JP', 'tosAccepted': true},
      });

      final data = (res.data as Map).cast<String, dynamic>();
      final url = data['onboardingUrl'] as String?;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stripe接続情報更新')));

      if (url != null && url.isNotEmpty) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('処理に失敗しました：${e.code} ${e.message ?? ""}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('処理に失敗しました：$e')));
    } finally {
      if (mounted) setState(() => _onboardingBusy = false);
    }
  }

  Future<void> _openConnectPortal(BuildContext context) async {
    setState(() => _onboardingBusy = true);
    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createAgencyConnectLink'); // ← 環境に合わせて
      final res = await fn.call({'agentId': widget.agentId});
      final data = (res.data as Map).cast<String, dynamic>();
      final url = (data['url'] ?? '').toString();

      if (url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('リンクの取得に失敗しました')));
        return;
      }

      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('リンク作成に失敗：${e.code} ${e.message ?? ""}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('リンク作成に失敗：$e')));
    } finally {
      setState(() => _onboardingBusy = false);
    }
  }

  // disabled_reason を日本語ラベル & 状態・色・アイコンにマップ
  (String label, _ConnectState state, Color bg, IconData icon)
  _reasonToLabelAndState(String? reason) {
    final r = (reason ?? '').trim();

    // 空（理由なし）= 進行中ラベル
    if (r.isEmpty) {
      return (
        '処理中',
        _ConnectState.processing,
        const Color(0xFFBBDEFB),
        Icons.hourglass_top_rounded,
      );
    }

    // 期限切れ（唯一の「要対応」オレンジ）
    if (r.contains('requirements.past_due')) {
      return (
        '要対応',
        _ConnectState.needAction,
        const Color(0xFFFFE0B2),
        Icons.warning_amber_rounded,
      );
    }

    // 入力不足（Stripe 側の文言で出ることがある）
    if (r.contains('requirements.currently_due')) {
      return (
        '要対応',
        _ConnectState.needAction,
        const Color(0xFFFFE0B2),
        Icons.warning_amber_rounded,
      );
    }

    // 確認中
    if (r.contains('requirements.pending_verification')) {
      return (
        '審査中',
        _ConnectState.processing,
        const Color(0xFFBBDEFB),
        Icons.hourglass_top_rounded,
      );
    }

    // プラットフォーム都合の一時停止
    if (r == 'platform_paused') {
      return (
        '一時停止',
        _ConnectState.processing,
        const Color(0xFFBBDEFB),
        Icons.pause_circle_filled,
      );
    }

    // 審査中
    if (r == 'under_review') {
      return (
        '審査中',
        _ConnectState.processing,
        const Color(0xFFBBDEFB),
        Icons.assignment_turned_in,
      );
    }

    // リスティング（制限）
    if (r == 'listed') {
      return (
        '利用制限中',
        _ConnectState.processing,
        const Color(0xFFBBDEFB),
        Icons.privacy_tip,
      );
    }

    // 審査NG 系（rejected.*）
    if (r.startsWith('rejected')) {
      // 例: rejected.fraud / rejected.terms_of_service / rejected.other
      return (
        '要対応（利用不可: ${r.split('.').last}）',
        _ConnectState.needAction,
        const Color(0xFFFFCDD2),
        Icons.block,
      );
    }

    // それ以外は理由を添えた処理中
    return (
      '処理中（$r）',
      _ConnectState.processing,
      const Color(0xFFBBDEFB),
      Icons.info_outline,
    );
  }

  // ===== Connect ステータス判定（disabled_reason に応じて柔軟表示） =====
  (Color bg, IconData icon, String label, _ConnectState state)
  _connectOverallStatus({
    required bool chargesEnabled,
    required bool payoutsEnabled,
    required bool hasAccount,
    String? disabledReason,
  }) {
    // 完了
    if (hasAccount && chargesEnabled && payoutsEnabled) {
      return (brandYellow, Icons.check_circle, '接続完了', _ConnectState.complete);
    }

    // 進行中（アカウント作成済み or どちらか有効）→ 理由に応じて出し分け
    if (hasAccount || chargesEnabled || payoutsEnabled) {
      final (lbl, st, bg, icon) = _reasonToLabelAndState(disabledReason);
      return (bg, icon, lbl, st);
    }

    // 未接続
    return (const Color(0xFFE0E0E0), Icons.link_off, '未接続', _ConnectState.none);
  }

  Future<void> _setAgentPassword(
    BuildContext context,
    String code,
    String email,
  ) async {
    final pass1 = TextEditingController();
    final pass2 = TextEditingController();

    final ok = await showDialog<bool>(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 3),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: "LINEseed",
        ),
        contentTextStyle: const TextStyle(color: Colors.black),
        title: const Text('代理店用パスワード設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1つ目：ラベル短く＋ヘルパーで条件表示
              TextField(
                controller: pass1,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '新しいパスワード',
                  helperText: '8文字以上', // ← 別枠に明示
                  helperStyle: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'LINEseed',
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black, width: 3),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black, width: 3),
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              // 2つ目：こちらもラベル短く、補足はヘルパーで
              TextField(
                controller: pass2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '確認用パスワード',
                  helperText: '同じパスワードを入力してください',
                  helperStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'LINEseed',
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black, width: 3),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black, width: 3),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // まとめの注意を別行で（必要なら）
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '※ パスワードは8文字以上・確認用と同一である必要があります。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontFamily: 'LINEseed',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: brandYellow,
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('決定'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final p1 = pass1.text;
    final p2 = pass2.text;
    if (p1.length < 8 || p1 != p2) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('8文字以上・同一のパスワードを入力してください')));
      return;
    }

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('adminSetAgencyPassword');
      await fn.call({
        'agentId': widget.agentId,
        'password': p1,
        'login': code,
        'email': email,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'パスワードを設定しました',
            style: TextStyle(color: Colors.white, fontFamily: "LINEseed"),
          ),
          backgroundColor: brandYellow,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'システムエラーにより、パスワード設定に失敗しました',
            style: TextStyle(color: Colors.white, fontFamily: "LINEseed"),
          ),
          backgroundColor: brandYellow,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'システムエラーにより、パスワード設定に失敗しました',
            style: TextStyle(color: Colors.white, fontFamily: "LINEseed"),
          ),
          backgroundColor: brandYellow,
        ),
      );
    }
  }

  Future<void> _editAgent(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> current,
  ) async {
    final nameC = TextEditingController(
      text: (current['name'] ?? '').toString(),
    );
    final emailC = TextEditingController(
      text: (current['email'] ?? '').toString(),
    );
    final codeC = TextEditingController(
      text: (current['code'] ?? '').toString(),
    );
    final pctC = TextEditingController(
      text: ((current['commissionPercent'] ?? 0)).toString(),
    );
    String status = (current['status'] ?? 'active').toString();

    const brandYellow = Color(0xFFFCC400);

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // items と一致するように正規化
        status = switch (status) {
          'active' => 'active',
          'suspended' => 'suspended',
          _ => 'active',
        };

        // 共通デコレータ（白背景＋黒太枠）
        InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 3),
          ),
        );

        const double kStroke = 3.0; // 黒枠の太さ
        const double kRadius = 12.0; // 黒枠の角丸
        const double kInnerR = kRadius - kStroke; // 内側用の角丸

        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadius),
            side: const BorderSide(color: Colors.black, width: kStroke),
          ),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),

          // ===== タイトル（黄色エリアは黒枠の内側に 3px 余白＋ClipRRect） =====
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 上部の細いアクセントバー
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kStroke,
                  kStroke,
                  kStroke,
                  0,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(kInnerR),
                  ),
                  child: Container(height: 6, color: brandYellow),
                ),
              ),
              // タイトル帯
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kStroke,
                  0,
                  kStroke,
                  kStroke,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(kInnerR * 0),
                  ),
                  child: Container(
                    color: brandYellow,
                    padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '代理店情報を編集',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'LINEseed',
                              fontSize: 16,
                              height: 1.1,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'パスワード設定',
                          icon: const Icon(
                            Icons.key_outlined,
                            color: Colors.black,
                          ),
                          onPressed: () =>
                              _setAgentPassword(ctx, codeC.text, emailC.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ===== 本文 =====
          content: MediaQuery.removeViewInsets(
            context: ctx,
            removeBottom: true,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    !widget.agent
                        ? TextField(controller: nameC, decoration: deco('名称'))
                        : const SizedBox(height: 0),
                    const SizedBox(height: 8),
                    !widget.agent
                        ? TextField(controller: emailC, decoration: deco('メール'))
                        : const SizedBox(height: 0),
                    const SizedBox(height: 8),
                    !widget.agent
                        ? TextField(
                            controller: codeC,
                            decoration: deco('代理店コード'),
                          )
                        : const SizedBox(height: 0),
                    const SizedBox(height: 8),
                    !widget.agent
                        ? DropdownButtonFormField<String>(
                            value: status,
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('有効'),
                              ),
                              DropdownMenuItem(
                                value: 'suspended',
                                child: Text('無効'),
                              ),
                            ],
                            onChanged: (v) => status = (v ?? 'active'),
                            decoration: deco('ステータス'),
                            dropdownColor: Colors.white,
                          )
                        : const SizedBox(height: 0),
                  ],
                ),
              ),
            ),
          ),

          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: brandYellow,
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                side: const BorderSide(color: Colors.black, width: kStroke),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final pct = int.tryParse(pctC.text.trim());
    await ref.set({
      'name': nameC.text.trim(),
      'email': emailC.text.trim(),
      'code': codeC.text.trim(),
      if (pct != null) 'commissionPercent': pct,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('設定が完了しました', style: TextStyle(fontFamily: 'LINEseed')),
        backgroundColor: Color(0xFFFCC400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('agencies')
        .doc(widget.agentId);

    final hp = _hpad(context);
    print(widget.agent);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 53,
        titleSpacing: widget.agent ? 16 : 0,
        leadingWidth: widget.agent ? null : 44,
        leading: widget.agent
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                iconSize: 25,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text(
          '代理店詳細',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: !widget.agent, // （leading未指定時のみ効く）
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),

      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('読み込みエラー：${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final m = snap.data!.data() ?? {};
          final name = (m['name'] ?? '(名称未設定)').toString();
          final email = (m['email'] ?? '').toString();
          final code = (m['code'] ?? '').toString();

          final status = (m['status'] ?? 'active').toString();

          final (sBg, sIcon, sJp) = _agencyStatusVisual(status);

          final emailC = TextEditingController(
            text: (m['email'] ?? '').toString(),
          );
          final codeC = TextEditingController(
            text: (m['code'] ?? '').toString(),
          );

          // ======= フル幅 ListView =======
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: hp, vertical: 8),
            children: [
              // ヘッダ（名前）
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hp, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TipriQrButton(),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 8),

              _sectionTitle(context, '基本情報'),
              _kv(context, 'メール', email.isNotEmpty ? email : '—'),
              _kv(context, '代理店コード', code.isNotEmpty ? code : '—'),
              _kv(context, 'ステータス', sJp),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hp),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      // ① 既存の「編集」ボタン
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: Colors.black,
                          backgroundColor: brandYellow,
                        ),
                        onPressed: () => !widget.agent
                            ? _editAgent(context, ref, m)
                            : _setAgentPassword(
                                context,
                                codeC.text,
                                emailC.text,
                              ),
                        icon: const Icon(Icons.edit),
                        label: const Text('編集'),
                      ),

                      // ② 新規追加：メンバー管理ボタン
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.black, width: 3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AgencyMemberManagePage(
                                agentId: widget.agentId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.group),
                        label: const Text('メンバー管理'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),

              // ===== Connect / 入金口座 =====
              _sectionTitle(context, '入金・決済（Stripe Connect）'),
              Builder(
                builder: (ctx) {
                  final mm = snap.data!.data() ?? {};
                  final acctId = (mm['stripeAccountId'] ?? '').toString();
                  final connect =
                      (mm['connect'] as Map?)?.cast<String, dynamic>() ?? {};
                  final charges = connect['charges_enabled'] == true;
                  final payouts = connect['payouts_enabled'] == true;

                  // ★ 追加: disabled_reason を取得して渡す
                  final reqs =
                      (connect['requirements'] as Map?)
                          ?.cast<String, dynamic>() ??
                      {};
                  final disabledReason = (reqs['disabled_reason'] ?? '')
                      .toString();

                  final (cBg, cIcon, cLabel, cState) = _connectOverallStatus(
                    chargesEnabled: charges,
                    payoutsEnabled: payouts,
                    hasAccount: acctId.isNotEmpty,
                    disabledReason: disabledReason, // ← 渡す
                  );

                  final schedule =
                      (mm['payoutSchedule'] as Map?)?.cast<String, dynamic>() ??
                      {};
                  final anchor = schedule['monthly_anchor'] ?? 1;

                  // CTAテキスト
                  final String ctaText = switch (cState) {
                    _ConnectState.complete => '口座情報を確認', // Connectポータルへ
                    _ConnectState.processing => '審査状況を確認', // ポータルでステータス確認
                    _ConnectState.needAction => '口座設定の続き', // 要入力/不足項目の解消
                    _ConnectState.none => '口座設定を開始', // 新規作成開始
                  };

                  // CTAアクション
                  final VoidCallback? ctaAction = switch (cState) {
                    _ConnectState.complete =>
                      () => _onboardingBusy ? null : _openConnectPortal(ctx),
                    _ConnectState.processing =>
                      () => _onboardingBusy ? null : _openConnectPortal(ctx),
                    _ConnectState.needAction =>
                      _onboardingBusy
                          ? null
                          : () => _upsertConnectAndOnboardForAgency(ctx),
                    _ConnectState.none =>
                      _onboardingBusy
                          ? null
                          : () => _upsertConnectAndOnboardForAgency(ctx),
                  };

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: hp),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pillChip(
                          text: 'Stripe: $cLabel',
                          bg: cBg,
                          icon: cIcon,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '入金サイクル: 毎月$anchor日',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: brandYellow,
                              foregroundColor: Colors.black,
                              side: const BorderSide(
                                color: Colors.black,
                                width: 3,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onPressed: ctaAction,
                            child:
                                _onboardingBusy &&
                                    (cState != _ConnectState.complete)
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text('処理中…'),
                                    ],
                                  )
                                : Text(ctaText),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),
              const Divider(height: 1, color: Colors.black12),

              // ===== 契約店舗一覧 =====
              _sectionTitle(context, '契約店舗一覧'),
              // 検索 + フィルタ
              Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, 8),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final isWide = c.maxWidth >= 900;
                    const gap = 8.0;

                    final searchField = TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '店舗名で検索',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black, width: 4),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black, width: 4),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: searchField),
                          const SizedBox(width: gap),
                          Expanded(
                            child: _triFilterChip(
                              label: '初期費用',
                              value: _fInitial,
                              onChanged: (v) => setState(() => _fInitial = v),
                            ),
                          ),
                          const SizedBox(width: gap),
                          Expanded(
                            child: _triFilterChip(
                              label: 'サブスク',
                              value: _fSub,
                              onChanged: (v) => setState(() => _fSub = v),
                            ),
                          ),
                          const SizedBox(width: gap),
                          Expanded(
                            child: _triFilterChip(
                              label: 'Stripe',
                              value: _fConnect,
                              onChanged: (v) => setState(() => _fConnect = v),
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        searchField,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _triFilterChip(
                                label: '初期費用',
                                value: _fInitial,
                                onChanged: (v) => setState(() => _fInitial = v),
                              ),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              child: _triFilterChip(
                                label: 'サブスク',
                                value: _fSub,
                                onChanged: (v) => setState(() => _fSub = v),
                              ),
                            ),
                            const SizedBox(width: gap),
                            Expanded(
                              child: _triFilterChip(
                                label: 'Connect',
                                value: _fConnect,
                                onChanged: (v) => setState(() => _fConnect = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 店舗リスト
              ContractsListForAgent(
                agentId: widget.agentId,
                query: _searchCtrl.text,
                initialPaid: _fInitial,
                subActive: _fSub,
                connectCreated: _fConnect,
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
