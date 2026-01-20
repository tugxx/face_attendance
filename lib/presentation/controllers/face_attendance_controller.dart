import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/types/face_progress.dart';

class FaceCheckinState {
  // Biến cấu hình
  static const int requiredRecognitionStreak =
      3; // Cần 3 lần nhận diện đúng tên
  static const int requiredLivenessStreak = 3; // Cần 3 lần check liveness OK

  // Biến trạng thái runtime
  String? currentCandidate; // Tên người đang theo dõi
  int matchStreak = 0; // Đếm số lần nhận diện đúng liên tiếp
  int livenessStreak = 0; // Đếm số lần liveness pass liên tiếp
  bool isSuccessCooldown = false; // Chế độ chờ sau khi điểm danh thành công

  void reset() {
    currentCandidate = null;
    matchStreak = 0;
    livenessStreak = 0;
  }
}

// Khởi tạo instance (Để trong Controller của bạn)
final checkinState = FaceCheckinState();

class FaceAttendanceController extends GetxController {
  CameraController? cameraController;
  final FaceRecognitionService _aiService = FaceRecognitionService();

  var isInitialized = false.obs; // Cờ báo hiệu Camera đã bật chưa.
  var recognizedName = "Unknown".obs;
  // Cái "khóa" (Lock/Semaphore) để ngăn không cho xử lý quá nhiều frame cùng lúc (tránh tràn RAM).
  var isProcessing = false.obs;
  var errorMsg = "".obs;

  bool _isDetecting = false;

  DateTime _lastRecognitionTime = DateTime.fromMillisecondsSinceEpoch(0);

  late FaceDetector _faceDetector;
  var detectedFaces = <Face>[].obs;
  CameraDescription? _currentCamera;

  // ------------------------------------------------------
  // HELPER
  // ------------------------------------------------------

  bool _shouldSkipRecognition() {
    // Nếu đang xử lý một khuôn mặt khác -> Skip
    if (isProcessing.value) return true;

    // Nếu chưa đủ 500ms kể từ lần nhận diện trước -> Skip
    final now = DateTime.now();
    if (now.difference(_lastRecognitionTime).inMilliseconds < 500) {
      return true;
    }
    return false;
  }

  Future<Face?> _detectFaceFromImage(CameraImage image) async {
    // 1. Chuyển đổi dữ liệu
    // Gọi hàm static từ Utils
    final inputImage = CameraUtils.convertCameraImageToInputImage(
      image,
      _currentCamera!,
    );
    // Nếu convert lỗi (do format lạ hoặc xoay không đúng) -> Bỏ qua frame này
    if (inputImage == null) return null;

    // 2. Gửi cho ML Kit xử lý
    final faces = await _faceDetector.processImage(inputImage);

    detectedFaces.assignAll(faces);

    if (faces.isEmpty) return null;

    final face = faces.first;
    // Lọc khuôn mặt quá nhỏ
    if (face.boundingBox.width < 80 || face.boundingBox.height < 80) {
      return null;
    }

    return face;
  }

  void _lockProcessing() {
    isProcessing.value = true;
    _lastRecognitionTime = DateTime.now();
  }

  // Future<String?> _generateDebugPath() async {
  //   try {
  //     final dir = await getExternalStorageDirectory();
  //     if (dir != null) {
  //       // 1. Đặt tên file cố định
  //       final String path = '${dir.path}/debug_face.jpg';

  //       // 2. In đường dẫn ra console để debug
  //       debugPrint("💾 File path: $path");

  //       return path;
  //     }
  //   } catch (e) {
  //     debugPrint("⚠️ Lỗi tạo đường dẫn: $e");
  //   }
  //   return null;
  // }

  Future<bool> _predictAntiSpoofing(List<double> facePixels) async {
    // TODO: Gọi model Anti-Spoofing của bạn ở đây
    // Return true nếu là người thật, false nếu là giả mạo
    await Future.delayed(const Duration(milliseconds: 10));
    return true;
  }

  Future<void> _performRecognition(
    List<double> facePixels,
    Stopwatch sw,
  ) async {
    if (checkinState.isSuccessCooldown) {
      isProcessing.value = false;
      return;
    }

    if (facePixels.isEmpty) {
      debugPrint("⚠️ Lỗi: Dữ liệu khuôn mặt rỗng!");
      isProcessing.value = false;
      return;
    }

    int tStartAI = sw.elapsedMilliseconds;

    try {
      // ---------------------------------------------------------
      // TỐI ƯU 1: CHẠY SONG SONG (Parallel Execution)
      // Thay vì await từng cái, ta bắn cả 2 model cùng lúc
      // (Lưu ý: Tùy vào device, đôi khi chạy tuần tự nhanh hơn nếu GPU bị lock,
      // nhưng về mặt logic luồng thì code này gọn hơn).
      // ---------------------------------------------------------

      // Gọi nhận diện danh tính
      final futureIdentity = _aiService.predict(facePixels);

      // Gọi Liveness (Anti-Spoofing) luôn, không cần chờ ID
      final futureLiveness = _predictAntiSpoofing(facePixels);

      // Chờ cả 2 kết quả trả về
      final results = await Future.wait([futureIdentity, futureLiveness]);

      futureIdentity.then((recognition) {
        debugPrint("Độ similarity: ${recognition.distance}");
      });

      int tEndAI = sw.elapsedMilliseconds;
      debugPrint("3️⃣ AI Inference (2 Models): ${tEndAI - tStartAI} ms");

      final RecognitionResult idResult = results[0] as RecognitionResult;
      final bool isRealPerson = results[1] as bool;

      String detectedName = idResult.isUnknown ? "Unknown" : idResult.name;

      // ---------------------------------------------------------
      // TỐI ƯU 2: GỘP LOGIC (Combined Logic)
      // Điều kiện: Phải ĐÚNG NGƯỜI và PHẢI LÀ NGƯỜI THẬT cùng lúc
      // ---------------------------------------------------------

      if (detectedName != "Unknown" && isRealPerson) {
        // Nếu là người mới hoặc đang track dở người này
        if (detectedName == checkinState.currentCandidate) {
          checkinState.matchStreak++; // Tăng điểm tin cậy
        } else {
          // Đổi người -> Reset
          checkinState.currentCandidate = detectedName;
          checkinState.matchStreak = 1;
          debugPrint("🔄 Tracking new: $detectedName");
        }

        // TỐI ƯU 3: BỎ UI NẶNG (Get.snackbar)
        // Chỉ in log hoặc update biến nhẹ nhàng để UI tự build lại (dùng Obx/ValueListenable)
        debugPrint(
          "🚀 Verified: $detectedName | Progress: ${checkinState.matchStreak}/3",
        );

        // Đủ điều kiện check-in (Ví dụ: 3 lần liên tiếp đúng cả ID lẫn Liveness)
        if (checkinState.matchStreak >=
            FaceCheckinState.requiredRecognitionStreak) {
          await _handleCheckinSuccess(checkinState.currentCandidate!);
        }
      } else {
        // ❌ FAILED (Hoặc là Unknown, hoặc là Fake)
        if (!isRealPerson && detectedName != "Unknown") {
          debugPrint("⚠️ SPOOF DETECTED for $detectedName");
          // Có thể show cảnh báo nhỏ ở đây nếu cần thiết, nhưng đừng dùng Snackbar chặn màn hình
        }

        // Reset streak nếu đứt quãng
        checkinState.matchStreak = 0;
        // Không reset currentCandidate ngay để tránh UI nhấp nháy, chỉ reset điểm
      }
    } catch (e, stack) {
      debugPrint("❌ Error: $e");
      debugPrint('Stack trace: $stack');
    } finally {
      isProcessing.value = false; // Mở khóa luồng
    }
  }

  Future<void> _handleCheckinSuccess(String name) async {
    checkinState.isSuccessCooldown = true; // Khóa hệ thống

    debugPrint("🎉 CHECKIN SUCCESS: $name");

    Get.snackbar(
      "Điểm danh thành công",
      "Xin chào, $name!",
      backgroundColor: Colors.green,
      colorText: Colors.white,
      icon: const Icon(Icons.check_circle, color: Colors.white),
      duration: const Duration(seconds: 2),
    );

    // Gửi API log lên server tại đây...

    // Wait 3 giây rồi reset (Logic Python: success_mode active duration)
    await Future.delayed(const Duration(seconds: 3));

    checkinState.reset();
    checkinState.isSuccessCooldown = false; // Mở khóa lại
  }

  void _safeguardUnlock() async {
    // Logic mở khóa an toàn nếu bị kẹt
    if (isProcessing.value) {
      // Chỉ delay nhẹ để tránh spam UI nếu vừa fail xong
      await Future.delayed(const Duration(milliseconds: 500));
      // Check lại lần nữa xem đã có ai mở chưa, nếu chưa thì mở
      if (recognizedName.value == "Unknown") {
        isProcessing.value = false;
      }
    }
  }

  // ------------------------------------------------------
  // INIT FUNCTION
  // ------------------------------------------------------

  @override
  void onInit() async {
    super.onInit();

    try {
      // Bắt đầu quy trình khởi tạo
      isInitialized.value = false;

      // Khởi tạo Service Nhận diện khuôn mặt (Custom AI)
      // Đây là bước nạp Model (ví dụ: mobilefacenet.tflite) và dữ liệu nhân viên vào RAM.
      // Từ khóa 'await': Đợi nạp xong xuôi mới chạy dòng tiếp theo (tránh lỗi chưa load model mà đã dùng).
      await _aiService.initialize();

      // 2. Cấu hình ML Kit
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast, // Ưu tiên độ chính xác
          enableContours:
              false, // Không cần vẽ đường viền bao quanh mặt (giúp giảm tải xử lý nếu không dùng để vẽ UI).
          // Bật tìm các điểm mốc (Mắt, mũi, miệng, má...).
          // QUAN TRỌNG: Dùng để căn chỉnh (align) khuôn mặt cho thẳng trước khi đưa vào AI nhận diện.
          enableLandmarks: true,
          // Không cần phân loại (ví dụ: đang cười hay mở mắt), tắt đi cho nhẹ.
          enableClassification: false,
          minFaceSize: 0.15,
        ),
      );

      await startCamera();

      // Mọi thứ đã xong, giờ mới cho phép hiện UI Camera
      isInitialized.value = true;
    } catch (e) {
      errorMsg.value = "Lỗi khởi tạo: $e";
    }
  }

  Future<void> startCamera() async {
    // Reset lỗi cũ trước khi bắt đầu
    errorMsg.value = "";

    try {
      // 1. KIỂM TRA QUYỀN TRUY CẬP
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        errorMsg.value = "Vui lòng cấp quyền Camera";
        return;
      }

      // 2. TÌM KIẾM CAMERA KHẢ DỤNG
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        errorMsg.value = "Không tìm thấy Camera";
        return;
      }

      // 3. CHỌN CAMERA TRƯỚC (Ưu tiên Selfie)
      // Logic: Cố tìm cam trước, nếu không có thì lấy cam đầu tiên (cam sau)
      _currentCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // 4. CẤU HÌNH CONTROLLER
      cameraController = CameraController(
        _currentCamera!,
        ResolutionPreset.medium,
        enableAudio: false, // Tắt thu âm cho nhẹ, vì chấm công không cần tiếng
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup
                  .nv21 // Android
            : ImageFormatGroup.bgra8888, // iOS
      );

      // 5. KHỞI ĐỘNG PHẦN CỨNG
      await cameraController!.initialize();

      // 6. BẮT ĐẦU STREAM HÌNH ẢNH
      // Truyền hàm _processFrame vào để xử lý từng khung hình
      await cameraController!.startImageStream(processFrame);

      // 7. HOÀN TẤT
      // Chỉ khi stream chạy thành công mới báo UI hiển thị
      isInitialized.value = true;
    } catch (e) {
      // Bắt lỗi phần cứng (VD: Camera bị hỏng, bị chiếm dụng...)
      errorMsg.value = "Lỗi khởi động Camera: $e";
      isInitialized.value = false; // Đảm bảo UI không hiện khung camera đen
    }
  }

  void processFrame(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    // ⏱️ BẮT ĐẦU ĐỒNG HỒ
    final Stopwatch sw = Stopwatch()..start();

    Face? face;
    
    try {
      // 1. Detect khuôn mặt (ML Kit - Giữ nguyên)
      face = await _detectFaceFromImage(image);
      
    } catch (e) {
      debugPrint("Error detecting: $e");
    } finally {
      _isDetecting = false; // Luôn mở khóa detect
    }

    int tDetect = sw.elapsedMilliseconds;

    // Nếu không có mặt -> Dừng
    if (face == null) {
      if (checkinState.matchStreak > 0) {
        checkinState.matchStreak = 0;
        debugPrint("❌ Face lost. Reset streak.");
      }
      return;
    }

    // Log Detect (Nên < 80ms)
    debugPrint("1️⃣ Detect: ${tDetect}ms");

    // 2. Throttling (Giữ nguyên)
    if (_shouldSkipRecognition()) return;

    // 3. Khoá luồng xử lý nhận diện
    _lockProcessing();

    try {
      // 4. Chuẩn bị dữ liệu gửi sang Isolate
      // Copy YUV bytes (Phải copy vì CameraImage buffer sẽ bị hủy ở frame sau)
      final rawBytes = CameraUtils.cloneCameraBytes(image);

      // Tạo Request (Lưu ý: Bỏ các tham số cropW, cropH vì Dart Processor tự tính)
      final request = FaceProcessRequest(
        yuvBytes: rawBytes,
        width: image.width,
        height: image.height,
        face: face,
        sensorOrientation: _currentCamera!.sensorOrientation,
        isAndroid: Platform.isAndroid,
        rootToken: RootIsolateToken.instance,
      );

      // 5. Gửi sang Isolate -> Gọi C++ Native
      // Đo thời gian bắt đầu gửi
      int tStartCrop = sw.elapsedMilliseconds;

      // 5. Gửi sang Isolate (Xử lý ảnh bằng Dart thuần)
      // Input: YUV -> Output: List<double> (Pixels đã chuẩn hóa)
      debugPrint("🚀 Gửi task sang Isolate...");

      final List<double>? facePixels = await compute(
        isolateFaceProcessor,
        request,
      );

      int tEndCrop = sw.elapsedMilliseconds;
      int tCrop = tEndCrop - tStartCrop; // Thời gian thực tế của bước Crop

      // 6. Có kết quả từ Isolate -> Đưa vào Model
      if (facePixels != null) {
        await _performRecognition(facePixels, sw);

        int tTotal = sw.elapsedMilliseconds;

        debugPrint(
          "⏱️ [${tTotal}ms] "
          "Detect: ${tDetect}ms | "
          "Crop: ${tCrop}ms | "
          "AI: ${tTotal - tEndCrop}ms | "
          "FPS: ${(1000 / tTotal).toStringAsFixed(1)}",
        );
      } else {
        debugPrint("⚠️ Isolate trả về null (Do mặt nghiêng hoặc lỗi ảnh)");
        isProcessing.value = false;
      }
    } catch (e, s) {
      debugPrint("❌ Lỗi processFrame: $e");
      debugPrintStack(stackTrace: s);
      isProcessing.value = false;
    } finally {
      _safeguardUnlock(); // Đảm bảo an toàn

      // // Tổng kết thời gian 1 frame
      sw.stop();
    }
  }

  @override
  void onClose() {
    _faceDetector.close();
    cameraController?.stopImageStream();
    cameraController?.dispose();
    super.onClose();
  }
}
