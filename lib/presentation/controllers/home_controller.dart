import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../routes/app_routes.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/services/face_antispoofing_service.dart';
import '../../app/types/face_pipeline.dart';
import '../../app/services/log_service.dart';
import '../../app/services/face_isolate_service.dart';
import '../../app/services/sync_service.dart';
import '../../app/services/web_socket_service.dart';
import '../../app/extensions/app_profiler.dart';
import '../../app/services/device_service.dart';
import '../../app/services/face_quality_service.dart';

class HomeController extends GetxController {
  var isLoadingAI = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Vừa vào Home là kích hoạt các dịch vụ ngầm ngay
    _initAuthenticatedServices();
  }

  Future<void> _initAuthenticatedServices() async {
    try {
      AppLog.info("⚙️ [HOME-INIT]: Bắt đầu nạp dịch vụ ngầm...");

      // 1. Mở các Box cần thiết cho phiên đăng nhập này
      await AppProfiler.measureAsync('Open_Hive_Boxes', () async {
        await Future.wait([
          Hive.openBox('face_db'),
          Hive.openBox('AttendanceBox'),
          Hive.openBox('SettingsBox'),
        ]);
      });

      await AppProfiler.measureAsync('Device_Name_Init', () async {
        await DeviceService().initDeviceName();
      });

      // 2. Khởi động dịch vụ đồng bộ ngầm
      AppProfiler.measureAsync('Background_Network_Services', () async {
        SyncService().init();
      });

      AppLog.info("✅ [HOME-INIT]: Luồng khởi tạo Home hoàn tất siêu tốc!");
    } catch (e) {
      AppLog.error("Lỗi khi nạp dịch vụ ngầm: $e");
    }
  }

  Future<bool> _ensureAiReady({required bool needSpoof}) async {
    isLoadingAI.value = true;

    try {
      // 1. NẠP CORE AI (Bắt buộc cho cả 2 màn hình)
      if (!Get.isRegistered<FaceRecognitionService>()) {
        await AppProfiler.measureAsync('Face_Native_Init', () async {
          FaceImagePipelineNative.init();
        });

        await AppProfiler.measureAsync('Parallel_AI_Init', () async {
          final aiService = FaceRecognitionService();
          final isolateService = FaceIsolateService();

          await Future.wait([aiService.initialize(), isolateService.start()]);

          Get.put(aiService, permanent: true);
          Get.put(isolateService, permanent: true);
        });
      }

      if (!Get.isRegistered<FaceQualityAssessor>()) {
        AppLog.info("⏳ Đang khởi tạo Face Quality Model (LightQNet)...");
        await AppProfiler.measureAsync('Face_Quality_Init', () async {
          final qualityService =
              FaceQualityAssessor(); // Class bọc FaceQualityAssessor
          await qualityService.initialize();
          Get.put(qualityService, permanent: true);
        });
      }

      // 2. NẠP ANTI-SPOOFING (Chỉ nạp nếu có yêu cầu VÀ chưa từng nạp trước đó)
      if (needSpoof && !Get.isRegistered<FaceAntiSpoofingService>()) {
        AppLog.info("⏳ Đang khởi tạo thêm Anti-Spoofing...");
        await AppProfiler.measureAsync(
          'face anti spoofing initialize',
          () async {
            final spoofService = FaceAntiSpoofingService();
            await spoofService.initialize();
            Get.put(spoofService, permanent: true);
          },
        );
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
      Get.toNamed(Routes.faceRegister);
    }
  }

  void goToAttendance() async {
    bool isReady = await _ensureAiReady(needSpoof: true);
    if (isReady) {
      Get.toNamed(Routes.faceAttendance);
    }
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
