import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../routes/app_routes.dart';
import '../../app/services/log_service.dart';
import '../../app/services/sync_service.dart';
import '../../app/services/web_socket_service.dart';
import '../../app/extensions/app_profiler.dart';
import '../../app/services/device_service.dart';

class HomeController extends GetxController {
  var isLoadingAI = true.obs;

  @override
  void onInit() {
    super.onInit();
    // Vừa vào Home là kích hoạt các dịch vụ ngầm ngay
    _initAuthenticatedServices();
  }

  Future<void> _initAuthenticatedServices() async {
    try {
      await AppProfiler.measureAsync('Device_Name_Init', () async {
        await DeviceService().initDeviceName();
      });

      // 1. Mở các Box cần thiết cho phiên đăng nhập này
      await AppProfiler.measureAsync('Open_Hive_Boxes', () async {
        await Future.wait([
          Hive.openBox('face_db'),
          Hive.openBox('AttendanceBox'),
          Hive.openBox('SettingsBox'),
        ]);
      });

      // 2. Khởi động dịch vụ đồng bộ ngầm
      AppProfiler.measureAsync('Background_Network_Services', () async {
        SyncService().init();
      });
    } catch (e) {
      AppLog.error("Lỗi khi nạp dịch vụ ngầm: $e");
    } finally {
      // 3. MỞ KHÓA RÀO CHẮN (Bắt buộc phải có finally để luôn mở khóa dù có lỗi)
      isLoadingAI.value = false;
    }
  }

  // Hàm điều hướng
  void goToRegister() async {
    Get.toNamed(Routes.faceRegister);
  }

  void goToAttendance() async {
    Get.toNamed(Routes.faceAttendance);
  }

  @override
  void onClose() {
    // Khi thoát Home (Ví dụ người dùng Logout), dọn dẹp mọi thứ
    SyncService().dispose();
    WebSocketService().dispose();

    // Đóng Box lại để bảo mật và tiết kiệm RAM
    Hive.box('AttendanceBox').close();

    super.onClose();
  }
}
