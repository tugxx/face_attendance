import 'dart:io';
import 'dart:ffi';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffi/ffi.dart';

import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/services/log_service.dart';
import '../../data/models/registration_result.dart';
import '../../app/services/face_isolate_service.dart';

class FaceRegisterController extends GetxController {
  CameraController? cameraController;
  final FaceRecognitionService _aiService = Get.find<FaceRecognitionService>();
  final FaceIsolateService _isolateRegistrationService =
      Get.find<FaceIsolateService>();
  late FaceDetector _faceDetector;

  var isInitialized = false.obs;
  var detectedFaces = <Face>[].obs;
  var errorMsg = "".obs;

  // Trạng thái: Đang chờ đăng ký hay đã chụp xong
  var isRegistering = false.obs;
  var faceInstruction = "".obs;

  var registrationStep = 0.obs;

  CameraDescription? _currentCamera;
  bool _isDetecting = false;

  // Biến đếm ngược để tránh chụp quá nhanh khi vừa vào
  int _stableFrameCount = 0;
  static const int _requiredStableFrames =
      3; // Cần giữ mặt ổn định trong 3 frame

  List<List<double>> capturedVectors = [];

  Uint8List? frontFaceImage;

  Pointer<Uint8>? nativeBuffer;
  int _currentBufferSize = 0;

  var showDuplicateDialog = false.obs; // Bật/tắt Dialog trùng lặp
  var showNewUserDialog = false.obs; // Bật/tắt Dialog nhập tên người mới

  var tempAiPixels = <double>[];
  var tempDisplayBytes = Uint8List(0).obs;
  var tempRecognizedName = "".obs;
  var tempConfidence = 0.0.obs;

  var tempAllVectors = <List<double>>[];

  var frameColor = Colors.white70.obs;
  var scanProgress = 0.0.obs;

  final isSuccess = false.obs;

  // Trả về điểm số độ nét. Điểm càng cao ảnh càng sắc nét.
  (double, double) _calculateFaceQuality(CameraImage image, Face face) {
    try {
      final yPlane = image.planes[0].bytes;
      final width = image.width;
      final height = image.height;

      // Lấy tọa độ khuôn mặt (mở rộng một chút xíu để lấy cả đường viền mặt)
      int left = face.boundingBox.left.toInt().clamp(0, width - 1);
      int top = face.boundingBox.top.toInt().clamp(0, height - 1);
      int right = face.boundingBox.right.toInt().clamp(0, width - 1);
      int bottom = face.boundingBox.bottom.toInt().clamp(0, height - 1);

      if (right <= left || bottom <= top) return (0.0, 0.0);

      int sumLaplacian = 0;
      int sumSqLaplacian = 0;
      int sumBrightness = 0;
      int count = 0;

      // Tính Laplacian: L(x,y) = 4*I(x,y) - I(x-1,y) - I(x+1,y) - I(x,y-1) - I(x,y+1)
      // Bác nhảy bước (+= 2) để giảm một nửa số vòng lặp, tăng tốc độ tính toán
      for (int y = top + 1; y < bottom - 1; y += 2) {
        for (int x = left + 1; x < right - 1; x += 2) {
          int idx = y * width + x;

          // 1. Tính độ sáng pixel hiện tại
          int pixelValue = yPlane[idx];
          sumBrightness += pixelValue;

          // Lấy giá trị pixel hiện tại và 4 pixel xung quanh
          int val =
              (4 * pixelValue) -
              yPlane[idx - 1] -
              yPlane[idx + 1] -
              yPlane[idx - width] -
              yPlane[idx + width];

          sumLaplacian += val;
          sumSqLaplacian += val * val;
          count++;
        }
      }

      if (count == 0) return (0.0, 0.0);

      double meanLap = sumLaplacian / count;
      double sharpness = (sumSqLaplacian / count) - (meanLap * meanLap);

      double meanBrightness = sumBrightness / count;

      return (sharpness, meanBrightness);
    } catch (e) {
      return (0.0, 0.0);
    }
  }

  // Hàm phụ trợ để xử lý kết quả và thông báo
  void _handleResult(bool success, String message) async {
    if (success) {
      isSuccess.value = true;
      isRegistering.value = false;

      Get.snackbar(
        "Thành công",
        message,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(milliseconds: 3000),
      );

      // 🛑 2. Đợi 3.0 giây cho người dùng đọc thông báo rồi mới thoát
      await Future.delayed(const Duration(milliseconds: 3000));

      if (Get.isSnackbarOpen) {
        Get.closeCurrentSnackbar();
      }

      Get.until((route) => route.isFirst);
    } else {
      isRegistering.value = false;
      Get.snackbar("Lỗi", "Thao tác thất bại");
      _resumeCamera();
    }
  }

  bool _checkFaceQuality(
    Face face,
    int imageWidth,
    int imageHeight,
    CameraImage image,
  ) {
    // 1. TÍNH TOÁN KÍCH THƯỚC ĐỘNG
    // Lấy cạnh ngắn nhất của bức ảnh (chiều rộng màn hình)
    final shortEdge = min(imageWidth, imageHeight);

    // Khung Oval chiếm 70% màn hình.
    // -> Mặt lý tưởng nhất nên chiếm khoảng 40% đến 60% màn hình.
    final minFaceWidth = shortEdge * 0.40; // Mặt quá nhỏ
    final maxFaceWidth = shortEdge * 0.75; // Mặt quá to (tràn Oval)

    final faceWidth = face.boundingBox.width;

    if (faceWidth < minFaceWidth) {
      faceInstruction.value = "Hãy đưa mặt lại gần khung ";
      frameColor.value = Colors.orangeAccent;
      return false;
    }
    if (faceWidth > maxFaceWidth) {
      faceInstruction.value = "Khuôn mặt quá lớn, hãy lùi ra xa một chút";
      frameColor.value = Colors.orangeAccent;
      return false;
    }

    // ✅ CHECK ĐỘ NÉT TRƯỚC KHI CHECK GÓC
    final (sharpness, brightness) = _calculateFaceQuality(image, face);

    // Cảnh báo nếu môi trường tối thui (Tránh AI nhận diện sai bét)
    if (brightness < 40.0) {
      faceInstruction.value = "Môi trường quá tối, vui lòng tìm nơi sáng hơn!";
      frameColor.value = Colors.orangeAccent;
      return false;
    }

    // ✅ THUẬT TOÁN NGƯỠNG ĐỘNG (DYNAMIC THRESHOLD)
    // Ánh sáng 255 (Max) -> Ngưỡng đòi hỏi = 35.0
    // Ánh sáng 50 (Tối) -> Ngưỡng đòi hỏi = 12.0
    double dynamicThreshold = (brightness / 255.0) * 35.0;

    dynamicThreshold = dynamicThreshold.clamp(12.0, 35.0);

    AppLog.info(
      "Sáng: ${brightness.toStringAsFixed(1)} | Nét: ${sharpness.toStringAsFixed(1)} | Ngưỡng yêu cầu: ${dynamicThreshold.toStringAsFixed(1)}",
    );

    if (sharpness < dynamicThreshold) {
      faceInstruction.value = "Ảnh bị mờ, hãy giữ yên hoặc lau ống kính!";
      frameColor.value =
          Colors.yellowAccent; // Hoặc dùng màu vàng cho khác biệt
      return false;
    }

    final double? yaw = face.headEulerAngleY; // Trái/Phải
    if (yaw == null) return false;

    // 3. Logic hướng dẫn theo từng bước
    if (registrationStep.value == 0) {
      if (yaw > -10 && yaw < 10) {
        faceInstruction.value = "Giữ yên để chụp ảnh chính diện";
        frameColor.value = Colors.greenAccent;
        return true; // Mặt đang nhìn thẳng chuẩn
      } else {
        faceInstruction.value = "Vui lòng nhìn thẳng vào màn hình";
        frameColor.value = Colors.redAccent;
        return false;
      }
    } else if (registrationStep.value == 1) {
      if (yaw > 15) {
        // Âm là quay sang trái
        faceInstruction.value = "Giữ yên góc trái";
        frameColor.value = Colors.greenAccent;
        return true;
      } else {
        faceInstruction.value = "Từ từ quay mặt sang trái";
        frameColor.value = Colors.redAccent;
        return false;
      }
    } else if (registrationStep.value == 2) {
      if (yaw < -15) {
        // Dương là quay sang phải
        faceInstruction.value = "Giữ yên góc phải";
        frameColor.value = Colors.greenAccent;
        return true;
      } else {
        faceInstruction.value = "Từ từ quay mặt sang phải";
        frameColor.value = Colors.redAccent;
        return false;
      }
    }
    return false;
  }

  // Logic kiểm tra trùng lặp trước khi cho nhập tên
  Future<void> _checkDuplicateAndShowDialog(
    List<List<double>> allVectors,
    Uint8List displayBytes,
  ) async {
    detectedFaces.clear();
    isRegistering.value = true;

    tempAllVectors = allVectors; // Cất 3 góc vào kho tạm chờ API
    tempDisplayBytes.value = displayBytes;

    try {
      // 1. Chạy AI Predict (Dùng aiPixels - List<double>)
      // Không cần convert Mat nữa!
      final result = await _aiService.predict(allVectors[0]);

      // 2. PHÁT HIỆN NGƯỜI QUEN
      if (!result.isUnknown) {
        // [UX] Rung nhẹ để báo hiệu nhận ra người quen
        HapticFeedback.vibrate();

        tempRecognizedName.value = result.name;
        tempConfidence.value = result.distance;
        showDuplicateDialog.value = true;
      } else {
        // NGƯỜI MỚI -> Báo View mở Dialog Nhập tên
        showNewUserDialog.value = true;
      }
    } catch (e) {
      AppLog.error("Duplicate check error: $e");
      showNewUserDialog.value = true;
    }
  }

  // Hàm để camera chạy lại nếu hủy hoặc lỗi
  void _resumeCamera() {
    isRegistering.value = false;
    _isDetecting = false;

    _stableFrameCount = 0;
    registrationStep.value = 0;
    capturedVectors.clear();
    frontFaceImage = null;
    try {
      cameraController?.startImageStream(processFrame);
    } catch (e) {
      AppLog.error("Resume camera error: $e");
    }
  }

  // ------------------------------------------------------
  // 1. LIFECYCLE (KHỞI TẠO & HỦY)
  // ------------------------------------------------------

  @override
  void onInit() async {
    super.onInit();

    try {
      // 1. Báo hiệu UI đang tải
      isInitialized.value = false;
      errorMsg.value = "";

      // // 2. Khởi tạo Service AI
      // // Bước này quan trọng để đảm bảo Database và Model đã nạp vào RAM
      // // Nếu không có bước này, lúc bấm lưu sẽ bị lỗi null
      // await _aiService.initialize();

      // 3. Cấu hình Face Detector (ML Kit)
      // Với chức năng ĐĂNG KÝ, ta cần độ chính xác cao nhất (Accurate)
      // và BẮT BUỘC phải có Landmarks để căn chỉnh mặt cho thẳng.
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode:
              FaceDetectorMode.accurate, // Ưu tiên chính xác hơn tốc độ
          enableContours: false,
          enableLandmarks: true, // Cần thiết để crop mặt chuẩn
          enableClassification: false,
          minFaceSize: 0.15, // Chỉ bắt mặt đủ lớn
        ),
      );

      // 4. Mở Camera
      await startCamera();

      // 5. Hoàn tất -> Ẩn loading, hiện Camera
      isInitialized.value = true;
    } catch (e) {
      AppLog.error("❌ Lỗi khởi tạo Register Controller: $e");
      errorMsg.value = "Không thể khởi động: $e";
    }
  }

  @override
  void onClose() {
    _faceDetector.close();

    if (nativeBuffer != null) {
      calloc.free(nativeBuffer!);
      nativeBuffer = null;
    }

    Get.find<FaceIsolateService>().reset();

    cameraController?.dispose();
    super.onClose();
  }

  // ------------------------------------------------------
  // 2. CAMERA SETUP
  // ------------------------------------------------------

  Future<void> startCamera() async {
    // 1. Reset trạng thái lỗi
    errorMsg.value = "";

    try {
      // 2. XIN QUYỀN CAMERA (Bắt buộc)
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        errorMsg.value = "Vui lòng cấp quyền Camera để đăng ký khuôn mặt";
        return;
      }

      // 3. TÌM CAMERA
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        errorMsg.value = "Thiết bị không có Camera";
        return;
      }

      // 4. CHỌN CAMERA TRƯỚC (Selfie)
      _currentCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // 5. CẤU HÌNH CONTROLLER
      cameraController = CameraController(
        _currentCamera!,
        ResolutionPreset.high, // Chọn độ phân giải cao để ảnh đăng ký nét nhất
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup
                  .nv21 // Chuẩn cho Android ML Kit
            : ImageFormatGroup.bgra8888, // Chuẩn cho iOS
      );

      // 6. KHỞI ĐỘNG CAMERA
      await cameraController!.initialize();

      // 7. BẮT ĐẦU STREAM HÌNH ẢNH
      // Lưu ý: Gọi hàm _processFrame (hàm xử lý tự động chụp mà mình vừa viết)
      await cameraController!.startImageStream(processFrame);

      // 8. Báo hiệu thành công để UI hiển thị Preview
      isInitialized.value = true;
    } catch (e) {
      // Bắt lỗi phần cứng (ví dụ camera bị hỏng hoặc app khác đang chiếm camera)
      AppLog.error("❌ Lỗi khởi động Camera: $e");
      errorMsg.value = "Không thể mở Camera: $e";
      isInitialized.value = false;
    }
  }

  void processFrame(CameraImage image) async {
    // Nếu đang bận đăng ký hoặc detect chưa xong -> Bỏ qua
    if (isRegistering.value || _isDetecting || Get.isDialogOpen == true) {
      return;
    }

    _isDetecting = true;

    try {
      // 1. Detect khuôn mặt
      final inputImage = CameraUtils.convertCameraImageToInputImage(
        image,
        _currentCamera!,
      );
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      detectedFaces.assignAll(faces);

      // 2. Logic TỰ ĐỘNG CHỤP (Auto Capture)
      if (faces.isNotEmpty) {
        final face = faces.first;

        // Kiểm tra điều kiện chất lượng
        if (_checkFaceQuality(face, image.width, image.height, image)) {
          _stableFrameCount++;

          int totalFramesNeeded = 3 * _requiredStableFrames;
          int currentFramesDone =
              (registrationStep.value * _requiredStableFrames) +
              _stableFrameCount;
          scanProgress.value = currentFramesDone / totalFramesNeeded;

          // // Debug: In ra để biết đang đếm
          // AppLog.info("Stable count: $_stableFrameCount");

          // Nếu mặt ổn định đủ lâu -> CHỤP LUÔN
          if (_stableFrameCount >= _requiredStableFrames) {
            await autoCapture(image, face);
          }
        } else {
          _stableFrameCount = 0; // Reset nếu mặt bị rung/lệch
          scanProgress.value =
              (registrationStep.value * _requiredStableFrames) /
              (3 * _requiredStableFrames);
        }
      } else {
        _stableFrameCount = 0;
        frameColor.value = Colors.white70;
        scanProgress.value =
            (registrationStep.value * _requiredStableFrames) /
            (3 * _requiredStableFrames);
      }
    } catch (e) {
      AppLog.error("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  Future<void> autoCapture(CameraImage image, Face face) async {
    // isRegistering.value = true;
    _stableFrameCount = 0;

    // await cameraController?.stopImageStream();

    try {
      // AppLog.info("📸 Đang chụp góc thứ ${registrationStep.value}...");

      // ---------------------------------------------------------
      // 1. CHUẨN BỊ BỘ NHỚ (COPY ẢNH VÀO C++ ĐỂ LẤY ADDRESS)
      // ---------------------------------------------------------
      final int totalBytes = image.planes.fold(
        0,
        (sum, plane) => sum + plane.bytes.length,
      );

      // nativeBuffer và _currentBufferSize là các biến bác khai báo ở trên đầu Controller (giống bên Điểm danh)
      if (nativeBuffer == null || _currentBufferSize != totalBytes) {
        if (nativeBuffer != null) calloc.free(nativeBuffer!);
        nativeBuffer = calloc<Uint8>(totalBytes);
        _currentBufferSize = totalBytes;
      }

      int offset = 0;
      for (var plane in image.planes) {
        nativeBuffer!.asTypedList(totalBytes).setAll(offset, plane.bytes);
        offset += plane.bytes.length;
      }

      // GỌI ISOLATE MỚI (isolateRegistrationProcessor)
      final RegistrationResult? result = await _isolateRegistrationService
          .processRegistrationInIsolate(
            address: nativeBuffer!.address,
            width: image.width,
            height: image.height,
            face: face,
            rotation: _currentCamera!.sensorOrientation,
          );

      if (result != null) {
        // 1. Cất Vector 192 chiều vào kho
        capturedVectors.add(result.aiPixels);

        // 2. Nếu là góc chính diện (bước 0), cất luôn tấm ảnh để lát hiện Dialog
        if (registrationStep.value == 0) {
          frontFaceImage = result.displayBytes;
        }

        // 3. Rung báo hiệu đã chụp xong 1 góc
        HapticFeedback.lightImpact();

        // 4. Chuyển sang góc tiếp theo
        registrationStep.value++;

        // 5. KIỂM TRA ĐÃ ĐỦ 3 GÓC CHƯA?
        if (registrationStep.value > 2) {
          // ✅ ĐÃ ĐỦ 3 GÓC -> BẮT ĐẦU ĐÓNG BĂNG MÀN HÌNH VÀ XỬ LÝ
          isRegistering.value = true; // Hiện vòng xoay loading đen mờ
          await cameraController?.stopImageStream(); // Tắt ống kính

          // // Trộn 3 vector thành 1 Siêu Vector
          // List<double> finalVector = _averageVectors(capturedVectors);

          // Hiện Dialog và kết thúc
          await _checkDuplicateAndShowDialog(capturedVectors, frontFaceImage!);
        }
      } else {
        Get.snackbar("Lỗi", "Không thể xử lý ảnh, hãy thử lại");
        _resumeCamera();
      }
    } catch (e) {
      AppLog.error("❌ Capture Error: $e");
      Get.snackbar("Lỗi", "Đã xảy ra lỗi: $e");
      _resumeCamera();
    }
  }

  Future<void> onRegisterNewUser(String name) async {
    if (name.isEmpty || name.length < 2) {
      Get.snackbar("Lỗi", "Tên không hợp lệ");
      return;
    }

    showNewUserDialog.value = false;
    try {
      bool success = await _aiService.register(name, tempAllVectors[0]);

      // 2. TODO: API GỬI LÊN DJANGO SERVER TẠI ĐÂY
      // Lát nữa code API, ta sẽ ném thẳng cái mảng 3 chiều này lên:
      // await ApiService.syncRegistration(name, tempAllVectors);

      if (success) {
        _handleResult(true, "Đã lưu, chờ đồng bộ: $name");
      } else {
        Get.snackbar("Lỗi", "Lưu thất bại");
        _resumeCamera();
      }
    } catch (e) {
      Get.snackbar("Lỗi", "Exception: $e");
      _resumeCamera();
    }
  }

  Future<void> onUpdateExistingUser() async {
    showDuplicateDialog.value = false;

    bool success = await _aiService.update(
      tempRecognizedName.value,
      tempAllVectors[0],
    );

    // TODO: Bắn API lên Server cả 3 góc

    _handleResult(
      success,
      "Đã cập nhật dữ liệu cho ${tempRecognizedName.value}",
    );
  }

  Future<void> onResetExistingUser() async {
    showDuplicateDialog.value = false;

    bool success = await _aiService.register(
      tempRecognizedName.value,
      tempAllVectors[0],
    );

    // TODO: Bắn API lên Server cả 3 góc

    _handleResult(
      success,
      "Đã làm mới dữ liệu của ${tempRecognizedName.value}",
    );
  }

  void onNotThisPerson() {
    showDuplicateDialog.value = false;
    showNewUserDialog.value =
        true; // Đóng dialog người quen, mở dialog người mới
  }

  void onCancelDialog() {
    showDuplicateDialog.value = false;
    showNewUserDialog.value = false;
    _resumeCamera();
  }
}
