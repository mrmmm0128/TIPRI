// ======= 店舗詳細（フル幅レスポンシブ / myCard不使用 / 旧表記維持） =======
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// import 'package:yourpay/appadmin/util.dart'; // 未使用なら削除OK
import 'package:yourpay/tenant/store_detail/tabs/store_qr_tab.dart';

enum _ChipKind { good, warn, bad }

class AgentMember {
  AgentMember({required this.name, required this.ref});

  final String name;
  final DocumentReference<Map<String, dynamic>> ref;
}

/// --------------------
/// 統合済みの課金情報モデル
/// --------------------
class _BillingInfo {
  _BillingInfo({
    required this.initStatus, // 'paid' | 'checkout_open' | 'none' | その他
    required this.subscriptionStatus, // 'active' | 'trialing' | 'past_due' | ...
    required this.subscriptionPlan, // プラン名 or '選択なし'
    required this.isTrialing,
    required this.trialEnd,
    required this.nextPaymentAt,
    required this.overdue,
    required this.chargesEnabled,
  });

  final String initStatus;
  final String subscriptionStatus;
  final String subscriptionPlan;
  final bool isTrialing;
  final DateTime? trialEnd;
  final DateTime? nextPaymentAt;
  final bool overdue;
  final bool chargesEnabled;
}

class AdminTenantDetailPage extends StatelessWidget {
  final String ownerUid;
  final String tenantId;
  final String tenantName;
  final String? agentId;

  const AdminTenantDetailPage({
    super.key,
    required this.ownerUid,
    required this.tenantId,
    required this.tenantName,
    this.agentId,
  });

  // ========== brand / helpers ==========
  static const brandYellow = Color(0xFFFCC400);

  // 横パディング（ブレークポイントで調整）
  double _hpad(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 480) return 12; // phone
    if (w < 840) return 16; // tablet / small window
    return 24; // desktop wide
  }

  String _ymd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  String _ymdhm(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _yen(int v) => '¥${v.toString()}';

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is double)
      return DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
    return null;
  }

  // ステータスチップ（修正前の色・表記復帰用 / レスポンシブ拡張）
  Widget _statusChip(
    String label,
    _ChipKind kind, {
    int maxLines = 2, // ← 追加: スマホで2行まで許可
    bool fullWidth = false, // ← 追加: スマホでフル幅に
  }) {
    final color = switch (kind) {
      _ChipKind.good => const Color(0xFF1B5E20), // 深緑
      _ChipKind.warn => const Color(0xFFB26A00), // 濃オレンジ
      _ChipKind.bad => const Color(0xFFB00020), // 濃赤
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: maxLines, // 2 以上で呼ぶと折り返し候補
        softWrap: true, // 常に許可してOK
        overflow: TextOverflow.ellipsis, // 溢れたら省略記号（2行でも有効）
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
          height: 1.2,
        ),
      ),
    );

    // スマホ時はフル幅で置く
    return fullWidth ? SizedBox(width: double.infinity, child: chip) : chip;
  }

  // セクション見出し（左に太バー）— パディングは画面幅に追従
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

  // ラベル:値（レスポンシブ幅可変）— キー列幅もブレークポイントで伸縮
  Widget _kv(BuildContext context, String k, String v) {
    final hp = _hpad(context);
    final w = MediaQuery.of(context).size.width;
    final bool isNarrow = w < 520;
    final double minKey = isNarrow ? 96 : (w < 840 ? 140 : 180);
    final double maxKey = isNarrow ? 160 : (w < 840 ? 240 : 320);

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

  // サブスク状態：日本語化
  String _jpSubStatus(String s) {
    switch (s.toLowerCase()) {
      case 'active':
        return '有効';
      case 'trialing':
        return 'トライアル中';
      case 'past_due':
        return '支払い遅延';
      case 'unpaid':
        return '未払い';
      case 'canceled':
        return 'キャンセル';
      case 'incomplete':
        return '未完了';
      case 'incomplete_expired':
        return '期限切れ（未完了）';
      case 'paused':
        return '一時停止';
      case 'inactive':
      case 'nonactive':
      case 'non_active':
        return '無効';
      default:
        return s.isEmpty ? '' : s;
    }
  }

  // Connectまとめステータス（chargesEnabled / hasAccount）
  (Color bg, IconData icon, String label) _connectOverallStatus({
    required bool chargesEnabled,
    required bool hasAccount,
  }) {
    if (chargesEnabled && hasAccount) {
      return (brandYellow, Icons.check_circle, '接続完了');
    } else if (chargesEnabled || hasAccount) {
      return (const Color(0xFFFFE0B2), Icons.warning_amber_rounded, '要対応');
    } else {
      return (Colors.white, Icons.info_outline, '未接続');
    }
  }

  // ===== 連絡先編集 =====
  Future<void> _openEditContactSheet(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> tenantRef, {
    String? currentPhone,
    String? currentMemo,
  }) async {
    final phoneCtrl = TextEditingController(text: currentPhone ?? '');
    final memoCtrl = TextEditingController(text: currentMemo ?? '');
    bool saving = false;

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
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                Future<void> save() async {
                  if (saving) return;
                  setLocal(() => saving = true);
                  try {
                    final phone = phoneCtrl.text.trim();
                    final memo = memoCtrl.text.trim();
                    await tenantRef.set({
                      'contact': {
                        'phone': phone.isEmpty ? FieldValue.delete() : phone,
                        'memo': memo.isEmpty ? FieldValue.delete() : memo,
                      },
                      'contactUpdatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('連絡先を保存しました')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
                    }
                  } finally {
                    setLocal(() => saving = false);
                  }
                }

                return Padding(
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
                            '連絡先を編集',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '電話番号（任意）',
                          hintText: '例: 03-1234-5678 / 090-1234-5678',
                          prefixIcon: Icon(Icons.phone_outlined),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 3,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: memoCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'メモ（任意）',
                          hintText: '店舗メモ・注意事項など',
                          prefixIcon: Icon(Icons.notes_outlined),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 3,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
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
                              ),
                              onPressed: saving ? null : save,
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('保存'),
                            ),
                          ),
                        ],
                      ),
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

  // 初期費用・サブスク・Connect（chargesEnabled）を統合
  _BillingInfo _parseBilling(Map<String, dynamic> m) {
    final dynamic init1 = (m['initialFee'] as Map?)?['status'];
    final dynamic init2 = (m['billing'] as Map?)?['initialFee']?['status'];
    final String initStatus = ((init1 ?? init2) ?? 'none').toString();

    final sub = (m['subscription'] as Map?) ?? const {};
    final String subStatus = (sub['status'] ?? '').toString();
    final String subPlan = (sub['plan'] ?? '選択なし').toString();

    final trialMap = (sub['trial'] as Map?) ?? const {};
    final bool isTrialing =
        (trialMap['status'] == 'trialing') || (subStatus == 'trialing');

    final DateTime? trialEnd =
        _toDate(sub['trialEnd']) ??
        _toDate(sub['trial_end']) ??
        _toDate(sub['currentPeriodEnd']);

    final DateTime? nextAt =
        _toDate(sub['nextPaymentAt']) ?? _toDate(sub['currentPeriodEnd']);

    final bool overdue =
        (sub['overdue'] == true) ||
        subStatus == 'past_due' ||
        subStatus == 'unpaid';

    final bool chargesEnabled = m['connect']?['charges_enabled'] == true;

    return _BillingInfo(
      initStatus: initStatus,
      subscriptionStatus: subStatus,
      subscriptionPlan: subPlan,
      isTrialing: isTrialing,
      trialEnd: trialEnd,
      nextPaymentAt: nextAt,
      overdue: overdue,
      chargesEnabled: chargesEnabled,
    );
  }

  void _openQrPoster(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('QRポスター作成')),
          body: StoreQrTab(
            tenantId: tenantId,
            tenantName: tenantName,
            ownerId: ownerUid,
            agency: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openEditAgentPeopleSheet(
    BuildContext context, {
    required DocumentReference<Map<String, dynamic>> tenantIndexRef,
    required String tenantId,
    required List<AgentMember> allMembers,
    required List<String> initialSelectedNames,
  }) async {
    final selected = initialSelectedNames.toSet();
    final initialSelected = initialSelectedNames.toSet();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> save() async {
              if (saving) return;
              setLocal(() => saving = true);

              try {
                // ---------- ① tenantIndex.agent_people に保存 ----------
                await tenantIndexRef.set({
                  'agent_people': selected.toList(),
                  'agentPeopleUpdatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                // ---------- ② agents/{agentId}/members 更新 ----------
                // 追加された名前 / 外された名前を差分で計算
                final added = selected.difference(initialSelected);
                final removed = initialSelected.difference(selected);

                // name -> AgentMember のインデックス
                final byName = {for (final m in allMembers) m.name: m};

                final writes = <Future<void>>[];

                // 追加された人には tenants に tenantId を Union
                for (final name in added) {
                  final m = byName[name];
                  if (m == null) continue;
                  writes.add(
                    m.ref.set({
                      'tenants': FieldValue.arrayUnion([tenantId]),
                    }, SetOptions(merge: true)),
                  );
                }

                // 外された人には tenants から tenantId を Remove
                for (final name in removed) {
                  final m = byName[name];
                  if (m == null) continue;
                  writes.add(
                    m.ref.set({
                      'tenants': FieldValue.arrayRemove([tenantId]),
                    }, SetOptions(merge: true)),
                  );
                }

                // ---------- ③ agencies/{agentId}/contracts 側にも同じ情報を反映 ----------
                // この代理店の contracts コレクションから、該当 tenantId の契約を取得
                final contractsSnap = await FirebaseFirestore.instance
                    .collection('agencies')
                    .doc(agentId) // ★ 外側 or 引数で受け取っている agentId
                    .collection('contracts')
                    .where('tenantId', isEqualTo: tenantId) // ★ このテナントの契約だけ
                    .get();

                for (final doc in contractsSnap.docs) {
                  writes.add(
                    doc.reference.set({
                      'agent_people': selected.toList(),
                      'agentPeopleUpdatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true)),
                  );
                }

                // ---------- batched 実行 ----------
                await Future.wait(writes);

                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('代理店メンバーを保存しました')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
                }
              } finally {
                setLocal(() => saving = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
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
                          '代理店メンバーを紐づけ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (allMembers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('候補メンバーが登録されていません'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allMembers.length,
                          itemBuilder: (ctx, i) {
                            final m = allMembers[i];
                            final checked = selected.contains(m.name);
                            return CheckboxListTile(
                              title: Text(m.name),
                              value: checked,
                              onChanged: (v) {
                                setLocal(() {
                                  if (v == true) {
                                    selected.add(m.name);
                                  } else {
                                    selected.remove(m.name);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(saving ? '保存中…' : '保存する'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFCC400),
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black, width: 3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<AgentMember>> _fetchAgentMembersByCode({
    required String agentId,
  }) async {
    try {
      // agencies/{agentId}/members から取得
      final agentDocRef = FirebaseFirestore.instance
          .collection('agencies')
          .doc(agentId);

      final memSnap = await agentDocRef.collection('members').get();

      return memSnap.docs.map((d) {
        final data = d.data();
        final name = (data['name'] ?? d.id).toString(); // フィールド名は要調整
        return AgentMember(name: name, ref: d.reference);
      }).toList();
    } catch (e) {
      debugPrint('Failed to fetch agent members: $e');
      return <AgentMember>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantRef = FirebaseFirestore.instance
        .collection(ownerUid)
        .doc(tenantId);
    final tenantIndexRef = FirebaseFirestore.instance
        .collection('tenantIndex')
        .doc(tenantId);

    final hp = _hpad(context); // 先に算出

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 53,
        titleSpacing: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: 25,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '店舗詳細',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: tenantRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('読み込みエラー：${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final m = snap.data!.data() ?? const <String, dynamic>{};
          final plan = (m['subscription']?['plan'] ?? '').toString();
          final status = (m['status'] ?? '').toString();
          final creatorEmailFromDoc =
              (m['creatorEmail'] ?? m['createdBy']?['email'])?.toString();
          final connect =
              (m['connect'] as Map?)?.cast<String, dynamic>() ?? const {};
          final chargesEnabled = connect['charges_enabled'] == true;
          final accountId = (m['stripeAccountId'] ?? '').toString();

          final (_bg, _icon, _label) = _connectOverallStatus(
            chargesEnabled: chargesEnabled,
            hasAccount: accountId.isNotEmpty,
          );

          final payoutSchedule =
              (m['payoutSchedule'] as Map?)?.cast<String, dynamic>() ??
              const {};
          final anchor = payoutSchedule['monthly_anchor'] ?? 1;

          final bill = _parseBilling(m);

          // ======= ここからフル幅 ListView（Align/ConstrainedBox は使わない） =======
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: hp, vertical: 8),
            children: [
              // ===== ヘッダ（店舗名） =====
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hp, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tenantName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 8),

              // ===== 基本情報 =====
              _sectionTitle(
                context,
                '基本情報',
                trailing: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: brandYellow,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _openQrPoster(context),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('QRポスターダウンロード'),
                ),
              ),
              _kv(context, '名前', tenantName),
              _kv(context, 'プラン', plan.isEmpty ? '—' : plan),
              _kv(
                context,
                'ステータス',
                status.isEmpty
                    ? '—'
                    : status == "active"
                    ? "有効"
                    : "無効",
              ),
              _kv(context, 'Stripe', chargesEnabled ? '有効' : '未登録'),
              if (creatorEmailFromDoc != null && creatorEmailFromDoc.isNotEmpty)
                _kv(context, '作成者メール', creatorEmailFromDoc)
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(ownerUid)
                      .snapshots(),
                  builder: (context, userSnap) {
                    final mail =
                        userSnap.data?.data()?['email']?.toString() ?? '—';
                    return _kv(context, 'Creator Email', mail);
                  },
                ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),

              // ===== 入金・決済（Connect） ※使う場合はコメント解除 =====
              // _sectionTitle(context, '入金・決済（Stripe Connect）'),
              // Padding(
              //   padding: EdgeInsets.symmetric(horizontal: hp),
              //   child: Column(
              //     crossAxisAlignment: CrossAxisAlignment.start,
              //     children: [
              //       // ここは任意のチップUIに差し替え可
              //       Container(
              //         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              //         decoration: BoxDecoration(
              //           color: _bg,
              //           borderRadius: BorderRadius.circular(999),
              //           border: Border.all(color: Colors.black, width: 2),
              //         ),
              //         child: Row(
              //           mainAxisSize: MainAxisSize.min,
              //           children: [
              //             Icon(_icon, size: 14, color: Colors.black),
              //             const SizedBox(width: 6),
              //             Text('Connect: $_label', style: const TextStyle(fontWeight: FontWeight.w700)),
              //           ],
              //         ),
              //       ),
              //       const SizedBox(height: 6),
              //       Text('入金サイクル: 毎月$anchor日', style: const TextStyle(color: Colors.black54)),
              //       if (accountId.isNotEmpty) ...[
              //         const SizedBox(height: 6),
              //         Text('アカウントID: $accountId', style: const TextStyle(color: Colors.black54)),
              //       ],
              //     ],
              //   ),
              // ),

              // const SizedBox(height: 12),
              // const Divider(height: 1, color: Colors.black12),

              // ===== 課金・トライアル状況（旧スタイル） =====
              _sectionTitle(context, '課金・トライアル状況'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hp),
                child: Builder(
                  builder: (context) {
                    final b = bill;

                    // 初期費用（旧表記）
                    late String initLabel;
                    late _ChipKind initKind;
                    if (b.isTrialing && b.trialEnd != null) {
                      initLabel = '初期費用 ${_ymd(b.trialEnd!)} 支払予定';
                      initKind = _ChipKind.warn;
                    } else if (b.initStatus == 'paid') {
                      initLabel = '初期費用 済';
                      initKind = _ChipKind.good;
                    } else if (b.initStatus == 'checkout_open') {
                      initLabel = '初期費用 決済中';
                      initKind = _ChipKind.warn;
                    } else {
                      initLabel = '初期費用 未払い';
                      initKind = _ChipKind.bad;
                    }

                    // サブスク（旧表記）
                    final subLabel =
                        'サブスク: '
                        '${b.subscriptionPlan.isEmpty ? '未選択' : b.subscriptionPlan} '
                        '${_jpSubStatus(b.subscriptionStatus)}'
                        '${b.nextPaymentAt != null && _jpSubStatus(b.subscriptionStatus) != "無効" ? '・次回請求: ${_ymdhm(b.nextPaymentAt!)}' : ''}'
                        '${b.overdue ? '・未払い' : ''}';

                    final _ChipKind subKind = b.overdue
                        ? _ChipKind.bad
                        : ((b.subscriptionStatus == 'active' ||
                                  b.subscriptionStatus == 'trialing')
                              ? _ChipKind.good
                              : _ChipKind.bad);

                    // Connect（良/悪チップ）
                    final bool connectOk = b.chargesEnabled;
                    final connectLabel = connectOk
                        ? 'Stripe: 登録済'
                        : 'Stripe: 未登録';
                    final _ChipKind connectKind = connectOk
                        ? _ChipKind.good
                        : _ChipKind.bad;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _statusChip(initLabel, initKind),
                            _statusChip(subLabel, subKind),
                            _statusChip(connectLabel, connectKind),
                          ],
                        ),
                        if (b.isTrialing) ...[
                          const SizedBox(height: 8),
                          Text(
                            'トライアル終了日: ${b.trialEnd == null ? '—' : _ymd(b.trialEnd!)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),

              // ===== 連絡先 =====
              _sectionTitle(
                context,
                '連絡先',
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: Colors.black,
                    backgroundColor: brandYellow,
                  ),
                  onPressed: () => _openEditContactSheet(
                    context,
                    tenantRef,
                    currentPhone: (m['contact']?['phone'] ?? '').toString(),
                    currentMemo: (m['contact']?['memo'] ?? '').toString(),
                  ),
                  icon: const Icon(Icons.edit),
                  label: const Text('編集'),
                ),
              ),
              Builder(
                builder: (_) {
                  final contact =
                      (m['contact'] as Map?)?.cast<String, dynamic>() ??
                      const {};
                  final phone = (contact['phone'] as String?) ?? '';
                  final memo = (contact['memo'] as String?) ?? '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv(context, '電話番号', phone.isEmpty ? '' : phone),
                      _kv(context, 'メモ', memo.isEmpty ? '' : memo),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),
              // ===== 代理店担当（tenantIndex.agent_people） =====
              _sectionTitle(
                context,
                '担当者',
                trailing: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    foregroundColor: Colors.black,
                    backgroundColor: brandYellow,
                  ),
                  onPressed: () async {
                    // 1) 現在の agent_people を取得
                    // tenantIndex の参照
                    final tenantIndexRef = FirebaseFirestore.instance
                        .collection('tenantIndex')
                        .doc(tenantId);

                    // 1) 現在の agent_people を取得
                    final idxSnap = await tenantIndexRef.get();
                    final data = idxSnap.data() ?? <String, dynamic>{};
                    final rawList = (data['agent_people'] as List?) ?? const [];
                    final currentNames = rawList
                        .map((e) => e.toString())
                        .toList();

                    // 2) 代理店メンバー候補（agents/{code==agentId}/members）
                    final members = await _fetchAgentMembersByCode(
                      agentId: agentId ?? "",
                    );

                    // ignore: use_build_context_synchronously
                    await _openEditAgentPeopleSheet(
                      context,
                      tenantIndexRef: tenantIndexRef,
                      tenantId: tenantId,
                      allMembers: members,
                      initialSelectedNames: currentNames,
                    );
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('編集'),
                ),
              ),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: tenantIndexRef.snapshots(),
                builder: (context, idxSnap) {
                  final data = idxSnap.data?.data() ?? <String, dynamic>{};
                  final rawList = (data['agent_people'] as List?) ?? const [];
                  final names = rawList.map((e) => e.toString()).toList();

                  final display = names.isEmpty ? '—' : names.join('、');

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_kv(context, '担当者', display)],
                  );
                },
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),

              // ===== 直近のチップ =====
              _sectionTitle(context, '直近のチップ（50件）'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: tenantRef
                    .collection('tips')
                    .where('status', isEqualTo: 'succeeded')
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, tipsSnap) {
                  final docs = tipsSnap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: hp,
                        vertical: 8,
                      ),
                      child: const Text('データがありません'),
                    );
                  }
                  return Column(
                    children: docs.map((d) {
                      final m = d.data();
                      final amount = (m['amount'] as num?)?.toInt() ?? 0;
                      final emp = (m['employeeName'] ?? 'スタッフ').toString();
                      final ts = m['createdAt'];
                      final when = (ts is Timestamp) ? ts.toDate() : null;
                      return ListTile(
                        dense: true,
                        title: Text('${_yen(amount)} / $emp'),
                        subtitle: Text(when == null ? '—' : _ymdhm(when)),
                        trailing: Text(
                          (m['currency'] ?? 'JPY').toString().toUpperCase(),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: hp),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
