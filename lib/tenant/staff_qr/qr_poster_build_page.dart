// lib/qr_poster_builder_page.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // ← RepaintBoundary の toImage に必要
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:yourpay/firebase_options.dart';

// ===== 用紙定義（縦基準の寸法・フォーマット） =====
enum _Paper { a0, a1, a2, a3, a4, b0, b1, b2, b3, b4, b5 }

enum _QrDesign { classic, roundEyes, dots }

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
  double _qrSizeMm = 58; // QR内側の一辺(mm)
  double _marginMm = 12; // ページ外周余白 (視覚上)
  bool _putWhiteBg = true; // QRの白背景
  static const double _qrWhiteMarginMm = 10; // 白背景のとき外側に足す(mm)

  // ★ 位置：内容領域(余白を除く)における[0,1]正規化座標（中心位置）
  Offset _qrPos = const Offset(0.274, 0.644);

  // 用紙と向き
  _Paper _paper = _Paper.a4;
  bool _landscape = false;
  _QrDesign _qrDesign = _QrDesign.classic;

  // ★ Cプラン判定
  bool _isCPlan = false;
  bool _loadingPlan = true;

  // ====== プレビューキャプチャ用 ======
  final GlobalKey _previewKey = GlobalKey();

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

      // 初期座標（任意）
      final ip = (args['initialQrPos'] as Map?)?.cast<String, dynamic>();
      if (ip != null) {
        final dx = (ip['dx'] is num) ? (ip['dx'] as num).toDouble() : null;
        final dy = (ip['dy'] is num) ? (ip['dy'] as num).toDouble() : null;
        if (dx != null && dy != null) _qrPos = _clampOffset(Offset(dx, dy));
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
    if (qi >= 0) qp.addAll(Uri.splitQueryString(frag.substring(qi + 1)));
    tenantId = qp['t'] ?? qp['tenantId'];
    employeeId = qp['e'] ?? qp['employeeId'];

    final qdx = double.tryParse(qp['dx'] ?? '');
    final qdy = double.tryParse(qp['dy'] ?? '');
    if (qdx != null && qdy != null) _qrPos = _clampOffset(Offset(qdx, qdy));
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

  String get _qrData {
    if (tenantId == null || employeeId == null) return '';
    final params = Uri(
      queryParameters: {'t': tenantId!, 'e': employeeId!},
    ).query;
    return 'https://tip.tipri.jp/#/staff?$params';
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

  // ====== PDF生成（プレビューをそのままキャプチャ） ======
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

    final boundary =
        _previewKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'プレビューを準備中です',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
      return;
    }

    // 用紙に応じたターゲット解像度（重すぎ防止のため 6〜10 px/mm 目安）
    final pdef = _paperDefs[_paper]!;
    final mmW = _landscape ? pdef.heightMm : pdef.widthMm;
    final pxPerMmTarget = 8.0;
    final targetWidth = (mmW * pxPerMmTarget).round();
    final logicalW = boundary.size.width;
    final pixelRatio = (logicalW > 0)
        ? (targetWidth / logicalW)
        : 3.0; // フォールバック

    final ui.Image image = await boundary.toImage(
      pixelRatio: pixelRatio.clamp(2.0, 8.0),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final pdf = pw.Document();
    final pageFormat = _landscape ? pdef.format.landscape : pdef.format;
    final memImg = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(
          width: double.infinity,
          height: double.infinity,
          child: pw.FittedBox(
            fit: pw.BoxFit.cover, // プレビューとページ比率は同じなのでそのまま全面
            child: pw.Image(memImg),
          ),
        ),
      ),
    );

    final fname = 'staff_qr_${employeeId ?? ""}.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fname);
  }

  // ====== 便利: Offset正規化のクランプ ======
  Offset _clampOffset(Offset o) =>
      Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

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
              // ==== QRデザイン選択 ====
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'QRデザイン',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_QrDesign>(
                          value: _qrDesign,
                          items: const [
                            DropdownMenuItem(
                              value: _QrDesign.classic,
                              child: Text(
                                'クラシック（四角）',
                                style: TextStyle(fontFamily: 'LINEseed'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: _QrDesign.roundEyes,
                              child: Text(
                                '角丸アイ（目だけ丸）',
                                style: TextStyle(fontFamily: 'LINEseed'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: _QrDesign.dots,
                              child: Text(
                                'ドット（全体丸）',
                                style: TextStyle(fontFamily: 'LINEseed'),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _qrDesign = v!),
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
                RepaintBoundary(
                  key: _previewKey,
                  child: _PosterPreview(
                    paper: _paper,
                    landscape: _landscape,
                    marginMm: _marginMm,
                    qrPos: _qrPos,
                    qrSizeMm: _qrSizeMm,
                    putWhiteBg: _putWhiteBg,
                    qrWhiteMarginMm: _qrWhiteMarginMm,
                    photoBytes: _photoBytes,
                    qrData: _qrData,
                    qrDesign: _qrDesign,
                    onPosChanged: (o) =>
                        setState(() => _qrPos = _clampOffset(o)),
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
                  label: '外周余白 (mm)',
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

                // 位置の数値表示＆微調整
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

// ====== プレビュー本体（これをそのままキャプチャ→PDF） ======
class _PosterPreview extends StatelessWidget {
  final _Paper paper;
  final bool landscape;
  final double marginMm; // 視覚的外周余白
  final Offset qrPos; // [0,1] での中心位置（内容領域基準）
  final double qrSizeMm; // QR「内側」の一辺(mm)
  final bool putWhiteBg;
  final double qrWhiteMarginMm; // 白背景を付けるときの外枠分(mm)
  final Uint8List? photoBytes;
  final String qrData;
  final ValueChanged<Offset> onPosChanged;
  final _QrDesign qrDesign;

  const _PosterPreview({
    super.key,
    required this.paper,
    required this.landscape,
    required this.marginMm,
    required this.qrPos,
    required this.qrSizeMm,
    required this.putWhiteBg,
    required this.qrWhiteMarginMm,
    required this.photoBytes,
    required this.qrData,
    required this.onPosChanged,
    required this.qrDesign,
  });

  @override
  Widget build(BuildContext context) {
    final pdef = _paperDefs[paper]!;
    final previewAspect = landscape
        ? (pdef.heightMm / pdef.widthMm)
        : (pdef.widthMm / pdef.heightMm);

    return Container(
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
            // mm→px を単一スカラーで統一
            final pageWmm = landscape ? pdef.heightMm : pdef.widthMm;
            final pageHmm = landscape ? pdef.widthMm : pdef.heightMm;
            final pxPerMmX = c.maxWidth / pageWmm;
            final pxPerMmY = c.maxHeight / pageHmm;
            final pxPerMm = pxPerMmX < pxPerMmY ? pxPerMmX : pxPerMmY;
            //final _QrDesign = _QrDesign.
            final marginPx = marginMm * pxPerMm;

            // 内容領域（余白を除く）
            final contentW = c.maxWidth - marginPx * 2;
            final contentH = c.maxHeight - marginPx * 2;

            // QR外枠（白背景ありなら一回り大きく）
            final qrOuterMm = qrSizeMm + (putWhiteBg ? qrWhiteMarginMm : 0);
            final qrOuterPx = qrOuterMm * pxPerMm;

            // 正規化座標→内容領域座標（左上起点）
            double left =
                marginPx +
                (qrPos.dx.clamp(0.0, 1.0)) * contentW -
                qrOuterPx / 2;
            double top =
                marginPx +
                (qrPos.dy.clamp(0.0, 1.0)) * contentH -
                qrOuterPx / 2;

            // 可動範囲クランプ（内容領域内）
            final minLeft = marginPx;
            final minTop = marginPx;
            final maxLeft = marginPx + contentW - qrOuterPx;
            final maxTop = marginPx + contentH - qrOuterPx;
            left = left.clamp(minLeft, maxLeft);
            top = top.clamp(minTop, maxTop);

            // ドラッグ時更新：px→正規化(中心)
            void _updateFromDrag(Offset delta) {
              final newLeft = (left + delta.dx).clamp(minLeft, maxLeft);
              final newTop = (top + delta.dy).clamp(minTop, maxTop);
              final centerX = (newLeft + qrOuterPx / 2) - marginPx;
              final centerY = (newTop + qrOuterPx / 2) - marginPx;
              final ndx = (contentW <= 0) ? 0.5 : (centerX / contentW);
              final ndy = (contentH <= 0) ? 0.5 : (centerY / contentH);
              onPosChanged(Offset(ndx, ndy));
            }

            // ページ背景（外周余白を白で見せる）
            final pageBg = Container(color: Colors.white);

            // 中身：背景画像 or デフォルト
            final contentBg = Positioned.fill(
              left: marginPx,
              top: marginPx,
              right: marginPx,
              bottom: marginPx,
              child: photoBytes == null
                  ? Image.asset(
                      "assets/posters/store_poster.jpg",
                      fit: BoxFit.cover,
                    )
                  : Image.memory(photoBytes!, fit: BoxFit.cover),
            );

            // QR表示（外枠＋内側）
            final qrBox = Positioned(
              left: left,
              top: top,
              width: qrOuterPx,
              height: qrOuterPx,
              child: GestureDetector(
                onPanUpdate: (d) => _updateFromDrag(d.delta),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: putWhiteBg ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: putWhiteBg
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
                  child: qrData.isEmpty
                      ? const SizedBox()
                      : Center(
                          child: QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            gapless: true,
                            padding: EdgeInsets.zero,
                            size: (qrOuterPx - (putWhiteBg ? 12 : 0)).clamp(
                              0,
                              double.infinity,
                            ),
                            eyeStyle: QrEyeStyle(
                              color: Colors.black,
                              eyeShape:
                                  (qrDesign == _QrDesign.dots ||
                                      qrDesign == _QrDesign.roundEyes)
                                  ? QrEyeShape.circle
                                  : QrEyeShape.square,
                            ),
                            dataModuleStyle: QrDataModuleStyle(
                              color: Colors.black,
                              dataModuleShape: (qrDesign == _QrDesign.dots)
                                  ? QrDataModuleShape.circle
                                  : QrDataModuleShape.square,
                            ),
                          ),
                        ),
                ),
              ),
            );

            return Stack(children: [pageBg, contentBg, qrBox]);
          },
        ),
      ),
    );
  }
}

// ====== 位置微調整ウィジェット ======
class _NudgePad extends StatelessWidget {
  final Offset pos; // 正規化
  final ValueChanged<Offset> onChanged;
  const _NudgePad({required this.pos, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(fontFamily: 'LINEseed', color: Colors.black87);
    void nudge(double dx, double dy) =>
        onChanged(Offset(pos.dx + dx, pos.dy + dy));
    return Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '位置: x=${pos.dx.toStringAsFixed(3)}, y=${pos.dy.toStringAsFixed(3)}',
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
