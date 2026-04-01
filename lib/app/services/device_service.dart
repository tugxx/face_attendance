import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/log_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  String _currentDeviceId = "UNKNOWN_DEVICE";

  // Hàm này gọi 1 lần ở màn hình Home (lúc khởi tạo các dịch vụ ngầm)
  Future<void> initDeviceName() async {
    final box = await Hive.openBox('SettingsBox'); // Két chuyên chứa cài đặt

    // Kiểm tra xem máy này đã từng được Admin đặt tên chưa?
    String? savedName = box.get('device_id');

    if (savedName != null) {
      // Nếu có rồi thì cứ thế mà dùng
      _currentDeviceId = savedName;
    } else {
      // Nếu là lần đầu cài App -> Tự động lấy tên máy nguyên bản
      _currentDeviceId = await _getRawDeviceName();

      // Lưu tạm tên gốc này vào két để dùng tạm
      await box.put('device_id', _currentDeviceId);
    }

    AppLog.info("📱 Device ID hiện tại: $_currentDeviceId");
  }

  // Getter để các hàm khác (như SyncService) gọi lấy tên máy
  String get deviceId => _currentDeviceId;

  // Hàm dành cho Màn hình Cài Đặt (Admin gõ tên mới vào đây)
  Future<void> updateDeviceName(String customName) async {
    final box = Hive.box('SettingsBox');
    await box.put('device_id', customName);
    _currentDeviceId = customName;
  }

  // Hàm chui xuống hệ điều hành lấy tên máy thật
  Future<String> _getRawDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Kết quả ví dụ: "samsung SM-N950F" (Note 8)
        return "${androidInfo.brand}_${androidInfo.model}".replaceAll(' ', '_');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // Kết quả ví dụ: "Apple iPad8,1"
        return "Apple_${iosInfo.utsname.machine}".replaceAll(' ', '_');
      }
    } catch (e) {
      return "Generic_Device_${DateTime.now().millisecondsSinceEpoch}";
    }
    return "Unknown_Device";
  }
}
