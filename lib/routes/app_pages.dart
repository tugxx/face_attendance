import 'package:get/get.dart';

import '../presentation/controllers/face_attendance_controller.dart';
import '../presentation/views/face_attendance_view.dart';
import '../presentation/views/home_view.dart';
import '../presentation/controllers/home_controller.dart';
import '../presentation/controllers/face_register_controller.dart';
import '../presentation/views/face_register_view.dart';
import '../presentation/controllers/login_controller.dart';
import '../presentation/views/login_view.dart';
import '../presentation/controllers/register_account_controller.dart';
import '../presentation/views/register_account_view.dart';
import 'app_routes.dart';

class AppPages {
  AppPages._();

  static const initial = Routes.login;

  // TRANG CHỦ
  static final routes = [
    // ==========================================
    // AUTHENTICATION
    // ==========================================
    GetPage(
      name: Routes.login,
      page: () => const LoginView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => LoginController())),
      // Transition: Animation khi chuyển trang (tùy chọn)
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.register,
      page: () => const RegisterAccountView(),
      binding: BindingsBuilder(
        () => Get.lazyPut(() => RegisterAccountController()),
      ),
      transition: Transition.rightToLeft,
    ),

    // ==========================================
    // MAIN APP
    // ==========================================
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: BindingsBuilder(() {
        Get.lazyPut(() => HomeController());
      }),
    ),

    // ==========================================
    // FEATURES
    // ==========================================

    // TRANG NHẬN DIỆN KHUÔN MẶT
    GetPage(
      name: Routes.faceAttendance,
      page: () => const FaceAttendanceView(),
      binding: BindingsBuilder(() {
        Get.lazyPut<FaceAttendanceController>(() => FaceAttendanceController());
      }),
    ),

    // TRANG ĐĂNG KÝ KHUÔN MẶT
    GetPage(
      name: Routes.faceRegister,
      page: () => const FaceRegisterView(),
      binding: BindingsBuilder(() {
        // LazyPut: Chỉ khởi tạo Controller khi vào màn hình này
        Get.lazyPut<FaceRegisterController>(() => FaceRegisterController());
      }),
    ),
  ];
}
