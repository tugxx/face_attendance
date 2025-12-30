import 'package:get/get.dart';
import '../modules/face_attendance/bindings/face_attendance_binding.dart';
import '../modules/face_attendance/views/face_attendance_view.dart';
import 'app_routes.dart';

class AppPages {
  static const initial = Routes.faceAttendance;

  static final routes = [
    GetPage(
      name: Routes.faceAttendance,
      page: () => const FaceAttendanceView(), // (Frontend UI) Vẽ giao diện lên màn hình.
      binding: FaceAttendanceBinding(), // (Backend logic) Khởi tạo các Controller, Service cần thiết cho màn hình này trước hoặc ngay khi màn hình được vẽ.
    ),
  ];
}