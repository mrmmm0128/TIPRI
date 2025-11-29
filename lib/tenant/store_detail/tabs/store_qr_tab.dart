import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yourpay/tenant/method/fetchPlan.dart';
import 'package:yourpay/tenant/method/image_scrol.dart';
import 'package:yourpay/tenant/newTenant/onboardingSheet.dart';
import 'dart:async'; // 追加

class StoreQrTab extends StatefulWidget {
  final String tenantId;
  final String? tenantName;
  final String posterAssetPath; // 例: 'assets/posters/store_poster.png'
  final String? ownerId;
  final bool? agency;
  const StoreQrTab({
    super.key,
    required this.tenantId,
    this.tenantName,
    this.agency,
    this.posterAssetPath = 'assets/posters/store_poster.jpg',
    this.ownerId,
  });

  @override
  State<StoreQrTab> createState() => _StoreQrTabState();
}

class _PosterOption {
  final String id; // 'asset' or Firestore docId
  final String label;
  final String? assetPath;
  final String? url;
  const _PosterOption.asset(this.assetPath, {this.label = 'テンプレ'})
    : id = 'asset',
      url = null;
  const _PosterOption.remote(this.id, this.url, {required this.label})
    : assetPath = null;
  bool get isAsset => assetPath != null;
}

// ▼ 用紙定義（A0〜A4 / B0〜B5）
enum _Paper { a0, a1, a2, a3, a4, a6, a7, b0, b1, b2, b3, b4, b5, b6, b7 }

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
  // 追加: A6 / A7（A5は不要とのことなので未追加のまま）
  _Paper.a6: _PaperDef(
    'A6',
    PdfPageFormat(105 * PdfPageFormat.mm, 148 * PdfPageFormat.mm),
    105,
    148,
  ),
  _Paper.a7: _PaperDef(
    'A7',
    PdfPageFormat(74 * PdfPageFormat.mm, 105 * PdfPageFormat.mm),
    74,
    105,
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
  // 追加: B6 / B7
  _Paper.b6: _PaperDef(
    'B6',
    PdfPageFormat(125 * PdfPageFormat.mm, 176 * PdfPageFormat.mm),
    125,
    176,
  ),
  _Paper.b7: _PaperDef(
    'B7',
    PdfPageFormat(88 * PdfPageFormat.mm, 125 * PdfPageFormat.mm),
    88,
    125,
  ),
};

class _StoreQrTabState extends State<StoreQrTab> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  final uid = FirebaseAuth.instance.currentUser?.uid;

  // ------- 状態 -------
  String? _publicStoreUrl;
  String _selectedPosterId = 'asset';
  _PosterOption? _optimisticPoster;
  bool _exporting = false;

  // 表示/出力カスタム
  bool _putWhiteBg = true;
  double _qrScale = 0.28; // 20〜60%
  double _qrPaddingMm = 6;
  bool _landscape = false;
  // 追加: フィールド
  late CollectionReference<Map<String, dynamic>> _postersRef;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _postersStream;
  QuerySnapshot<Map<String, dynamic>>? _initialPosters; // 初期表示用(キャッシュ)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _tenantListen; // 追加
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tenantStatusSub;

  // 用紙：UI表示は setState、プレビューは _paperVN で用紙変更時のみ再描画
  _Paper _paper = _Paper.a4;
  final ValueNotifier<_Paper> _paperVN = ValueNotifier<_Paper>(_Paper.a4);

  Offset _qrPos = const Offset(0.287, 0.649);
  bool isC = false;
  _QrDesign _qrDesign = _QrDesign.classic;
  bool agency = false;

  bool? _connected; // ← 一度だけ取得して保持
  bool? _subscStatus = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _publicStoreUrl = _buildStoreUrl();

    final u = FirebaseAuth.instance.currentUser?.uid;
    assert(u != null, 'Not signed in');
    _postersRef = FirebaseFirestore.instance
        .collection(widget.ownerId!)
        .doc(widget.tenantId)
        .collection('posters');

    if (widget.agency != null) {
      agency = widget.agency!;
    }
    _postersStream = _postersRef.snapshots(); // ← 初回から張る

    _primeInitialPosters(); // ← 下の #2 参照
    _listenTenantAndControl(); // ← これに差し替え
    _startWatchTenantStatus();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant StoreQrTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _publicStoreUrl = _buildStoreUrl();
      //Offset _qrPos = const Offset(0.199, 0.684);

      _postersRef = FirebaseFirestore.instance
          .collection(widget.ownerId!)
          .doc(widget.tenantId)
          .collection('posters');

      setState(() {
        _postersStream = _postersRef.snapshots(); // ★ 張り替え
        _optimisticPoster = null;
        _selectedPosterId = 'asset';
      });

      _primeInitialPosters(); // ★ 新テナントの初期データも取り直す
      _listenTenantAndControl(); // ← これに差し替え
      _startWatchTenantStatus();
      _initialize();
    }
  }

  void _logQrPos([String tag = '']) {
    debugPrint(
      'QR pos$tag: x=${_qrPos.dx.toStringAsFixed(3)}, y=${_qrPos.dy.toStringAsFixed(3)}',
    );
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
        ),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  static Future<void> showTipriInfoDialog(BuildContext context) async {
    // 表示する画像（あなたのアセットパスに合わせて変更）
    final assets = <String>[
      'assets/pdf/1.jpg',
      'assets/pdf/2.jpg',
      'assets/pdf/3.jpg',
      'assets/pdf/4.jpg',
      'assets/pdf/5.jpg',
      'assets/pdf/6.jpg',
      'assets/pdf/7.jpg',
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

      if (_subscStatus != next && mounted) {
        setState(() => _subscStatus = next);
      }
    });
  }

  Future<void> _initialize() async {
    final c = await fetchIsCPlan(
      FirebaseFirestore.instance
          .collection(widget.ownerId!)
          .doc(widget.tenantId),
    );
    if (!mounted) return;
    setState(() => isC = c); // ★ 取得後に描画更新
  }

  Future<void> _primeInitialPosters() async {
    try {
      final snap = await _postersRef.get(
        const GetOptions(source: Source.cache),
      );
      if (mounted && (snap.docs.isNotEmpty)) {
        setState(() => _initialPosters = snap);
      }
    } catch (_) {
      // キャッシュが無い・失敗は無視でOK
    }
  }

  void _listenTenantAndControl() {
    // 既存購読があれば外す
    _tenantListen?.cancel();

    final docRef = FirebaseFirestore.instance
        .collection(widget.ownerId!)
        .doc(widget.tenantId);

    _tenantListen = docRef.snapshots().listen(
      (doc) {
        final data = doc.data() ?? <String, dynamic>{};
        final connect = (data['connect'] as Map<String, dynamic>?) ?? {};

        final chargesEnabled = (connect['charges_enabled'] as bool?) ?? false;
        final payoutsEnabled = (connect['payouts_enabled'] as bool?) ?? false;
        final detailsSubmitted =
            (connect['details_submitted'] as bool?) ?? false;

        final allReady = chargesEnabled && payoutsEnabled && detailsSubmitted;

        if (mounted) {
          setState(() => _connected = allReady);
        } else {
          _connected = allReady;
        }
      },
      onError: (_) {
        if (mounted) setState(() => _connected = false);
      },
    );
  }

  String _buildStoreUrl() {
    return 'https://tip.tipri.jp?t=${widget.tenantId}';
    // 必要ならここでサイズやパラメータを追加
  }

  // ==== アップロード → Storage 保存 → Firestore 登録 ====
  Future<void> _addPosterFromFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final f = picked.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.readStream != null) {
        final chunks = <int>[];
        await for (final c in f.readStream!) {
          chunks.addAll(c);
        }
        bytes = Uint8List.fromList(chunks);
      }
      if (bytes == null) throw '画像の読み込みに失敗しました';

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

      final postersCol = FirebaseFirestore.instance
          .collection(widget.ownerId!)
          .doc(widget.tenantId)
          .collection('posters');

      final docRef = postersCol.doc();

      final contentType = _detectContentType(f.name);
      final ext = contentType.split('/').last;

      final storageRef = FirebaseStorage.instance.ref().child(
        '${widget.ownerId}/${widget.tenantId}/posters/${docRef.id}.$ext',
      );

      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final url = await storageRef.getDownloadURL();

      await docRef.set({
        'name': f.name,
        'url': url,
        'contentType': contentType,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // ★ ストリーム到着前に一時的に UI に出す
      _optimisticPoster = _PosterOption.remote(docRef.id, url, label: f.name);

      setState(() => _selectedPosterId = docRef.id);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ポスターを追加しました',
            style: TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'アップロード失敗: $e',
            style: const TextStyle(fontFamily: 'LINEseed'),
          ),
          backgroundColor: Color(0xFFFCC400),
        ),
      );
    }
  }

  // ==== PDF 出力 ====
  Future<void> _exportPdf(List<_PosterOption> options) async {
    if (_publicStoreUrl == null || _exporting) return;
    setState(() {
      _exporting = true;
    });

    final selected = options.firstWhere(
      (o) => o.id == _selectedPosterId,
      orElse: () => options.first,
    );

    pw.ImageProvider posterProvider;
    if (selected.isAsset) {
      final b = await rootBundle.load(selected.assetPath!);
      posterProvider = pw.MemoryImage(Uint8List.view(b.buffer));
    } else {
      posterProvider = await networkImage(selected.url!);
    }

    final pdef = _paperDefs[_paperVN.value]!;
    final pageFormat = _landscape ? pdef.format.landscape : pdef.format;

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        // ★ デフォルト文字色を黒に固定（このページで描くテキストすべてに効く）
        theme: pw.ThemeData(
          defaultTextStyle: pw.TextStyle(color: PdfColors.black),
        ),
        build: (ctx) {
          final pageW = ctx.page.pageFormat.availableWidth;
          final pageH = ctx.page.pageFormat.availableHeight;
          final minSide = pageW < pageH ? pageW : pageH;

          final qrSidePt = minSide * _qrScale;
          final padPt = _qrPaddingMm * PdfPageFormat.mm;
          final boxSidePt = qrSidePt + (_putWhiteBg ? padPt * 2 : 0);

          double leftPt = _qrPos.dx * pageW - boxSidePt / 2;
          double topPt = _qrPos.dy * pageH - boxSidePt / 2;
          leftPt = leftPt.clamp(0, pageW - boxSidePt);
          topPt = topPt.clamp(0, pageH - boxSidePt);

          final poster = pw.Positioned.fill(
            child: pw.FittedBox(
              child: pw.Image(posterProvider),
              fit: pw.BoxFit.cover,
            ),
          );

          final qr = pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: _publicStoreUrl!,
            width: qrSidePt,
            height: qrSidePt,
            drawText: false,
            color: PdfColors.black, // ← QR自体も黒
          );

          final qrBox = pw.Container(
            padding: _putWhiteBg
                ? pw.EdgeInsets.all(padPt)
                : pw.EdgeInsets.zero,
            decoration: _putWhiteBg
                ? pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(8),
                  )
                : const pw.BoxDecoration(),
            child: qr,
          );

          // ★（任意）QRの下に黒文字の説明やURLを入れる場合：白下地＋黒文字でくっきり
          final showCaption = false; // ← 表示したい場合は true に
          final caption = pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.white, // 白下地で背景がどんな色でも読める
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              _publicStoreUrl!,
              style: pw.TextStyle(
                color: PdfColors.black, // くっきり黒
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.span,
            ),
          );

          final qrWithCaption = pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              qrBox,
              // ignore: dead_code
              if (showCaption) caption,
            ],
          );

          return pw.Stack(
            children: [
              poster,
              pw.Positioned(left: leftPt, top: topPt, child: qrWithCaption),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'store_qr_${widget.tenantId}.pdf',
    );

    final postersCol = FirebaseFirestore.instance
        .collection(widget.ownerId!)
        .doc(widget.tenantId);

    final Col = FirebaseFirestore.instance
        .collection("tenantIndex")
        .doc(widget.tenantId);

    await postersCol.set({"download": "done"}, SetOptions(merge: true));
    await Col.set({"download": "done"}, SetOptions(merge: true));
    setState(() {
      _exporting = false;
    });
  }

  // ---------- オンボーディング ----------
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
        fillColor: Color(0xFFFCC400),
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

  @override
  void dispose() {
    _paperVN.dispose();
    _tenantListen?.cancel();
    _tenantStatusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final black78 = Colors.black.withOpacity(0.78);
    final primary = FilledButton.styleFrom(
      backgroundColor: Color(0xFFFCC400),
      foregroundColor: Colors.black,

      side: const BorderSide(color: Colors.black54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    final waitingConnect = _connected == null;

    // ---------------- UI ----------------
    return _subscStatus!
        ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _postersStream,
            initialData: _initialPosters,
            builder: (context, postersSnap) {
              // ★ 読み込みエラーは画面にも出し、SnackBar でも通知
              if (postersSnap.hasError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'ポスターの読み込みに失敗しました: ${postersSnap.error}',
                          style: TextStyle(fontFamily: 'LINEseed'),
                        ),
                        backgroundColor: Color(0xFFFCC400),
                      ),
                    );
                  }
                });
              }

              final remoteDocs = (postersSnap.data?.docs ?? []);
              final options = <_PosterOption>[
                _PosterOption.asset(widget.posterAssetPath, label: 'デフォルト'),
                ...remoteDocs.map((d) {
                  final m = d.data();
                  return _PosterOption.remote(
                    d.id,
                    (m['url'] ?? '') as String,
                    label: (""),
                  );
                }),
              ];

              // ★ 楽観挿入の重複防止：同じIDがサーバーから来たら破棄
              if (_optimisticPoster != null &&
                  options.any((o) => o.id == _optimisticPoster!.id)) {
                _optimisticPoster = null;
              }

              // ★ まだ入っていなければ一時的に挿入（アップロード直後にすぐ見える）
              if (_optimisticPoster != null &&
                  !options.any((o) => o.id == _optimisticPoster!.id)) {
                options.insert(1, _optimisticPoster!);
              }

              final currentPosterId =
                  options.any((o) => o.id == _selectedPosterId)
                  ? _selectedPosterId
                  : (options.isNotEmpty ? options.first.id : null);

              Widget paperSelector() => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InputDecorator(
                    decoration: InputDecoration(
                      //fillColor: Color(0xFFFCC400),
                      labelText: '用紙サイズ',
                      labelStyle: TextStyle(color: Colors.black),
                      hintStyle: TextStyle(color: Colors.black),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.black,
                          width: 3,
                        ), // ★
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.black,
                          width: 3,
                        ), // ★
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_Paper>(
                        key: const ValueKey('paper-dd'),
                        value: _paper,
                        isDense: true,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _paper = v);
                          _paperVN.value = v;
                        },
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text(
                      '横向き',
                      style: TextStyle(
                        color: Colors.black,
                        fontFamily: 'LINEseed',
                      ),
                    ),

                    value: _landscape,
                    onChanged: (v) => setState(() => _landscape = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,

                    activeColor: Colors.white, // 親指(thumb)
                    activeTrackColor: Colors.amberAccent, // レール(track)
                    // OFF時
                    inactiveThumbColor: Colors.amber,
                    inactiveTrackColor: Colors.white,
                  ),
                ],
              );

              // ▼ PDFダウンロード（FilledButton）
              Widget pdfButton() => FilledButton.icon(
                style: primary.copyWith(
                  // 太い黒枠（有効/無効で色だけ出し分け）
                  side: MaterialStateProperty.resolveWith<BorderSide>(
                    (states) => states.contains(MaterialState.disabled)
                        ? const BorderSide(color: Colors.black26, width: 3)
                        : const BorderSide(color: Colors.black, width: 3),
                  ),
                  // 角丸を明示（必要なければ消してOK）
                  shape: MaterialStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                onPressed:
                    (!_exporting && _connected! && _publicStoreUrl != null)
                    ? () => _exportPdf(options)
                    : null,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.black, // 黄背景に合う
                        ),
                      )
                    : const Icon(Icons.file_download),
                label: const Text(
                  'ダウンロード',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
              );

              Widget uploadButton({required bool isC}) {
                final canUpload = (_connected ?? false) && isC;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canUpload ? _addPosterFromFile : null,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text(
                        'アップロード',
                        style: TextStyle(fontFamily: 'LINEseed'),
                      ),
                      style:
                          OutlinedButton.styleFrom(
                            backgroundColor: Color(0xFFFCC400),
                            foregroundColor: Colors.black,

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            side: const BorderSide(
                              color: Colors.black,
                              width: 3,
                            ), // ★ 太枠
                          ).copyWith(
                            // 無効時も太さを維持（色だけ薄く）
                            side: MaterialStateProperty.resolveWith<BorderSide>(
                              (states) =>
                                  states.contains(MaterialState.disabled)
                                  ? const BorderSide(
                                      color: Colors.black26,
                                      width: 3,
                                    )
                                  : const BorderSide(
                                      color: Colors.black,
                                      width: 3,
                                    ),
                            ),
                          ),
                    ),
                  ],
                );
              }

              Widget posterPicker() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 108,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final opt = options[i];
                        final selected =
                            (currentPosterId != null &&
                            opt.id == currentPosterId);

                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedPosterId = opt.id),
                          child: Column(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? Colors.black
                                        : Colors.black12,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: opt.isAsset
                                    ? Image.asset(
                                        opt.assetPath!,
                                        fit: BoxFit.cover,
                                      )
                                    : isC
                                    ? Image.network(
                                        opt.url!,
                                        fit: BoxFit.cover,
                                        loadingBuilder:
                                            (
                                              ctx,
                                              child,
                                              progress,
                                            ) => progress == null
                                            ? child
                                            : const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                        errorBuilder: (ctx, err, st) =>
                                            const Center(
                                              child: Icon(Icons.broken_image),
                                            ),
                                      )
                                    : Center(child: Text("使用不可")),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  opt.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'LINEseed',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );

              Widget urlButton(BuildContext context) {
                final url = _publicStoreUrl;
                if (url == null || url.isEmpty) return const SizedBox.shrink();

                return FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(0xFFFCC400),
                    foregroundColor: Colors.black,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.black, width: 3),
                  ),
                  onPressed: () async {
                    final ok = await launchUrlString(
                      url,
                      mode: LaunchMode.externalApplication,
                      webOnlyWindowName: '_self',
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'リンクを開けませんでした',
                            style: TextStyle(fontFamily: 'LINEseed'),
                          ),
                          backgroundColor: Color(0xFFFCC400),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('ページ確認'),
                );
              }

              Widget qrControls() => DefaultTextStyle.merge(
                style: TextStyle(color: black78),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('QRデザイン'),
                      trailing: DropdownButton<_QrDesign>(
                        value: _qrDesign,
                        onChanged: (v) => setState(() => _qrDesign = v!),
                        items: const [
                          DropdownMenuItem(
                            value: _QrDesign.classic,
                            child: Text('デフォルト（四角）'),
                          ),
                          DropdownMenuItem(
                            value: _QrDesign.roundEyes,
                            child: Text('丸い目＋四角ドット'),
                          ),
                          DropdownMenuItem(
                            value: _QrDesign.dots,
                            child: Text('丸ドット'),
                          ),
                        ],
                      ),
                    ),
                    _SliderTile(
                      label: 'QRサイズ（%）',
                      value: _qrScale,
                      min: 0.20,
                      max: 0.60,
                      displayAsPercent: true,
                      onChanged: (v) => setState(() => _qrScale = v),
                    ),
                    _SliderTile(
                      label: 'QRの余白（mm）',
                      value: _qrPaddingMm,
                      min: 0,
                      max: 20,
                      onChanged: (v) => setState(() => _qrPaddingMm = v),
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
                    const SizedBox(height: 6),
                    const Text(
                      'ヒント：プレビュー内のQRをドラッグで移動/ダブルタップで規定位置に移動',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontFamily: 'LINEseed',
                      ),
                    ),
                  ],
                ),
              );

              Widget connectNotice() {
                if (_connected == true) return const SizedBox.shrink();

                // 白背景で見やすい淡色トーン
                const warnBg = Color(0xFFFFF8E1); // 明るいアンバー系（薄い黄色）
                const warnBorder = Color(0xFFFFD54F); // 枠線（少し濃い黄色）
                const iconBg = Color(0xFFFFD54F); // アイコンの円背景
                const iconFg = Colors.black; // アイコン色

                return Column(
                  children: [
                    Card(
                      elevation: 0,
                      color: warnBg,
                      surfaceTintColor: Colors.transparent, // M3の面影色を無効化
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: warnBorder),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: iconBg,
                          foregroundColor: iconFg,
                          child: Icon(Icons.info_outline),
                        ),
                        title: const Text(
                          'Stripeアカウント未作成',
                          style: TextStyle(
                            fontFamily: 'LINEseed',
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        subtitle: const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'チップの受取にはStripeアカウントの作成が必要です。',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                        trailing: FilledButton(
                          // 既存の `primary` スタイルを使いたければ置き換え可
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              // agency=true で無効時は薄く
                              if (agency) return Colors.black.withOpacity(0.12);
                              return Colors.black;
                            }),
                            foregroundColor: const WidgetStatePropertyAll(
                              Colors.white,
                            ),
                          ),
                          onPressed: agency
                              ? null
                              : () => startOnboarding(
                                  widget.tenantId,
                                  widget.tenantName!,
                                ),
                          child: const Text(
                            '今すぐ設定',
                            style: TextStyle(fontFamily: 'LINEseed'),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // 右側プレビュー：用紙変更時だけ再レイアウト（_paperVN）
              Widget previewPane() => ValueListenableBuilder<_Paper>(
                valueListenable: _paperVN,
                builder: (_, paper, __) {
                  final def = _paperDefs[paper]!;
                  final wMm = _landscape ? def.heightMm : def.widthMm;
                  final hMm = _landscape ? def.widthMm : def.heightMm;
                  final aspect = wMm / hMm;

                  return AspectRatio(
                    aspectRatio: aspect,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final h = c.maxHeight;
                        final minSide = w < h ? w : h;

                        final widthMm = _landscape ? def.heightMm : def.widthMm;
                        final pxPerMm = w / widthMm;
                        final padPx = _qrPaddingMm * pxPerMm;
                        final qrSidePx = minSide * _qrScale;
                        final boxSidePx =
                            qrSidePx + (_putWhiteBg ? padPx * 2 : 0);

                        final halfX = (boxSidePx / 2) / w;
                        final halfY = (boxSidePx / 2) / h;

                        final selected = options.firstWhere(
                          (o) => o.id == _selectedPosterId,
                          orElse: () => options.first,
                        );
                        final posterWidget = selected.isAsset
                            ? Image.asset(
                                selected.assetPath!,
                                fit: BoxFit.cover,
                              )
                            : isC
                            ? Image.network(selected.url!, fit: BoxFit.cover)
                            : null;

                        final cx = _qrPos.dx.clamp(halfX, 1 - halfX).toDouble();
                        final cy = _qrPos.dy.clamp(halfY, 1 - halfY).toDouble();

                        final left = cx * w - boxSidePx / 2;
                        final top = cy * h - boxSidePx / 2;

                        final showQr =
                            (_connected == true) &&
                            _publicStoreUrl != null &&
                            _publicStoreUrl!.isNotEmpty;

                        // ★ ここを必ず return する！
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: posterWidget,
                              ),
                            ),
                            if (showQr)
                              Positioned(
                                left: left,
                                top: top,
                                width: boxSidePx,
                                height: boxSidePx,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      final nx = (_qrPos.dx + details.delta.dx / w)
                                          .clamp(halfX, 1 - halfX)
                                          .toDouble(); // ★ clamp の戻り値を double に
                                      final ny =
                                          (_qrPos.dy + details.delta.dy / h)
                                              .clamp(halfY, 1 - halfY)
                                              .toDouble();
                                      _qrPos = Offset(nx, ny);
                                    });
                                    _logQrPos(' (drag)');
                                  },
                                  onDoubleTap: () => setState(
                                    () => _qrPos = const Offset(0.5, 0.5),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _putWhiteBg
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: _putWhiteBg
                                          ? const [
                                              BoxShadow(
                                                color: Color(0x22000000),
                                                blurRadius: 6,
                                                offset: Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Padding(
                                      padding: EdgeInsets.all(
                                        _putWhiteBg ? padPx : 0,
                                      ),
                                      child: QrImageView(
                                        data: _publicStoreUrl!,
                                        version: QrVersions.auto,
                                        gapless: true,
                                        size: qrSidePx,
                                        eyeStyle: QrEyeStyle(
                                          color: Colors.black,
                                          eyeShape:
                                              _qrDesign == _QrDesign.dots ||
                                                  _qrDesign ==
                                                      _QrDesign.roundEyes
                                              ? QrEyeShape.circle
                                              : QrEyeShape.square,
                                        ),
                                        dataModuleStyle: QrDataModuleStyle(
                                          color: Colors.black,
                                          dataModuleShape:
                                              _qrDesign == _QrDesign.dots
                                              ? QrDataModuleShape.circle
                                              : QrDataModuleShape.square,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  );
                },
              );

              final isWide = MediaQuery.of(context).size.width >= 900;

              if (isWide) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              connectNotice(),
                              if (_connected!) ...[
                                paperSelector(),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: pdfButton()),
                                    const SizedBox(width: 12),
                                    Expanded(child: uploadButton(isC: isC)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              posterPicker(),
                              const SizedBox(height: 16),
                              if (!_exporting &&
                                  _connected! &&
                                  _publicStoreUrl != null) ...[
                                qrControls(),
                              ],
                              const SizedBox(height: 12),
                              if (_connected!) ...[urlButton(context)],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _connected!
                          ? Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: previewPane(),
                              ),
                            )
                          : Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Center(
                                      child: Text(
                                        "コネクトアカウントを作成すると、\n QRコードを含んだポスターを作成することができます",
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ],
                  ),
                );
              } else {
                if (waitingConnect) const LinearProgressIndicator(minHeight: 2);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (waitingConnect)
                        const LinearProgressIndicator(minHeight: 2), // ← こう
                      connectNotice(),
                      if (_connected!) ...[
                        paperSelector(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: pdfButton()),
                            const SizedBox(width: 12),
                            Expanded(child: uploadButton(isC: isC)),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      posterPicker(),
                      const SizedBox(height: 16),
                      previewPane(),

                      const SizedBox(height: 16),
                      if (!_exporting &&
                          _connected! &&
                          _publicStoreUrl != null) ...[
                        qrControls(),
                      ],
                      const SizedBox(height: 12),
                      if (_connected!) ...[urlButton(context)],
                    ],
                  ),
                );
              }
            },
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

class _SliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool displayAsPercent;
  final ValueChanged<double> onChanged;
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.displayAsPercent = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = displayAsPercent
        ? '${(value * 100).toStringAsFixed(0)}%'
        : value.toStringAsFixed(0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      textColor: Colors.black87,
      title: Text(label, style: const TextStyle(color: Colors.black87)),
      subtitle: Slider(value: value, min: min, max: max, onChanged: onChanged),
      trailing: SizedBox(
        width: 56,
        child: Text(
          text,
          textAlign: TextAlign.end,
          style: const TextStyle(fontFamily: 'LINEseed'),
        ),
      ),
    );
  }
}
