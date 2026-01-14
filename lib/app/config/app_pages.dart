import 'package:get/get.dart';

import '../../presentation/controllers/face_attendance_controller.dart';
import '../../presentation/views/face_attendance_view.dart';
import '../../presentation/views/home_view.dart';
import '../../presentation/controllers/home_controller.dart';
import '../../presentation/controllers/face_register_controller.dart';
import '../../presentation/views/face_register_view.dart';
import 'app_routes.dart';

class AppPages {
  static const initial = Routes.home;

  // TRANG CHỦ
  static final routes = [
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: BindingsBuilder(() {
        Get.lazyPut(() => HomeController());
      }),
    ),

    // TRANG DEBUG
    GetPage(
      name: Routes.faceAttendance,
      page: () => const FaceAttendanceView(),
      binding: BindingsBuilder(() {
        Get.lazyPut<FaceAttendanceController>(() => FaceAttendanceController());
      }),
    ),

    // 3. TRANG ĐĂNG KÝ (MỚI THÊM) 👇
    GetPage(
      name: Routes.register,
      page: () => const FaceRegisterView(),
      binding: BindingsBuilder(() {
        // LazyPut: Chỉ khởi tạo Controller khi vào màn hình này
        Get.lazyPut<FaceRegisterController>(() => FaceRegisterController());
      }),
    ),
  ];
}
