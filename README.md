# Fotografer Watch 📸

Aplikasi pendamping AmbilFile khusus fotografer: jepret/pantau foto → otomatis diproses 3 versi → upload ke AmbilFile.

## Alur

```
[Kamera / Folder dipantau]
        ↓
   asli/      → file original apa adanya
   compress/  → max 1920px, JPEG 82
   publik/    → compress + bingkai + watermark
        ↓
  Upload via API key → Room AmbilFile (link share)
```

## Struktur

```
fotografer-watch/
├── mobile/    → Android (kamera + pantau folder)
└── desktop/   → Windows (pantau folder) — menyusul
```

## Tab

- **Kamera** — jepret langsung di app, foto masuk antrian
- **Pantau** — awasi folder (default DCIM/Camera), foto baru otomatis diproses
- **Antrian** — status tiap foto: proses → upload → selesai (link share)
- **Atur** — API key AmbilFile, teks watermark, info folder kerja

## Syarat

1. Minta **API key** ke admin via aplikasi AmbilFile (tab API Key)
2. Masukkan API key di tab Atur
3. Atur teks watermark (cth: `© Studio Foto`)

## Build Android

```bash
cd mobile
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## Catatan

- Tiap foto diupload ke **room baru** (berlaku 1 hari) — link share per foto
- Butuh izin kamera & akses media saat pertama jalan
- Folder kerja: `<storage>/FotograferWatch/{asli,compress,publik}/`
