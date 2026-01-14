import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:permission_handler/permission_handler.dart';

import '../../app/types/face_progress.dart';
import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';

class FaceRegisterController extends GetxController {
  CameraController? cameraController;
  final FaceRecognitionService _aiService = FaceRecognitionService();
  late FaceDetector _faceDetector;

  var isInitialized = false.obs;
  var detectedFaces = <Face>[].obs;
  var errorMsg = "".obs;

  // Trạng thái: Đang chờ đăng ký hay đã chụp xong
  var isRegistering = false.obs;

  CameraDescription? _currentCamera;
  bool _isDetecting = false;

  // Biến đếm ngược để tránh chụp quá nhanh khi vừa vào
  int _stableFrameCount = 0;
  static const int _requiredStableFrames =
      12; // Cần giữ mặt ổn định trong 10 frame (khoảng 0.5s)

  // Hàm phụ trợ để xử lý kết quả và thông báo
  void _handleResult(bool success, String message) async {
    isRegistering.value = false;

    if (success) {
      Get.snackbar(
        "Thành công",
        message,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      // 🛑 2. Đợi 1.5 giây cho người dùng đọc thông báo rồi mới thoát
      await Future.delayed(const Duration(milliseconds: 1500));
      Get.back(); // Quay về Home
    } else {
      Get.snackbar("Lỗi", "Thao tác thất bại");
      _resumeCamera();
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

      // 2. Khởi tạo Service AI
      // Bước này quan trọng để đảm bảo Database và Model đã nạp vào RAM
      // Nếu không có bước này, lúc bấm lưu sẽ bị lỗi null
      await _aiService.initialize();

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
      debugPrint("❌ Lỗi khởi tạo Register Controller: $e");
      errorMsg.value = "Không thể khởi động: $e";
    }
  }

  @override
  void onClose() {
    _faceDetector.close();
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
      await cameraController!.startImageStream(_processFrame);

      // 8. Báo hiệu thành công để UI hiển thị Preview
      isInitialized.value = true;
    } catch (e) {
      // Bắt lỗi phần cứng (ví dụ camera bị hỏng hoặc app khác đang chiếm camera)
      debugPrint("❌ Lỗi khởi động Camera: $e");
      errorMsg.value = "Không thể mở Camera: $e";
      isInitialized.value = false;
    }
  }

  // ------------------------------------------------------
  // 3. FRAME PROCESSING
  // ------------------------------------------------------

  void _processFrame(CameraImage image) async {
    // Nếu đang bận đăng ký hoặc detect chưa xong -> Bỏ qua
    if (isRegistering.value || _isDetecting) return;

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
        if (_checkFaceQuality(face)) {
          _stableFrameCount++;

          // Debug: In ra để biết đang đếm
          debugPrint("Stable count: $_stableFrameCount");

          // Nếu mặt ổn định đủ lâu -> CHỤP LUÔN
          if (_stableFrameCount >= _requiredStableFrames) {
            await _autoCapture(image, face);
          }
        } else {
          _stableFrameCount = 0; // Reset nếu mặt bị rung/lệch
        }
      } else {
        _stableFrameCount = 0;
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // ------------------------------------------------------
  // 4. BUSINESS LOGIC
  // ------------------------------------------------------
  bool _checkFaceQuality(Face face) {
    // 1. Mặt phải đủ to (gần camera)
    if (face.boundingBox.width < 120) return false;

    // 2. Mặt phải nhìn thẳng (Không nghiêng quá nhiều)
    // HeadEulerAngleY: Quay trái/phải
    // HeadEulerAngleZ: Nghiêng đầu
    if ((face.headEulerAngleY ?? 0).abs() > 10) return false;
    if ((face.headEulerAngleZ ?? 0).abs() > 10) return false;

    // C. Mặt phải ở trung tâm (Tránh bị cắt cằm/trán)
    // (Có thể thêm logic check tọa độ boundingBox nằm trong vùng an toàn giữa màn hình)

    return true;
  }

  Future<void> _autoCapture(CameraImage image, Face face) async {
    // Dừng xử lý frame tiếp theo ngay lập tức
    isRegistering.value = true;
    _stableFrameCount = 0; // Reset đếm

    // Rung nhẹ 1 cái báo hiệu đã chụp (UX tốt)
    HapticFeedback.mediumImpact();

    // Tạm dừng camera stream để "đóng băng" hình ảnh
    await cameraController?.stopImageStream();

    try {
      debugPrint("📸 Capturing face...");

      // Xử lý cắt ảnh (Isolate)
      final rawBytes = CameraUtils.cloneCameraBytes(image);
      final cropRect = CameraUtils.calculateCropRect(
        face,
        image.width,
        image.height,
      );

      final request = FaceProcessRequest(
        yuvBytes: rawBytes,
        width: image.width,
        height: image.height,
        face: face,
        cropX: cropRect.left.toInt(),
        cropY: cropRect.top.toInt(),
        cropW: cropRect.width.toInt(),
        cropH: cropRect.height.toInt(),
        sensorOrientation: _currentCamera!.sensorOrientation,
        isAndroid: Platform.isAndroid,
        rootToken: RootIsolateToken.instance,
      );

      final List<int>? alignedBytes = await compute(
        isolateFaceProcessor,
        request,
      );

      if (alignedBytes != null && alignedBytes.isNotEmpty) {
        // Hiện Dialog nhập tên
        await _checkDuplicateAndShowDialog(alignedBytes);
      } else {
        Get.snackbar("Lỗi", "Không thể xử lý khuôn mặt, vui lòng thử lại");
        _resumeCamera();
      }
    } catch (e) {
      debugPrint("❌ Capture Error: $e");
      Get.snackbar("Lỗi", "Đã xảy ra lỗi khi chụp: $e");
      _resumeCamera();
    }
  }

  // Logic kiểm tra trùng lặp trước khi cho nhập tên
  Future<void> _checkDuplicateAndShowDialog(List<int> faceBytes) async {
    cv.Mat? faceMat;

    try {
      // Convert JPG Bytes -> OpenCV Mat để đưa vào AI
      faceMat = cv.imdecode(
        Uint8List.fromList(faceBytes),
        cv.IMREAD_COLOR,
      );

      // Chạy nhận diện thử
      final result = await _aiService.predict(faceMat);

      // PHÁT HIỆN TRÙNG (Đã có trong DB)
      if (!result.isUnknown) {
        // Hiện Dialog lựa chọn
        await Get.defaultDialog(
          title: "Người Quen!",
          barrierDismissible: false,
          content: Column(
            children: [
              // Ảnh vừa chụp
              ClipOval(
                child: Image.memory(
                  Uint8List.fromList(faceBytes),
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                "Hệ thống nhận diện đây là:\n${result.name}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                "Độ trùng khớp: ${(result.distance * 100).toStringAsFixed(1)}%",
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 20),
              const Text(
                "Bạn muốn làm gì?",
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),

          // NÚT 1: CẬP NHẬT (Merge Vector)
          confirm: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.merge_type),
              label: const Text("Cập nhật thêm góc mặt"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                Get.back(); // Đóng dialog
                // Gọi hàm update (Cộng gộp)
                bool success = await _aiService.update(result.name, faceMat!);
                faceMat.dispose();
                _handleResult(
                  success,
                  "Đã cập nhật dữ liệu cho ${result.name}",
                );
              },
            ),
          ),

          // NÚT 2: GHI ĐÈ (Overwrite)
          cancel: Column(
            children: [
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Làm mới hoàn toàn (Ghi đè)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                  onPressed: () async {
                    Get.back();
                    // Gọi hàm register (Ghi đè) với tên cũ
                    bool success = await _aiService.register(
                      result.name,
                      faceMat!,
                    );
                    faceMat.dispose();
                    _handleResult(
                      success,
                      "Đã làm mới dữ liệu của ${result.name}",
                    );
                  },
                ),
              ),
              const SizedBox(height: 5),
              // NÚT 3: KHÔNG PHẢI TÔI (Đăng ký mới)
              TextButton(
                child: const Text(
                  "Không phải, tôi là người mới",
                  style: TextStyle(color: Colors.grey),
                ),
                onPressed: () {
                  Get.back();
                  faceMat?.dispose();
                  _showNameInputDialog(faceBytes); // Mở dialog nhập tên mới
                },
              ),
            ],
          ),
        );
        return;
      }

      // Nếu là người mới -> OK cho nhập tên
      faceMat.dispose();
      _showNameInputDialog(faceBytes);
    } catch (e) {
      debugPrint("Duplicate check error: $e");
      faceMat?.dispose();
      // Nếu lỗi check thì cứ cho hiện dialog nhập tên
      _showNameInputDialog(faceBytes);
    }
  }

  // Hàm để camera chạy lại nếu hủy hoặc lỗi
  void _resumeCamera() {
    isRegistering.value = false;
    _stableFrameCount = 0;
    try {
      cameraController?.startImageStream(_processFrame);
    } catch (e) {
      debugPrint("Resume camera error: $e");
    }
  }

  Future<void> _showNameInputDialog(List<int> faceBytes) async {
    final nameController = TextEditingController();

    await Get.defaultDialog(
      title: "Đăng Ký Mới",
      barrierDismissible: false, // Bắt buộc chọn
      content: Column(
        children: [
          // Hiện ảnh đã crop
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: Image.memory(
              Uint8List.fromList(faceBytes),
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Họ và tên",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
        ],
      ),
      textConfirm: "Lưu dữ liệu",
      textCancel: "Chụp lại",
      confirmTextColor: Colors.white,
      buttonColor: Colors.blue,
      onConfirm: () async {
        final name = nameController.text.trim();
        // Validate dữ liệu
        if (name.isEmpty) {
          Get.snackbar(
            "Lỗi",
            "Tên không được để trống",
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }
        if (name.length < 2) {
          Get.snackbar(
            "Lỗi",
            "Tên quá ngắn",
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        Get.back(); // Đóng dialog

        try {
          // Gọi Service Lưu
          cv.Mat faceMat = cv.imdecode(
            Uint8List.fromList(faceBytes),
            cv.IMREAD_COLOR,
          );
          bool success = await _aiService.register(name, faceMat);
          faceMat.dispose();

          if (success) {
            isRegistering.value = false;

            Get.snackbar(
              "Thành công",
              "Đã thêm học sinh $name",
              backgroundColor: Colors.green,
              colorText: Colors.white,
            );
            
            await Future.delayed(const Duration(milliseconds: 1500));
            // Đóng màn hình đăng ký luôn sau khi xong
            Get.back();
          } else {
            Get.snackbar("Lỗi", "Đăng ký thất bại");
            _resumeCamera();
          }
        } catch (e) {
          Get.snackbar("Lỗi", "Exception: $e");
          _resumeCamera();
        }
      },
      onCancel: () {
        // Nếu chọn Chụp lại -> Mở lại camera
        _resumeCamera();
      },
    );
  }
}
