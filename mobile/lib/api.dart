import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client API AmbilFile untuk Fotografer Watch.
/// Upload pakai API key: buat room via /api/v1, lalu chunked upload ke /api/upload.
class FotoApi {
  FotoApi._();
  static final FotoApi instance = FotoApi._();

  static const _kApiKey = 'fw_api_key';
  static const _kBaseUrl = 'https://ambilfile.web.id';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'FotograferWatch/1.0'},
  ));

  String? _apiKey;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _apiKey = p.getString(_kApiKey);
  }

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kApiKey, _apiKey!);
  }

  Future<void> clearApiKey() async {
    _apiKey = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kApiKey);
  }

  Options get _auth => Options(headers: {
        'Authorization': 'Bearer $_apiKey',
      });

  /// POST /api/v1/room/create → {id, pin, ...}
  Future<Map<String, dynamic>> createRoom({int expiryMinutes = 1440}) async {
    if (!hasApiKey) throw StateError('API key belum diisi');
    final r = await _dio.post('/api/v1/room/create',
        data: {'expiry_minutes': expiryMinutes}, options: _auth);
    final d = r.data as Map<String, dynamic>;
    return d;
  }

  /// Tes API key: GET /api/v1/room/xxx/link (harus 404 bukan 401)
  /// Return null jika OK, pesan error jika gagal.
  Future<String?> testConnection() async {
    if (!hasApiKey) return 'API key belum diisi';
    try {
      await _dio.get('/api/v1/room/__test__/link', options: _auth);
      return null; // 200 (tidak mungkin)
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) return null; // key valid, room tidak ada = OK
      if (code == 401) {
        final msg = (e.response?.data is Map)
            ? (e.response!.data['error']?.toString() ?? '')
            : '';
        return 'API key ditolak server${msg.isNotEmpty ? ': $msg' : ''}';
      }
      return apiError(e);
    }
  }

  /// GET /api/v1/room/{id}/link → share link
  Future<String> roomLink(String roomId) async {
    final r = await _dio.get('/api/v1/room/$roomId/link', options: _auth);
    final d = r.data as Map<String, dynamic>;
    return (d['link'] ?? d['url'] ?? '').toString();
  }

  /// Chunked upload 5MB ke /api/upload/{roomId}
  /// onProgress(bytesSent, totalBytes)
  Future<void> uploadFile(
    String roomId,
    String filePath,
    String fileName,
    void Function(int sent, int total) onProgress,
  ) async {
    final file = await _readFile(filePath);
    final total = file.length;
    const chunkSize = 5 * 1024 * 1024;
    final fileId = _newFileId(fileName);
    final totalChunks = (total / chunkSize).ceil();

    int sent = 0;
    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      var end = start + chunkSize;
      if (end > total) end = total;
      final chunk = file.sublist(start, end);

      var ok = false;
      DioException? lastErr;
      for (var attempt = 0; attempt < 6 && !ok; attempt++) {
        try {
          final form = FormData.fromMap({
            'chunk': MultipartFile.fromBytes(chunk, filename: 'chunk'),
            'chunk_index': i,
            'total_chunks': totalChunks,
            'file_id': fileId,
            'filename': fileName,
          });
          await _dio.post('/api/upload/$roomId',
              data: form,
              options: Options(
                headers: {'Authorization': 'Bearer $_apiKey'},
                sendTimeout: const Duration(minutes: 5),
                receiveTimeout: const Duration(minutes: 2),
              ));
          ok = true;
        } on DioException catch (e) {
          lastErr = e;
          if (e.response?.statusCode == 413) rethrow;
          if (attempt == 5) break;
          // backoff: 2, 4, 8, 16, 32 detik
          await Future.delayed(Duration(seconds: 2 << attempt));
        }
      }
      if (!ok) {
        throw lastErr ??
            StateError('Upload gagal setelah 6x percobaan');
      }
      sent = end;
      onProgress(sent, total);
    }
  }

  Future<List<int>> _readFile(String path) async {
    return File(path).readAsBytes();
  }

  String _newFileId(String name) {
    final t = DateTime.now().millisecondsSinceEpoch;
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${t}_$safe'.substring(
        0, '${t}_$safe'.length > 128 ? 128 : '${t}_$safe'.length);
  }

  static String apiError(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] != null) return d['error'].toString();
      if (e.response?.statusCode == 401) return 'API key salah / tidak valid';
      if (e.type == DioExceptionType.connectionError) {
        return 'Tidak bisa terhubung ke server. Cek internet lalu coba lagi.';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Koneksi timeout. Cek internet lalu coba lagi.';
      }
      return 'Jaringan bermasalah (${e.type.name})';
    }
    if (e is StateError) return e.message;
    return e.toString();
  }
}
