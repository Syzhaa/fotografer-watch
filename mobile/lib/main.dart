import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';
import 'room.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'processor.dart';

const brand = Color(0xFFF6821F);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FotoApi.instance.init();
  await FotoProcessor.instance.init();
  await RoomManager.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fotografer Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF1F2937),
            elevation: 0),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _idx = 0;
  final _queueKey = GlobalKey<QueueScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _idx,
        children: [
          CameraScreen(onCaptured: (p) =>
              _queueKey.currentState?.addJob(p, fromCamera: true)),
          WatchScreen(onDetected: (p) =>
              _queueKey.currentState?.addJob(p)),
          QueueScreen(key: _queueKey),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: brand,
        unselectedItemColor: Colors.black45,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Kamera'),
          BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined),
              activeIcon: Icon(Icons.folder),
              label: 'Pantau'),
          BottomNavigationBarItem(
              icon: Icon(Icons.queue_outlined),
              activeIcon: Icon(Icons.queue),
              label: 'Antrian'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Atur'),
        ],
      ),
    );
  }
}

// ─── TAB KAMERA ───

class CameraScreen extends StatefulWidget {
  final void Function(String path) onCaptured;
  const CameraScreen({super.key, required this.onCaptured});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _ctrl;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(() => _error = 'Izin kamera ditolak.');
      return;
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Tidak ada kamera.');
        return;
      }
      _ctrl = CameraController(
          cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cams.first),
          ResolutionPreset.high,
          enableAudio: false);
      await _ctrl!.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = 'Kamera error: $e');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _snap() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    try {
      final x = await _ctrl!.takePicture();
      widget.onCaptured(x.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto masuk antrian proses 📸')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kamera',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: _error != null
          ? Center(child: Text(_error!))
          : !_ready
              ? const Center(
                  child: CircularProgressIndicator(color: brand))
              : Stack(
                  children: [
                    CameraPreview(_ctrl!),
                    Positioned(
                      bottom: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _snap,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 4),
                              color: brand,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─── TAB PANTAU FOLDER ───

class WatchScreen extends StatefulWidget {
  final void Function(String path) onDetected;
  const WatchScreen({super.key, required this.onDetected});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  StreamSubscription<FileSystemEvent>? _sub;
  bool _watching = false;
  String? _folder;
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final fp = FotoProcessor.instance;
    var wd = fp.watchDir;
    if (wd == null) {
      // default: DCIM/Camera
      final w = fp.workDir;
      if (w != null) {
        wd = '${Directory(w).parent.path}/DCIM/Camera';
        await fp.setWatchDir(wd);
      }
    }
    setState(() => _folder = wd);
  }

  Future<void> _pickFolder() async {
    if (_watching) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Berhentikan pantauan dulu')));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih folder yang dipantau',
    );
    if (dir == null) return;
    await FotoProcessor.instance.setWatchDir(dir);
    setState(() => _folder = dir);
    _seen.clear();
  }

  Future<void> _toggle() async {
    if (_watching) {
      await _sub?.cancel();
      setState(() => _watching = false);
      return;
    }
    if (_folder == null) return;
    final dir = Directory(_folder!);
    if (!await dir.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Folder tidak ditemukan')));
      return;
    }
    await for (final e in dir.list()) {
      if (e is File) _seen.add(e.path);
    }
    _sub = dir.watch().listen((ev) {
      if (ev is FileSystemCreateEvent ||
          ev is FileSystemModifyEvent) {
        final p = ev.path;
        if (_seen.contains(p)) return;
        final name = p.split(Platform.pathSeparator).last;
        // skip file temp kamera Android (.pending-*) & file hidden
        if (name.startsWith('.pending-') || name.startsWith('.')) return;
        final low = p.toLowerCase();
        if (!(low.endsWith('.jpg') ||
            low.endsWith('.jpeg') ||
            low.endsWith('.png'))) return;
        // tunggu file stabil (selesai ditulis) via cek ukuran
        _waitStable(p);
      }
    });
    setState(() => _watching = true);
  }

  /// Tunggu sampai ukuran file stabil 2x cek (kamera selesai nulis).
  Future<void> _waitStable(String p) async {
    try {
      var lastSize = -1;
      var stableCount = 0;
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final f = File(p);
        if (!await f.exists()) return; // file hilang (temp)
        final sz = await f.length();
        if (sz == lastSize && sz > 0) {
          stableCount++;
          if (stableCount >= 2) break;
        } else {
          stableCount = 0;
        }
        lastSize = sz;
      }
      if (_seen.contains(p)) return;
      final f = File(p);
      if (!await f.exists()) return;
      if (await f.length() == 0) return;
      _seen.add(p);
      widget.onDetected(p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pantau Folder',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.folder_open,
                size: 64, color: Colors.black26),
            const SizedBox(height: 16),
            const Text(
              'App mengawasi folder dan otomatis memproses foto baru yang masuk.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_folder ?? '...',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12)),
                  ),
                  TextButton.icon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open,
                        size: 18),
                    label: const Text('Ubah'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kamera bawaan otomatis masuk pipeline.\nKamera eksternal: arahkan penyimpanannya ke folder ini.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _watching ? Colors.red : brand,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12))),
                onPressed: _toggle,
                icon: Icon(
                    _watching
                        ? Icons.stop
                        : Icons.play_arrow,
                    color: Colors.white),
                label: Text(
                    _watching
                        ? 'Berhenti Memantau'
                        : 'Mulai Memantau',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (_watching) ...[
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: brand)),
                  SizedBox(width: 8),
                  Text('Mengawasi...',
                      style: TextStyle(
                          color: Colors.black54, fontSize: 13)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── TAB ANTRIAN ───

enum JobStatus { waiting, processing, uploading, done, failed }

class Job {
  final String src;
  final bool fromCamera;
  JobStatus status = JobStatus.waiting;
  String step = '';
  double progress = 0;
  String? error;
  String? shareLink;
  Job(this.src, {this.fromCamera = false});
}

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => QueueScreenState();
}

class QueueScreenState extends State<QueueScreen> {
  final List<Job> _jobs = [];
  bool _busy = false;

  void addJob(String path, {bool fromCamera = false}) {
    setState(() => _jobs.insert(0, Job(path, fromCamera: fromCamera)));
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      for (final job in _jobs) {
        if (job.status != JobStatus.waiting) continue;
        await _run(job);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _run(Job job) async {
    setState(() {
      job.status = JobStatus.processing;
      job.step = 'Menyiapkan...';
    });
    try {
      final pubPath = await FotoProcessor.instance.process(
        job.src,
        onStep: (s) => setState(() => job.step = {
              'asli': 'Menyimpan asli...',
              'compress': 'Mengompres...',
              'publik': 'Bingkai + watermark...',
            }[s] ?? s),
      );
      if (!FotoApi.instance.hasApiKey) {
        throw StateError('Isi API key dulu di tab Atur.');
      }
      final rm = RoomManager.instance;
      if (!rm.hasRoom) {
        throw StateError(
            'Buat room dulu (tombol di atas) sebelum upload.');
      }
      final roomId = rm.roomId!;
      setState(() {
        job.status = JobStatus.uploading;
        job.step = 'Mengupload...';
      });
      final name = pubPath.split(Platform.pathSeparator).last;
      await FotoApi.instance.uploadFile(roomId, pubPath, name,
          (sent, total) {
        setState(() {
          job.progress = total > 0 ? sent / total : 0;
          job.step =
              'Mengupload ${(job.progress * 100).toStringAsFixed(0)}%';
        });
      });
      setState(() {
        job.status = JobStatus.done;
        job.shareLink = rm.link;
        job.step = 'Selesai ✅';
      });
    } catch (e) {
      setState(() {
        job.status = JobStatus.failed;
        job.error = FotoApi.apiError(e);
      });
    }
  }

  Future<void> _buatRoom() async {
    if (!FotoApi.instance.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Isi API key dulu di tab Atur.')));
      return;
    }
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Masa aktif room',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final o in [
            [60, '1 jam'],
            [720, '12 jam'],
            [1440, '1 hari'],
            [10080, '7 hari'],
          ])
            ListTile(
              title: Text(o[1] as String),
              onTap: () => Navigator.pop(c, o[0] as int),
            ),
        ]),
      ),
    );
    if (minutes == null) return;
    try {
      await RoomManager.instance.createRoom(minutes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Room dibuat! PIN ${RoomManager.instance.pin}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: ${FotoApi.apiError(e)}')));
    }
  }

  Widget _roomCard() {
    return ListenableBuilder(
      listenable: RoomManager.instance,
      builder: (_, __) {
        final rm = RoomManager.instance;
        if (!rm.hasRoom) {
          return Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Belum ada room aktif.\nBuat room dulu biar foto punya tempat upload + QR buat dibagikan.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: brand,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                    onPressed: _buatRoom,
                    icon: const Icon(Icons.add,
                        color: Colors.white),
                    label: const Text('Buat Room',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    QrImageView(
                      data: rm.link ?? '',
                      version: QrVersions.auto,
                      size: 110,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('Room Aktif',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('PIN ${rm.pin}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2)),
                              IconButton(
                                icon: const Icon(Icons.copy,
                                    size: 18),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text: rm.pin ?? ''));
                                  ScaffoldMessenger.of(
                                          context)
                                      .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'PIN disalin')));
                                },
                              ),
                            ],
                          ),
                          if ((rm.expiresAt ?? '').isNotEmpty)
                            Text(
                                'Aktif sampai ${rm.expiresAt}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(rm.link ?? '',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54),
                          overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: rm.link ?? ''));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                                content:
                                    Text('Link disalin')));
                      },
                      child: const Text('Salin Link'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title:
                                const Text('Tutup room?'),
                            content: const Text(
                                'Foto berikutnya butuh room baru.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          c, false),
                                  child:
                                      const Text('Batal')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(c, true),
                                  child:
                                      const Text('Tutup')),
                            ],
                          ),
                        );
                        if (yes == true) {
                          await RoomManager.instance
                              .clearRoom();
                        }
                      },
                      child: const Text('Tutup',
                          style:
                              TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Antrian',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _roomCard(),
          ),
          Expanded(
            child: _jobs.isEmpty
          ? const Center(
              child: Text('Belum ada foto.\nJepret via Kamera atau aktifkan Pantau Folder.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _jobs.length,
              itemBuilder: (_, i) {
                final j = _jobs[i];
                final name =
                    j.src.split(Platform.pathSeparator).last;
                return Card(
                  child: ListTile(
                    leading: _icon(j.status),
                    title: Text(name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                            j.status == JobStatus.failed
                                ? (j.error ?? 'Gagal')
                                : j.step,
                            style: TextStyle(
                                fontSize: 12,
                                color: j.status ==
                                        JobStatus.failed
                                    ? Colors.red
                                    : Colors.black54)),
                        if (j.status ==
                                JobStatus.processing ||
                            j.status == JobStatus.uploading)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: 6),
                            child: LinearProgressIndicator(
                                value: j.status ==
                                        JobStatus.uploading
                                    ? (j.progress > 0
                                        ? j.progress
                                        : null)
                                    : null,
                                color: brand,
                                backgroundColor:
                                    Colors.black12),
                          ),
                      ],
                    ),
                    trailing: j.status == JobStatus.failed
                        ? IconButton(
                            icon:
                                const Icon(Icons.refresh),
                            onPressed: () {
                              setState(() {
                                j.status =
                                    JobStatus.waiting;
                                j.error = null;
                              });
                              _pump();
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon(JobStatus s) {
    switch (s) {
      case JobStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green);
      case JobStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case JobStatus.waiting:
        return const Icon(Icons.schedule, color: Colors.grey);
      default:
        return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: brand));
    }
  }
}

// ─── TAB PENGATURAN ───

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiCtrl = TextEditingController();
  final _wmCtrl = TextEditingController();
  final _coupleCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _studioCtrl = TextEditingController();
  final _thanksCtrl = TextEditingController();
  bool _obscure = true;
  String _wmStyle = 'banner';

  @override
  void initState() {
    super.initState();
    final fp = FotoProcessor.instance;
    _apiCtrl.text = FotoApi.instance.apiKey ?? '';
    _wmCtrl.text = fp.watermark;
    _coupleCtrl.text = fp.couple;
    _dateCtrl.text = fp.wmDate;
    _studioCtrl.text = fp.studio;
    _thanksCtrl.text = fp.thanks;
    _wmStyle = fp.wmStyle;
  }

  Widget _wmField(TextEditingController c, String label,
      String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workDir = FotoProcessor.instance.workDir ?? '-';
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('API Key AmbilFile',
              style:
                  TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Minta ke admin via aplikasi AmbilFile (tab API Key).',
              style:
                  TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'ak_...',
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10))),
              onPressed: () async {
                await FotoApi.instance
                    .setApiKey(_apiCtrl.text);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('API key disimpan')));
              },
              child: const Text('Simpan',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Watermark Banner',
              style:
                  TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Model banner hijau ala undangan di bawah foto.',
              style:
                  TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Banner'),
                selected: _wmStyle == 'banner',
                selectedColor: brand.withOpacity(.2),
                onSelected: (_) =>
                    setState(() => _wmStyle = 'banner'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Simple'),
                selected: _wmStyle == 'simple',
                selectedColor: brand.withOpacity(.2),
                onSelected: (_) =>
                    setState(() => _wmStyle = 'simple'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _wmField(_coupleCtrl, 'Nama mempelai', 'cth: Ervaen & Mariatul'),
          _wmField(_dateCtrl, 'Tanggal', 'cth: 31.05.2026'),
          _wmField(_studioCtrl, 'Nama studio (kanan)',
              'cth: aisthetic'),
          _wmField(_thanksCtrl, 'Teks kiri',
              'cth: Thanks for coming!'),
          _wmField(_wmCtrl, 'Watermark simple (mode Simple)',
              'cth: © Studio Foto'),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: () async {
                await FotoProcessor.instance.setBanner(
                  couple: _coupleCtrl.text.trim(),
                  date: _dateCtrl.text.trim(),
                  studio: _studioCtrl.text.trim(),
                  thanks: _thanksCtrl.text.trim(),
                  style: _wmStyle,
                );
                await FotoProcessor.instance
                    .setWatermark(_wmCtrl.text.trim());
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Pengaturan watermark disimpan')));
              },
              child: const Text('Simpan Watermark'),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Folder kerja',
              style:
                  TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.black12)),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(workDir,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12)),
                const SizedBox(height: 6),
                const Text(
                    'Di dalamnya otomatis ada:\nasli/ • compress/ • publik/',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Center(
              child: Text('Fotografer Watch v1.0.0',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black38))),
        ],
      ),
    );
  }
}
