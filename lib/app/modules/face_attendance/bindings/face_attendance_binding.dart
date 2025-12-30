import 'package:get/get.dart';
import '../controllers/face_attendance_controller.dart';

class FaceAttendanceBinding extends Bindings {
  @override
  void dependencies() {
    // LazyPut: Chỉ khởi tạo Controller khi màn hình này được mở -> Tiết kiệm RAM
    Get.lazyPut<FaceAttendanceController>(() => FaceAttendanceController());
  }
}