import 'package:get/get.dart';
import 'package:flutter/foundation.dart';

import '../../app/config/app_routes.dart';

class HomeController extends GetxController {
  // Hàm điều hướng
  void goToRegister() {
    // Tạm thời chưa có trang này, mình cứ log ra đã
    debugPrint("Navigating to Register...");
    // Get.snackbar("Thông báo", "Tính năng Đăng ký đang phát triển");
    Get.toNamed(Routes.register); // Sau này sẽ mở cái này
  }

  void goToDebug() {
    // Chuyển sang màn hình Camera hiện tại của bạn
    Get.toNamed(Routes.faceAttendance);
  }

  void goToAttendance() {
    debugPrint("Navigating to Attendance...");
    Get.snackbar("Thông báo", "Tính năng Chấm công đang phát triển");
    // Get.toNamed(Routes.attendance); // Sau này sẽ mở cái này
  }
}