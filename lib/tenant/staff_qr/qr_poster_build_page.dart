import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:yourpay/firebase_options.dart';

// ===== 用紙定義（縦基準の寸法・フォーマット） =====
enum _Paper { a0, a1, a2, a3, a4, b0, b1, b2, b3, b4, b5 }

class _PaperDef {
  final String label;
  final PdfPageFormat format; // PDF用（縦基準）
  final double widthMm; // プレビュー用（縦基準）
  final double heightMm;
  const _PaperDef(this.label, this.format, this.widthMm, this.heightMm);
}

// ISO 216 mm
const Map<_Paper, _PaperDef> _paperDefs = {
  _Paper.a0: _PaperDef(
    'A0',
    PdfPageFormat(841 * PdfPageFormat.mm, 1189 * PdfPageFormat.mm),
    841,
    1189,
  ),
  _Paper.a1: _PaperDef(
    'A1',
    PdfPageFormat(594 * PdfPageFormat.mm, 841 * PdfPageFormat.mm),
    594,
    841,
  ),
  _Paper.a2: _PaperDef(
    'A2',
    PdfPageFormat(420 * PdfPageFormat.mm, 594 * PdfPageFormat.mm),
    420,
    594,
  ),
  _Paper.a3: _PaperDef(
    'A3',
    PdfPageFormat(297 * PdfPageFormat.mm, 420 * PdfPageFormat.mm),
    297,
    420,
  ),
  _Paper.a4: _PaperDef(
    'A4',
    PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm),
    210,
    297,
  ),
  _Paper.b0: _PaperDef(
    'B0',
    PdfPageFormat(1000 * PdfPageFormat.mm, 1414 * PdfPageFormat.mm),
    1000,
    1414,
  ),
  _Paper.b1: _PaperDef(
    'B1',
    PdfPageFormat(707 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm),
    707,
    1000,
  ),
  _Paper.b2: _PaperDef(
    'B2',
    PdfPageFormat(500 * PdfPageFormat.mm, 707 * PdfPageFormat.mm),
    500,
    707,
  ),
  _Paper.b3: _PaperDef(
    'B3',
    PdfPageFormat(353 * PdfPageFormat.mm, 500 * PdfPageFormat.mm),
    353,
    500,
  ),
  _Paper.b4: _PaperDef(
    'B4',
    PdfPageFormat(250 * PdfPageFormat.mm, 353 * PdfPageFormat.mm),
    250,
    353,
  ),
  _Paper.b5: _PaperDef(
    'B5',
    PdfPageFormat(176 * PdfPageFormat.mm, 250 * PdfPageFormat.mm),
    176,
    250,
  ),
};

class QrPosterBuilderPage extends StatefulWidget {
  const QrPosterBuilderPage({super.key});

  @override
  State<QrPosterBuilderPage> createState() => _QrPosterBuilderPageState();
}

class _QrPosterBuilderPageState extends State<QrPosterBuilderPage> {
  // ====== 引数（URL/argumentsから） ======
  String? tenantId;
  String? employeeId;

  // ====== 背景画像（Cプランのみ） ======
  Uint8List? _photoBytes;
  String? _photoName;

  // ====== QR設定 ======
  double _qrSizeMm = 50; // QRサイズ
  double _marginMm = 12; // ページ外周余白 (PDF)
  bool _putWhiteBg = true; // QRの白背景

  // ★ 位置：内容領域(余白を除く)における[0,1]正規化座標（中心位置）
  // 既定：Offset(0.199, 0.684)
  Offset _qrPos = const Offset(0.199, 0.684);

  // 用紙と向き
  _Paper _paper = _Paper.a4;
  bool _landscape = false;

  // ★ Cプラン判定
  bool _isCPlan = false;
  bool _loadingPlan = true;

  // ====== 初期化 ======
  @override
  void initState() {
    super.initState();
    _initFromUrl();
    _ensureFirebaseThenFetchPlan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      tenantId ??= (args['tenantId'] ?? args['t'])?.toString();
      employeeId ??= (args['employeeId'] ?? args['e'])?.toString();

      // ★ 初期座標を arguments から受け取って適用（省略時は既定値）
      final ip = (args['initialQrPos'] as Map?)?.cast<String, dynamic>();
      if (ip != null) {
        final dx = (ip['dx'] is num) ? (ip['dx'] as num).toDouble() : null;
        final dy = (ip['dy'] is num) ? (ip['dy'] as num).toDouble() : null;
        if (dx != null && dy != null) {
          _qrPos = _clampOffset(Offset(dx, dy));
        }
      }
      setState(() {});
      _ensureFirebaseThenFetchPlan();
    }
  }

  void _initFromUrl() {
    final uri = Uri.base;
    final frag = uri.fragment; // "#/qr-builder?t=...&e=...&dx=&dy="
    final qi = frag.indexOf('?');
    final qp = <String, String>{}..addAll(uri.queryParameters);
    if (qi >= 0) {
      qp.addAll(Uri.splitQueryString(frag.substring(qi + 1)));
    }
    tenantId = qp['t'] ?? qp['tenantId'];
    employeeId = qp['e'] ?? qp['employeeId'];

    // ★ URLクエリで初期座標も受け取り可能に（任意）
    final qdx = double.tryParse(qp['dx'] ?? '');
    final qdy = double.tryParse(qp['dy'] ?? '');
    if (qdx != null && qdy != null) {
      _qrPos = _clampOffset(Offset(qdx, qdy));
    }
  }

  Future<void> _ensureFirebaseThenFetchPlan() async {
    if (tenantId == null || tenantId!.isEmpty) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await _fetchIsCPlanPublic(tenantId!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCPlan = false;
        _loadingPlan = false;
      });
    }
  }

  Future<void> _fetchIsCPlanPublic(String tid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tenantIndex')
          .doc(tid)
          .get();
      final data = doc.data() ?? {};
      final sub = (data['subscription'] as Map?)?.cast<String, dynamic>();
      final planRaw = (sub?['plan'] ?? data['plan'])?.toString() ?? '';
      final plan = _canonicalizePlan(planRaw);
      if (!mounted) return;
      setState(() {
        _isCPlan = (plan == 'C');
        _loadingPlan = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCPlan = false;
        _loadingPlan = false;
      });
    }
  }

  String _canonicalizePlan(String raw) {
    final n = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    const cAliases = {'c', 'cplan', 'planc', 'premium'};
    const aAliases = {'a', 'aplan', 'plana', 'free', 'basic'};
    const bAliases = {'b', 'bplan', 'planb', 'pro', 'standard'};
    if (cAliases.contains(n)) return 'C';
    if (aAliases.contains(n)) return 'A';
    if (bAliases.contains(n)) return 'B';
    return raw.trim().toUpperCase();
  }

  // ローカル/本番自動切替のベースURL
  String get _publicBase {
    final u = Uri.base;
    final isHttp =
        (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
    if (isHttp) {
      return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    }
    const fb = String.fromEnvironment(
      'PUBLIC_BASE',
      defaultValue: 'https://tipri.jp',
    );
    return fb;
  }

  String get _qrData {
    if (tenantId == null || employeeId == null) return '';
    final params = Uri(
      queryParameters: {'t': tenantId!, 'e': employeeId!},
    ).query;
    return '$_publicBase/#/staff?$params';
  }

  // ====== 背景画像アップロード（Cのみ） ======
  Future<void> _pickPhoto() async {
    if (!_isCPlan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '写真アップロードは C プラン限定です',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
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
    if (bytes == null) return;
    setState(() {
      _photoBytes = bytes;
      _photoName = f.name;
    });
  }

  // ====== PDF生成 ======
  Future<void> _makePdfAndDownload() async {
    if (_qrData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URLが不正です', style: TextStyle(fontFamily: 'LINEseed')),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    final pdf = pw.Document();
    double mm(double v) => v * PdfPageFormat.mm;

    final pdef = _paperDefs[_paper]!;
    final pageFormat = _landscape ? pdef.format.landscape : pdef.format;

    // 内容領域サイズ（余白を引いた中身）
    final contentW = pageFormat.width - mm(_marginMm) * 2;
    final contentH = pageFormat.height - mm(_marginMm) * 2;

    // QRの外枠（白背景含めた一辺）
    final qrOuterMm = _qrSizeMm + (_putWhiteBg ? 10 : 0);
    final qrOuterPx = mm(qrOuterMm);

    // 中心座標（内容領域基準）
    final cx = (_qrPos.dx.clamp(0.0, 1.0)) * contentW;
    final cy = (_qrPos.dy.clamp(0.0, 1.0)) * contentH;

    // 左上座標（内容領域原点へ変換）
    final left = cx - qrOuterPx / 2;
    final top = cy - qrOuterPx / 2;

    // 背景
    pw.Widget background = pw.Container(color: PdfColors.white);
    if (_photoBytes != null) {
      final img = pw.MemoryImage(_photoBytes!);
      background = pw.Positioned.fill(
        child: pw.Image(img, fit: pw.BoxFit.cover),
      );
    }

    // QR本体
    final barcode = Barcode.qrCode();
    final qrWidget = pw.BarcodeWidget(
      barcode: barcode,
      data: _qrData,
      width: mm(_qrSizeMm),
      height: mm(_qrSizeMm),
      drawText: false,
      color: PdfColors.black,
    );

    final qrBox = pw.Container(
      width: qrOuterPx,
      height: qrOuterPx,
      decoration: _putWhiteBg
          ? pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(6),
            )
          : const pw.BoxDecoration(),
      alignment: pw.Alignment.center,
      child: qrWidget,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(mm(_marginMm)),
        build: (_) => pw.Stack(
          children: [
            background,
            // ★ 位置指定（内容領域内）
            pw.Positioned(
              left: left.clamp(0, contentW - qrOuterPx),
              top: top.clamp(0, contentH - qrOuterPx),
              child: qrBox,
            ),
          ],
        ),
      ),
    );

    final fname = 'staff_qr_${employeeId ?? ""}.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fname);
  }

  // ====== 便利: Offset正規化のクランプ ======
  Offset _clampOffset(Offset o) =>
      Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final valid = tenantId != null && employeeId != null;

    final pdef = _paperDefs[_paper]!;
    final previewAspect = _landscape
        ? (pdef.heightMm / pdef.widthMm)
        : (pdef.widthMm / pdef.heightMm);

    final canUpload = _isCPlan;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'QRポスター作成',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'LINEseed',
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'QR位置をリセット',
            onPressed: () =>
                setState(() => _qrPos = const Offset(0.199, 0.684)),
            icon: const Icon(Icons.my_location_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '用紙サイズ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_Paper>(
                          value: _paper,
                          items: _paperDefs.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value.label,
                                    style: const TextStyle(
                                      fontFamily: 'LINEseed',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _paper = v!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '向き',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<bool>(
                          value: _landscape,
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text(
                                '縦向き',
                                style: TextStyle(fontFamily: 'LINEseed'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text(
                                '横向き',
                                style: TextStyle(fontFamily: 'LINEseed'),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _landscape = v!),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (!valid)
                const Text(
                  'URLが不正です（t/e パラメータが必要）',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),

              if (valid) ...[
                // ==== プレビュー（ドラッグでQR移動） ====
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio: previewAspect,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // mm→px 変換
                        final pageWmm = _landscape
                            ? pdef.heightMm
                            : pdef.widthMm;
                        // //final pageHmm = _landscape
                        //     ? pdef.widthMm
                        //     : pdef.heightMm;
                        final pxPerMm = c.maxWidth / pageWmm;

                        final marginPx = _marginMm * pxPerMm;

                        // 内容領域（余白を除く）
                        final contentW = c.maxWidth - marginPx * 2;
                        final contentH = c.maxHeight - marginPx * 2;

                        // QR外枠ピクセル
                        final qrOuterPx =
                            (_qrSizeMm + (_putWhiteBg ? 10 : 0)) * pxPerMm;

                        // ★ 正規化座標→内容領域座標（左上起点）
                        double left =
                            marginPx +
                            (_qrPos.dx.clamp(0.0, 1.0)) * contentW -
                            qrOuterPx / 2;
                        double top =
                            marginPx +
                            (_qrPos.dy.clamp(0.0, 1.0)) * contentH -
                            qrOuterPx / 2;

                        // 可動範囲クランプ（内容領域内）
                        final minLeft = marginPx;
                        final minTop = marginPx;
                        final maxLeft = marginPx + contentW - qrOuterPx;
                        final maxTop = marginPx + contentH - qrOuterPx;
                        left = left.clamp(minLeft, maxLeft);
                        top = top.clamp(minTop, maxTop);

                        // ドラッグ更新：px→正規化(中心)
                        void _updateFromDrag(Offset delta) {
                          final newLeft = (left + delta.dx).clamp(
                            minLeft,
                            maxLeft,
                          );
                          final newTop = (top + delta.dy).clamp(minTop, maxTop);
                          final centerX = (newLeft + qrOuterPx / 2) - marginPx;
                          final centerY = (newTop + qrOuterPx / 2) - marginPx;
                          final ndx = (contentW <= 0)
                              ? 0.5
                              : (centerX / contentW);
                          final ndy = (contentH <= 0)
                              ? 0.5
                              : (centerY / contentH);
                          setState(
                            () => _qrPos = _clampOffset(Offset(ndx, ndy)),
                          );
                        }

                        return Stack(
                          children: [
                            // 背景
                            Positioned.fill(
                              child: _photoBytes == null
                                  ? Image.asset(
                                      "assets/posters/store_poster.jpg",
                                      fit: BoxFit.cover,
                                    )
                                  : Image.memory(
                                      _photoBytes!,
                                      fit: BoxFit.cover,
                                    ),
                            ),

                            // ドラッグハンドル+QR
                            Positioned(
                              left: left,
                              top: top,
                              width: qrOuterPx,
                              height: qrOuterPx,
                              child: GestureDetector(
                                onPanUpdate: (d) => _updateFromDrag(d.delta),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _putWhiteBg
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: _putWhiteBg
                                        ? const [
                                            BoxShadow(
                                              color: Color(0x22000000),
                                              blurRadius: 6,
                                              offset: Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                    border: Border.all(
                                      color: Colors.black26,
                                      width: 1,
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: _qrData.isEmpty
                                      ? const SizedBox()
                                      : Center(
                                          child: QrImageView(
                                            data: _qrData,
                                            version: QrVersions.auto,
                                            gapless: true,
                                            size:
                                                qrOuterPx -
                                                (_putWhiteBg ? 12 : 0),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ==== コントロール群 ====
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 560;
                    final pickBtn = Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canUpload
                            ? _pickPhoto
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '写真アップロードは C プラン限定です',
                                      style: TextStyle(fontFamily: 'LINEseed'),
                                    ),
                                    backgroundColor: Color(0xFFFCC400),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.photo_library),
                        label: Text(
                          _loadingPlan
                              ? 'プラン確認中...'
                              : (_photoName ??
                                    (canUpload ? '写真を選ぶ' : '写真アップロード（Cプランのみ）')),
                          style: const TextStyle(fontFamily: 'LINEseed'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Colors.black87),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    );
                    final pdfBtn = FilledButton.icon(
                      onPressed: _makePdfAndDownload,
                      icon: const Icon(Icons.file_download),
                      label: const Text(
                        'PDFをダウンロード',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFCC400),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          Row(children: [pickBtn]),
                          const SizedBox(height: 8),
                          SizedBox(width: double.infinity, child: pdfBtn),
                        ],
                      );
                    } else {
                      return Row(
                        children: [pickBtn, const SizedBox(width: 8), pdfBtn],
                      );
                    }
                  },
                ),

                const SizedBox(height: 8),
                if (!_loadingPlan && !canUpload)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '※ 写真アップロードは C プラン限定機能です。',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                _SliderTile(
                  label: 'QRサイズ (mm)',
                  value: _qrSizeMm,
                  min: 30,
                  max: 120,
                  onChanged: (v) => setState(() => _qrSizeMm = v),
                ),
                _SliderTile(
                  label: '余白 (mm)',
                  value: _marginMm,
                  min: 0,
                  max: 40,
                  onChanged: (v) => setState(() => _marginMm = v),
                ),
                SwitchListTile(
                  title: const Text(
                    'QRの背景を白で敷く',
                    style: TextStyle(
                      color: Colors.black87,
                      fontFamily: 'LINEseed',
                    ),
                  ),
                  value: _putWhiteBg,
                  onChanged: (v) => setState(() => _putWhiteBg = v),
                  contentPadding: EdgeInsets.zero,
                ),

                // 位置の数値表示＆微調整（お好みで）
                const SizedBox(height: 8),
                _NudgePad(
                  pos: _qrPos,
                  onChanged: (o) => setState(() => _qrPos = _clampOffset(o)),
                ),

                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ====== 位置微調整ウィジェット（任意） ======
class _NudgePad extends StatelessWidget {
  final Offset pos; // 正規化
  final ValueChanged<Offset> onChanged;
  const _NudgePad({required this.pos, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = TextStyle(fontFamily: 'LINEseed', color: Colors.black87);
    void nudge(double dx, double dy) =>
        onChanged(Offset(pos.dx + dx, pos.dy + dy));
    return Row(
      children: [
        Expanded(
          child: Text(
            '位置: x=${pos.dx.toStringAsFixed(3)}, '
            'y=${pos.dy.toStringAsFixed(3)}',
            style: text,
          ),
        ),
        IconButton(
          tooltip: '左へ',
          onPressed: () => nudge(-0.005, 0),
          icon: const Icon(Icons.chevron_left),
        ),
        Column(
          children: [
            IconButton(
              tooltip: '上へ',
              onPressed: () => nudge(0, -0.005),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: '下へ',
              onPressed: () => nudge(0, 0.005),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
        IconButton(
          tooltip: '右へ',
          onPressed: () => nudge(0.005, 0),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      textColor: Colors.black87,
      title: Text(
        label,
        style: const TextStyle(color: Colors.black87, fontFamily: 'LINEseed'),
      ),
      subtitle: Slider(value: value, min: min, max: max, onChanged: onChanged),
      trailing: SizedBox(
        width: 56,
        child: Text(
          value.toStringAsFixed(0),
          style: const TextStyle(fontFamily: 'LINEseed'),
        ),
      ),
    );
  }
}
