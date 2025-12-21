import 'package:flutter/material.dart';

class CardShellHome extends StatelessWidget {
  final Widget child;
  const CardShellHome({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final pad = w < 600 ? 9.0 : 16.0;

    return Container(
      margin: const EdgeInsets.all(3),
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),

        border: Border.all(width: 3, color: Colors.black),
        // boxShadow: const [
        //   // 全方向に広がる柔らかい影
        //   BoxShadow(
        //     color: Color(0x1A000000), // 黒10%くらい
        //     blurRadius: 16,
        //     spreadRadius: 2, // ★ 影を全方向に“にじませる”
        //     offset: Offset(0, 0), // ★ 0 にして全方向へ
        //   ),
        // ],
      ),
      child: child,
    );
  }
}

/// 白カード＋影（ネイティブ感のある入れ物）
class CardShell extends StatelessWidget {
  final Widget child;
  const CardShell({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    // 画面幅に応じて内側の余白を調整
    final w = MediaQuery.of(context).size.width;
    final pad = w < 600 ? 12.0 : 16.0;

    return Container(
      margin: const EdgeInsets.all(6), // 枠が太い分、少しだけ広めに
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // border: Border.all(
        //   color: Colors.black, // ★ 黒
        //   width: 3, // ★ 太枠（お好みで 4〜8 に）
        // ),
        boxShadow: const [
          // 枠が目立つので影は控えめ（不要なら消してOK）
          BoxShadow(
            color: Color.fromARGB(19, 14, 14, 14), // 黒 8% くらい
            blurRadius: 8,
            offset: Offset(4, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PlanPicker extends StatefulWidget {
  final String selected; // 'A' | 'B' | 'C'
  final ValueChanged<String> onChanged;

  const PlanPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<PlanPicker> {
  @override
  Widget build(BuildContext context) {
    // 画面高さを基準に、カードの最小/最大高さをブレークポイント別に調整
    final h = MediaQuery.of(context).size.height;

    // 11/29モリタ変更　プラン改定に伴いチップ手数料の変更＆プランBのコメントアウト
    final plans = <PlanDef>[
      PlanDef(
        code: 'A',
        title: 'Aプラン',
        monthly: 0,
        feePct: 50,
        features: const ['決済手数料50%'],
      ),
      // PlanDef(
      //   code: 'B',
      //   title: 'Bプラン',
      //   monthly: 3980,
      //   feePct: 25,
      //   features: const ['決済手数料25%', '公式LINEリンクの掲載', 'チップとともにコメントの送信'],
      // ),
      PlanDef(
        code: 'B',
        title: 'Bプラン',
        monthly: 9800,
        feePct: 30,
        features: const [
          '決済手数料30%',
          '公式LINEリンクの掲載',
          'チップとともにコメントの送信',
          'Googleレビュー導線の設置',
          'オリジナルポスター作成',
          'お客様への感謝動画',
          'サブスクリプションチップ対応',
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;

        // ===== ブレークポイント =====
        // <600: 1カラム（スマホ）
        // 600-899: 2カラム（タブレット縦/小さめ）
        // >=900: 3カラム（タブレット横/デスクトップ）
        final int crossAxisCount = w < 600 ? 1 : (w < 900 ? 2 : 2);

        // 高さはブレークポイントごとに少し変える
        final double tileHeight = () {
          if (crossAxisCount == 1) {
            // スマホはやや高めに（スクロール配慮）
            return (h * 0.28).clamp(220.0, 460.0).toDouble();
          } else if (crossAxisCount == 2) {
            return (h * 0.26).clamp(220.0, 420.0).toDouble();
          } else {
            return (h * 0.24).clamp(220.0, 380.0).toDouble();
          }
        }();

        // // childAspectRatio は「幅/高さ」
        // // 横に並ぶほど 1.0 付近、縦並びはやや縦長に
        // final double childAspectRatio = () {
        //   if (crossAxisCount == 1) return 16 / 12; // 少し横長に
        //   if (crossAxisCount == 2) return 16 / 12;
        //   return 16 / 12;
        // }();
        // childAspectRatio は「幅/高さ」
        // 値を大きくすると縦が低くなる
        final double childAspectRatio = () {
          if (crossAxisCount == 1) return 1.5; // スマホ：少し縦長
          if (crossAxisCount == 2) return 2.1; // タブレット/PC：かなり横長にして高さ↓
          return 2.4; // 3列になったときはさらに平たく
        }();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: plans.length,
          itemBuilder: (_, i) {
            final p = plans[i];
            return _PlanTile(
              plan: p,
              selected: widget.selected == p.code,
              onTap: () => widget.onChanged(p.code),
              height: tileHeight,
            );
          },
        );
      },
    );
  }
}

class PlanChip extends StatelessWidget {
  final String label;
  final bool dark;
  const PlanChip({required this.label, this.dark = false, super.key});
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final padH = w < 600 ? 8.0 : 10.0;
    final padV = w < 600 ? 4.0 : 6.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: Color(0xFFFCC400),

        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black, width: 3.0),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: w < 360 ? 12 : 14,
        ),
      ),
    );
  }
}

class PlanDef {
  final String code;
  final String title;
  final int monthly;
  final int feePct;
  final List<String> features;
  PlanDef({
    required this.code,
    required this.title,
    required this.monthly,
    required this.feePct,
    required this.features,
  });
}

class _PlanTile extends StatelessWidget {
  final PlanDef plan;
  final bool selected;
  final VoidCallback onTap;

  /// 全カードを同じ高さにしたいときに指定（例: 220〜460くらい）
  final double height;

  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final baseFg = selected ? Colors.white : Colors.black;
    final subFg = selected ? Colors.white70 : Colors.black;
    final w = MediaQuery.of(context).size.width;
    final titleSize = w < 360 ? 15.0 : 16.0;
    final priceSize = w < 360 ? 14.0 : 16.0;

    final tile = Material(
      color: selected ? Colors.black : Colors.black12,

      // ★ 真っ黒キープ：影＆サーフェスティントを無効化
      elevation: 0,
      surfaceTintColor: Colors.transparent,

      // ★ どんなときでも真っ黒の枠線（幅3）
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF000000), width: 3),
      ),
      clipBehavior: Clip.antiAlias, // 角丸に沿ってクリップ

      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(w < 600 ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー行
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: w < 600 ? 8 : 10,
                      vertical: w < 600 ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      plan.code,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: w < 360 ? 12 : 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: baseFg,
                        fontWeight: FontWeight.w700,
                        fontSize: titleSize,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    plan.monthly == 0 ? '無料' : '¥${plan.monthly}',
                    style: TextStyle(
                      color: baseFg,
                      fontWeight: FontWeight.w700,
                      fontSize: priceSize,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Text('手数料 ${plan.feePct}%', style: TextStyle(color: subFg)),
              const SizedBox(height: 6),

              // 機能リスト：ここだけスクロール可能にして高さ超過を吸収
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: plan.features.length,
                  itemBuilder: (_, i) {
                    final f = plan.features[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check,
                            size: w < 360 ? 14 : 16,
                            color: baseFg,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(
                                color: baseFg,
                                fontSize: w < 360 ? 12 : 14,
                                height: 1.25,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 高さを統一
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height * 0.85, maxHeight: height),
      child: tile,
    );
  }
}

class AdminEntry {
  final String uid;
  final String email;
  final String name;

  AdminEntry({required this.uid, required this.email, required this.name});
}

class AdminList extends StatelessWidget {
  final List<AdminEntry> entries;
  final ValueChanged<String> onRemove;
  const AdminList({required this.entries, required this.onRemove, super.key});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const ListTile(title: Text('管理者がいません'));
    }

    return LayoutBuilder(
      builder: (context, c) {
        final isCompact = c.maxWidth < 420;

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = entries[i];
            final name = e.name.trim();
            final email = e.email.trim();

            final title = isCompact
                ? Text(
                    // コンパクトでは1行にまとめる（省略）
                    [
                      if (name.isNotEmpty) name,
                      if (email.isNotEmpty) email,
                    ].join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (name.isNotEmpty)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54),
                        ),
                    ],
                  );

            return ListTile(
              dense: isCompact,
              leading: const CircleAvatar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                child: Icon(Icons.admin_panel_settings),
              ),
              title: title,
              trailing: isCompact
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: '削除',
                      onPressed: () => onRemove(e.uid),
                    )
                  : Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: '削除',
                          onPressed: () => onRemove(e.uid),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}
