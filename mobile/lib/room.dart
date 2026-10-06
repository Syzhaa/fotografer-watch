import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Room aktif untuk sesi foto: dibuat sekali di awal,
/// semua foto masuk ke room ini. Ada QR + link buat dibagikan.
class RoomManager extends ChangeNotifier {
  RoomManager._();
  static final RoomManager instance = RoomManager._();

  static const _kRoomId = 'fw_room_id';
  static const _kRoomPin = 'fw_room_pin';
  static const _kRoomLink = 'fw_room_link';
  static const _kRoomExp = 'fw_room_exp';

  String? _roomId;
  String? _pin;
  String? _link;
  String? _expiresAt;

  String? get roomId => _roomId;
  String? get pin => _pin;
  String? get link => _link;
  String? get expiresAt => _expiresAt;
  bool get hasRoom => _roomId != null && _roomId!.isNotEmpty;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _roomId = p.getString(_kRoomId);
    _pin = p.getString(_kRoomPin);
    _link = p.getString(_kRoomLink);
    _expiresAt = p.getString(_kRoomExp);
    notifyListeners();
  }

  Future<void> createRoom(int expiryMinutes) async {
    final r = await FotoApi.instance.createRoom(
        expiryMinutes: expiryMinutes);
    _roomId = r['id'].toString();
    _pin = (r['pin'] ?? '').toString();
    _expiresAt = (r['expires_at'] ?? '').toString();
    try {
      _link = await FotoApi.instance.roomLink(_roomId!);
    } catch (_) {
      _link = 'https://ambilfile.web.id/room.html?id=$_roomId';
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRoomId, _roomId!);
    await p.setString(_kRoomPin, _pin ?? '');
    await p.setString(_kRoomLink, _link ?? '');
    await p.setString(_kRoomExp, _expiresAt ?? '');
    notifyListeners();
  }

  Future<void> clearRoom() async {
    _roomId = _pin = _link = _expiresAt = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRoomId);
    await p.remove(_kRoomPin);
    await p.remove(_kRoomLink);
    await p.remove(_kRoomExp);
    notifyListeners();
  }
}
