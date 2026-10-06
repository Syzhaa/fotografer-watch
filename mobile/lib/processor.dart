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

  String? _workDir;
  String _watermark = '';
  int _frameColor = 0xFFFFFFFF; // putih

  String? get workDir => _workDir;
  String get watermark => _watermark;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _workDir = p.getString(_kWorkDir);
    _watermark = p.getString(_kWatermark) ?? '';
    _frameColor = p.getInt(_kFrameColor) ?? 0xFFFFFFFF;
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
    final final_ = _watermark.isNotEmpty
        ? _addWatermark(pub, _watermark)
        : pub;
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
