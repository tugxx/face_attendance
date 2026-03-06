import 'package:get/get.dart';

import '../../app/config/app_routes.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/services/face_antispoofing_service.dart';
import '../../app/types/face_progress.dart';
import '../../app/services/log_service.dart';
import '../../app/services/face_isolate_service.dart';

class HomeController extends GetxController {
  var isLoadingAI = false.obs;

  Future<bool> _ensureAiReady({required bool needSpoof}) async {
    isLoadingAI.value = true;

    try {
      // 1. NẠP CORE AI (Bắt buộc cho cả 2 màn hình)
      if (!Get.isRegistered<FaceRecognitionService>()) {
        AppLog.info("⏳ Đang khởi tạo Core AI & Isolate...");
        FaceProcessorNative.init();

        final aiService = FaceRecognitionService();
        await aiService.initialize();
        Get.put(aiService, permanent: true);

        final isolateService = FaceIsolateService();
        await isolateService.start();
        Get.put(isolateService, permanent: true);
      }

      // 2. NẠP ANTI-SPOOFING (Chỉ nạp nếu có yêu cầu VÀ chưa từng nạp trước đó)
      if (needSpoof && !Get.isRegistered<FaceAntiSpoofingService>()) {
        AppLog.info("⏳ Đang khởi tạo thêm Anti-Spoofing...");
        final spoofService = FaceAntiSpoofingService();
        await spoofService.initialize();
        Get.put(spoofService, permanent: true);
      }

      if (Get.isDialogOpen == true) {
        Get.back();
      }

      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi nạp AI: $e");
      Get.snackbar("Lỗi", "Không thể khởi tạo hệ thống AI: $e");
      return false;
    } finally {
      isLoadingAI.value = false;
    }
  }

  // Hàm điều hướng
  void goToRegister() async {
    bool isReady = await _ensureAiReady(needSpoof: false);
    if (isReady) {
      Get.toNamed(Routes.register);
    }
  }

  void goToAttendance() async {
    bool isReady = await _ensureAiReady(needSpoof: true);
    if (isReady) {
      Get.toNamed(Routes.faceAttendance);
    }
  }
}
