import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yourpay/appadmin/admin_dashboard_screen.dart';
import 'package:yourpay/appadmin/tenant/tenant_detail.dart';
import 'package:yourpay/appadmin/tenant/tenant_tile.dart';
import 'package:yourpay/appadmin/util.dart';

class TenantsListView extends StatelessWidget {
  final String query;
  final bool filterActiveOnly;
  final bool filterChargesEnabledOnly;
  final SortBy sortBy;
  final DateTime? rangeStart;
  final DateTime? rangeEndEx;

  // ★ 追加: フィルタ条件
  final Tri initialPaid; // 初期費用 status == 'paid'
  final Tri subActive; // subscription.status in {active, trialing}
  final Tri connectCreated; // connect.charges_enabled == true

  final Future<Revenue> Function({
    required String tenantId,
    required String ownerUid,
  })
  loadRevenueForTenant;

  final String Function(int) yen;
  final String Function(DateTime) ymd;

  const TenantsListView({
    super.key,
    required this.query,
    required this.filterActiveOnly,
    required this.filterChargesEnabledOnly,
    required this.sortBy,
    required this.rangeStart,
    required this.rangeEndEx,
    required this.loadRevenueForTenant,
    required this.yen,
    required this.ymd,
    this.initialPaid = Tri.any,
    this.subActive = Tri.any,
    this.connectCreated = Tri.any,
  });

  @override
  Widget build(BuildContext context) {
    // 1) tenantIndex を購読して ownerUid/tenantId ペア取得
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('tenantIndex').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('読込エラー: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final pairs = <({String ownerUid, String tenantId})>[];
        for (final d in snap.data!.docs) {
          final uid = d.data()['uid'];
          if (uid is String && uid.isNotEmpty) {
            pairs.add((ownerUid: uid, tenantId: d.id));
          }
        }
        if (pairs.isEmpty) {
          return const Center(child: Text('店舗がありません'));
        }

        // 2) 各オーナー配下の本体ドキュメントを get
        return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
          future: Future.wait(
            pairs.map(
              (p) => FirebaseFirestore.instance
                  .collection(p.ownerUid)
                  .doc(p.tenantId)
                  .get(),
            ),
          ),
          builder: (context, f) {
            if (f.hasError) {
              return Center(child: Text('読込エラー: ${f.error}'));
            }
            if (f.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final rows = <_Row>[];
            for (var i = 0; i < pairs.length; i++) {
              final snap = f.data![i];
              if (!snap.exists) continue;
              final p = pairs[i];
              rows.add(
                _Row(
                  ownerUid: p.ownerUid,
                  tenantId: p.tenantId,
                  data: snap.data() ?? {},
                ),
              );
            }

            // ===== ヘルパ =====
            String _s(dynamic v) => v == null ? '' : v.toString();
            String _nonEmptyOr(dynamic v, String fallback) {
              final s = _s(v).trim();
              return s.isEmpty ? fallback : s;
            }

            Timestamp? _ts(dynamic v) => v is Timestamp ? v : null;

            bool _chargesEnabledOf(Map<String, dynamic> m) =>
                (m['connect'] is Map) &&
                (((m['connect'] as Map)['charges_enabled']) == true);

            String _initialStatusOf(Map<String, dynamic> m) {
              final a = (m['initialFee'] is Map)
                  ? (m['initialFee'] as Map)['status']
                  : null;
              final b =
                  (m['billing'] is Map &&
                      (m['billing'] as Map)['initialFee'] is Map)
                  ? ((m['billing'] as Map)['initialFee'] as Map)['status']
                  : null;
              return _s(a ?? b).trim().isEmpty ? 'none' : _s(a ?? b);
            }

            String _subStatusOf(Map<String, dynamic> m) {
              final sub = (m['subscription'] is Map)
                  ? (m['subscription'] as Map)
                  : const <String, dynamic>{};
              return _s(sub['status']).trim();
            }

            bool _isSubActive(Map<String, dynamic> m) {
              final st = _subStatusOf(m);
              return st == 'active' || st == 'trialing';
            }

            // 3) クライアント側で検索・既存フィルタ
            var filtered = rows.where((r) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              final name = _s(r.data['name']).toLowerCase();
              final id = r.tenantId.toLowerCase();
              final owner = r.ownerUid.toLowerCase();
              return name.contains(q) || id.contains(q) || owner.contains(q);
            }).toList();

            if (filterActiveOnly) {
              filtered = filtered
                  .where((r) => _s(r.data['status']) == 'active')
                  .toList();
            }
            if (filterChargesEnabledOnly) {
              filtered = filtered
                  .where((r) => _chargesEnabledOf(r.data))
                  .toList();
            }

            // ★ 4) 三値フィルタの適用
            if (initialPaid != Tri.any) {
              filtered = filtered.where((r) {
                final paid = _initialStatusOf(r.data) == 'paid';
                return initialPaid == Tri.yes ? paid : !paid;
              }).toList();
            }
            if (subActive != Tri.any) {
              filtered = filtered.where((r) {
                final ok = _isSubActive(r.data);
                return subActive == Tri.yes ? ok : !ok;
              }).toList();
            }
            if (connectCreated != Tri.any) {
              filtered = filtered.where((r) {
                final ok = _chargesEnabledOf(r.data);
                return connectCreated == Tri.yes ? ok : !ok;
              }).toList();
            }

            // 5) ソート
            if (sortBy == SortBy.nameAsc) {
              filtered.sort(
                (a, b) => _s(a.data['name']).compareTo(_s(b.data['name'])),
              );
            } else if (sortBy == SortBy.createdDesc) {
              filtered.sort((a, b) {
                final da =
                    _ts(a.data['createdAt'])?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final db =
                    _ts(b.data['createdAt'])?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return db.compareTo(da);
              });
            } else if (sortBy == SortBy.revenueDesc) {
              // 売上は描画時にロード（必要なら後段で再整列）
            }

            if (filtered.isEmpty) {
              return const Center(child: Text('条件に一致する店舗がありません'));
            }

            // 6) リスト表示
            return ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.black),
              itemBuilder: (_, i) {
                final r = filtered[i];
                final m = r.data;

                final name = _nonEmptyOr(m['name'], '');
                final status = _nonEmptyOr(m['status'], '');
                final createdAt = _ts(m['createdAt'])?.toDate();
                final chargesEnabled = _chargesEnabledOf(m);

                final sub = (m['subscription'] is Map)
                    ? (m['subscription'] as Map)
                    : const <String, dynamic>{};
                final subStatus = _nonEmptyOr(sub['status'], '');
                final subPlan = _nonEmptyOr(sub['plan'], '');
                final nextRaw = sub['nextPaymentAt'] ?? sub['currentPeriodEnd'];
                final nextAt = _ts(nextRaw)?.toDate();
                final overdue =
                    (sub['overdue'] == true) ||
                    subStatus == 'past_due' ||
                    subStatus == 'unpaid';

                return TenantTile(
                  tenantId: r.tenantId,
                  ownerUid: r.ownerUid,
                  name: name,
                  status: status,
                  plan: subPlan,
                  chargesEnabled: chargesEnabled,
                  createdAt: createdAt,
                  download: m['download'],
                  rangeLabel: (rangeStart != null && rangeEndEx != null)
                      ? '${ymd(rangeStart!)} 〜 ${ymd(rangeEndEx!.subtract(const Duration(days: 1)))}'
                      : '期間未設定',
                  loadRevenue: () => loadRevenueForTenant(
                    tenantId: r.tenantId,
                    ownerUid: r.ownerUid,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminTenantDetailPage(
                          ownerUid: r.ownerUid,
                          tenantId: r.tenantId,
                          tenantName: name,
                        ),
                      ),
                    );
                  },
                  yen: yen,
                  subPlan: subPlan,
                  subStatus: subStatus,
                  subOverdue: overdue,
                  subNextPaymentAt: nextAt,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Row {
  final String ownerUid;
  final String tenantId;
  final Map<String, dynamic> data;
  _Row({required this.ownerUid, required this.tenantId, required this.data});
}
