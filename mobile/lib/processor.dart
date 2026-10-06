import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pipeline foto: asli → compress → publik (bingkai + watermark).
/// Struktur output di bawah folder kerja:
///   <kerja>/asli/<nama>
///   <kerja>/compress/<nama>
///   <kerja>/publik/<nama>
class FotoProcessor {
  FotoProcessor._();
  static final FotoProcessor instance = FotoProcessor._();

  static const _kWorkDir = 'fw_work_dir';
  static const _kWatermark = 'fw_watermark';
  static const _kFrameColor = 'fw_frame_color';
  static const _kCouple = 'fw_couple';
  static const _kWmDate = 'fw_wm_date';
  static const _kStudio = 'fw_studio';
  static const _kThanks = 'fw_thanks';
  static const _kWmStyle = 'fw_wm_style'; // banner | simple
  static const _kWatchDir = 'fw_watch_dir';

  String? _workDir;
  String _watermark = '';
  int _frameColor = 0xFFFFFFFF; // putih
  String _couple = '';
  String _wmDate = '';
  String _studio = '';
  String _thanks = 'Thanks for coming!';
  String _wmStyle = 'banner';
  String? _watchDir;

  String? get workDir => _workDir;
  String get watermark => _watermark;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _workDir = p.getString(_kWorkDir);
    _watermark = p.getString(_kWatermark) ?? '';
    _frameColor = p.getInt(_kFrameColor) ?? 0xFFFFFFFF;
    _couple = p.getString(_kCouple) ?? '';
    _wmDate = p.getString(_kWmDate) ?? '';
    _studio = p.getString(_kStudio) ?? '';
    _thanks = p.getString(_kThanks) ?? 'Thanks for coming!';
    _wmStyle = p.getString(_kWmStyle) ?? 'banner';
    _watchDir = p.getString(_kWatchDir);
    // default: folder AmbilFile/Fotografer di storage
    if (_workDir == null) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        _workDir = '${ext.path}/FotograferWatch';
        await p.setString(_kWorkDir, _workDir!);
      }
    }
    if (_workDir != null) {
      for (final sub in ['asli', 'compress', 'publik']) {
        await Directory('$_workDir/$sub')
            .create(recursive: true);
      }
    }
  }

  Future<void> setWorkDir(String dir) async {
    _workDir = dir;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWorkDir, dir);
    for (final sub in ['asli', 'compress', 'publik']) {
      await Directory('$dir/$sub').create(recursive: true);
    }
  }

  Future<void> setWatermark(String text) async {
    _watermark = text;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWatermark, text);
  }

  String get couple => _couple;
  String get wmDate => _wmDate;
  String get studio => _studio;
  String get thanks => _thanks;
  String get wmStyle => _wmStyle;
  String? get watchDir => _watchDir;

  Future<void> setWatchDir(String dir) async {
    _watchDir = dir;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWatchDir, dir);
  }

  Future<void> setBanner(
      {String? couple,
      String? date,
      String? studio,
      String? thanks,
      String? style}) async {
    final p = await SharedPreferences.getInstance();
    if (couple != null) {
      _couple = couple;
      await p.setString(_kCouple, couple);
    }
    if (date != null) {
      _wmDate = date;
      await p.setString(_kWmDate, date);
    }
    if (studio != null) {
      _studio = studio;
      await p.setString(_kStudio, studio);
    }
    if (thanks != null) {
      _thanks = thanks;
      await p.setString(_kThanks, thanks);
    }
    if (style != null) {
      _wmStyle = style;
      await p.setString(_kWmStyle, style);
    }
  }

  String _baseName(String path) =>
      path.split(Platform.pathSeparator).last;

  String _withJpg(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }

  /// Proses satu file foto → kembalikan path file publik (siap upload).
  /// [onStep] dipanggil tiap tahap: 'asli' | 'compress' | 'publik'.
  Future<String> process(String srcPath,
      {void Function(String step)? onStep}) async {
    if (_workDir == null) throw StateError('Folder kerja belum diisi');
    final name = _baseName(srcPath);
    final jpgName = _withJpg(name);

    // 1. ASLI — copy apa adanya
    onStep?.call('asli');
    final asliPath = '$_workDir/asli/$name';
    await File(srcPath).copy(asliPath);

    // 2. Decode sekali untuk compress & publik
    final bytes = await File(srcPath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw StateError('File bukan gambar valid');

    // 3. COMPRESS — max 1920px sisi panjang, JPEG 82
    onStep?.call('compress');
    final comp = _resizeMax(image, 1920);
    final compPath = '$_workDir/compress/$jpgName';
    await File(compPath)
        .writeAsBytes(img.encodeJpg(comp, quality: 82));

    // 4. PUBLIK — compress + bingkai + watermark
    onStep?.call('publik');
    final pub = _addFrame(comp, 24, _frameColor);
    img.Image final_;
    if (_wmStyle == 'banner') {
      final_ = _addBanner(pub);
    } else if (_watermark.isNotEmpty) {
      final_ = _addWatermark(pub, _watermark);
    } else {
      final_ = pub;
    }
    final pubPath = '$_workDir/publik/$jpgName';
    await File(pubPath)
        .writeAsBytes(img.encodeJpg(final_, quality: 85));

    return pubPath;
  }

  img.Image _resizeMax(img.Image src, int maxSide) {
    final w = src.width, h = src.height;
    final longest = w > h ? w : h;
    if (longest <= maxSide) return src.clone();
    final scale = maxSide / longest;
    return img.copyResize(src,
        width: (w * scale).round(),
        height: (h * scale).round(),
        interpolation: img.Interpolation.linear);
  }

  img.Image _addFrame(img.Image src, int border, int color) {
    final out = img.Image(
        width: src.width + border * 2,
        height: src.height + border * 2);
    img.fill(out, color: img.ColorRgba8(
      (color >> 16) & 0xFF,
      (color >> 8) & 0xFF,
      color & 0xFF,
      (color >> 24) & 0xFF,
    ));
    img.compositeImage(out, src,
        dstX: border, dstY: border);
    return out;
  }

  /// Banner watermark ala undangan: strip hijau tua di bawah,
  /// label putih nama mempelai di tengah, thanks kiri, studio kanan.
  img.Image _addBanner(img.Image src) {
    final out = src.clone();
    final W = src.width, H = src.height;

    // --- strip hijau tua ---
    final green = img.ColorRgba8(27, 94, 59, 255); // #1b5e3b
    final cream = img.ColorRgba8(250, 247, 240, 255);
    final bannerH = (H * 0.13).round().clamp(90, 220);
    final by = H - bannerH;
    img.fillRect(out, x1: 0, y1: by, x2: W - 1, y2: H - 1, color: green);

    // garis tipis emas di atas banner
    final gold = img.ColorRgba8(212, 175, 105, 255);
    img.fillRect(out, x1: 0, y1: by, x2: W - 1, y2: by + 3, color: gold);

    final fontS = img.arial14;
    final fontM = img.arial24;

    // --- teks kiri: Thanks for coming! ---
    if (_thanks.isNotEmpty) {
      img.drawString(out, _thanks,
          font: fontM,
          x: (W * 0.04).round(),
          y: by + (bannerH ~/ 2) - 12,
          color: cream);
    }

    // --- teks kanan: nama studio ---
    if (_studio.isNotEmpty) {
      final approxW = _studio.length * 12;
      img.drawString(out, _studio,
          font: fontM,
          x: (W - approxW - W * 0.04).round().clamp(0, W - 10),
          y: by + (bannerH ~/ 2) - 12,
          color: cream);
    }

    // --- label putih tengah (model pita) ---
    final labelW = (W * 0.44).round().clamp(200, 900);
    final labelH = (bannerH * 1.55).round();
    final lx = (W - labelW) ~/ 2;
    final ly = by - ((labelH - bannerH) ~/ 2);
    final white = img.ColorRgba8(255, 255, 255, 255);
    final darkGreen = img.ColorRgba8(27, 94, 59, 255);

    // badan label
    img.fillRect(out,
        x1: lx + 18, y1: ly, x2: lx + labelW - 19, y2: ly + labelH - 1,
        color: white);
    // ujung kiri (segitiga)
    img.fillPolygon(out,
        vertices: [
          img.Point(lx + 18, ly),
          img.Point(lx, ly + labelH ~/ 2),
          img.Point(lx + 18, ly + labelH - 1),
        ],
        color: white);
    // ujung kanan (segitiga)
    img.fillPolygon(out,
        vertices: [
          img.Point(lx + labelW - 19, ly),
          img.Point(lx + labelW - 1, ly + labelH ~/ 2),
          img.Point(lx + labelW - 19, ly + labelH - 1),
        ],
        color: white);

    // --- teks di label ---
    final cx = lx + labelW ~/ 2;
    var ty = ly + (labelH * 0.14).round();

    // "The Wedding Of"
    img.drawString(out, 'The Wedding Of',
        font: fontS,
        x: cx - ('The Wedding Of'.length * 7 ~/ 2),
        y: ty,
        color: darkGreen);
    ty += 22;

    // Nama mempelai
    final couple = _couple.isNotEmpty ? _couple : 'Mempelai';
    img.drawString(out, couple,
        font: fontM,
        x: cx - (couple.length * 12 ~/ 2).clamp(0, cx - lx - 20),
        y: ty,
        color: darkGreen);
    ty += 32;

    // Tanggal
    if (_wmDate.isNotEmpty) {
      img.drawString(out, _wmDate,
          font: fontS,
          x: cx - (_wmDate.length * 7 ~/ 2),
          y: ty,
          color: darkGreen);
    }
    return out;
  }

  img.Image _addWatermark(img.Image src, String text) {
    final out = src.clone();
    // Bar bawah semi-transparan untuk teks
    final barH = (src.height * 0.09).round().clamp(48, 120);
    final bar = img.Image(width: src.width, height: barH);
    img.fill(bar, color: img.ColorRgba8(0, 0, 0, 140));
    img.compositeImage(out, bar,
        dstX: 0, dstY: src.height - barH);
    // Teks putih tengah bar
    final font = img.arial24;
    final tw = text.length * 13; // perkiraan lebar
    img.drawString(out, text,
        font: font,
        x: ((src.width - tw) / 2).round().clamp(8, src.width - 8),
        y: src.height - barH + (barH ~/ 4),
        color: img.ColorRgba8(255, 255, 255, 255));
    return out;
  }
}
