import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/utils/camera_utils.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/utils/image_converter.dart';

class FaceAttendanceController extends GetxController {
  CameraController? cameraController;
  final FaceRecognitionService _aiService =
      FaceRecognitionService(); // Instance AI

  var isInitialized = false.obs; // Cờ báo hiệu Camera đã bật chưa.
  var recognizedName = "Unknown".obs;
  var isProcessing = false
      .obs; // Cái "khóa" (Lock/Semaphore) để ngăn không cho xử lý quá nhiều frame cùng lúc (tránh tràn RAM).
  var errorMsg = "".obs;

  String _lastRecognizedName = "";
  DateTime _lastDetectionTime = DateTime.now().subtract(
    const Duration(seconds: 10),
  );

  late FaceDetector _faceDetector;
  var isBusy = false;
  var detectedFaces = <Face>[].obs;
  CameraDescription? _currentCamera;

  img.Image? convertedImageTemp;
  Face? faceTemp;

  @override
  void onInit() async {
    super.onInit();
    await _aiService.initialize();

    // 2. Cấu hình ML Kit
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate, // Ưu tiên độ chính xác
        enableContours: false,
        enableLandmarks: false,
      ),
    );

    startCamera(); // Tự động chạy cam khi controller được tạo
  }

  Future<void> startCamera() async {
    errorMsg.value = "";
    var status = await Permission.camera.request(); // Xin quyền Camera
    if (!status.isGranted) {
      errorMsg.value = "Vui lòng cấp quyền Camera";
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      errorMsg.value = "Không tìm thấy Camera";
      return;
    }

    _currentCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    ); // Tìm Camera trước

    // await _initializeController(_currentCamera!);
    cameraController = CameraController(
      _currentCamera!,
      ResolutionPreset.medium, // Đừng dùng High, dùng Medium cho nhẹ
      enableAudio: false,
      // Tự động chọn format chuẩn theo OS
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup
                .nv21 // Android
          : ImageFormatGroup.bgra8888, // iOS
    );

    await cameraController!.initialize();
    isInitialized.value = true;

    // Bắt đầu Stream
    await cameraController!.startImageStream(
      _processFrame,
    ); // ỗi khi camera bắt được 1 hình, nó bắn ngay vào hàm _processFrame
  }

  // --- LOGIC XỬ LÝ FRAME ---
  void _processFrame(CameraImage image) async {
    // Nếu đang bận nhận diện ai đó, vứt bỏ frame này ngay.
    if (isProcessing.value ||
        DateTime.now().difference(_lastDetectionTime).inMilliseconds < 500) {
      return;
    }

    if (cameraController == null ||
        !cameraController!.value.isStreamingImages) {
      return;
    }

    try {
      // 1. Dùng ML Kit để tìm mặt
      final inputImage = CameraUtils.convertCameraImageToInputImage(
        image,
        _currentCamera!,
      );
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);

      if (isProcessing.value) return;

      // 2. Nếu có mặt và mặt đủ to
      if (faces.isNotEmpty) {
        final face = faces.first;

        // Logic lọc: Chỉ nhận diện khi mặt to > 100px (người đứng gần)
        if (face.boundingBox.width > 80) {
          // --- BẮT ĐẦU PHA XỬ LÝ NẶNG ---
          isProcessing.value = true; // Khóa luồng lại

          img.Image? convertedImage = await ImageConverter.convertCameraImage(
            image,
          );

          if (convertedImage == null) {
            debugPrint("⚠️ Convert ảnh thất bại -> Bỏ qua frame này");

            _lastDetectionTime = DateTime.now();

            isProcessing.value = false;
            return;
          }

          // Xoay ảnh (Thường Android Camera trước bị xoay 270 độ -> cần xoay -90 để thẳng)
          convertedImage = img.copyRotate(convertedImage, angle: -90);

          // final directory = await getTemporaryDirectory();
          // final path =
          //     '${directory.path}/face_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
          // File faceFile = File(path);
          // await faceFile.writeAsBytes(img.encodeJpg(convertedImage));

          convertedImageTemp = convertedImage;
          faceTemp = face;

          final startTime = DateTime.now();
          String? name = await _aiService.predict(convertedImage, face);
          final aiTime = DateTime.now().difference(startTime).inMilliseconds;

          debugPrint("🤖 AI Predict: $name (Time: ${aiTime}ms)");

          if (name != null) {
            if (name != "Unknown" && !name.contains("DB Empty")) {
              recognizedName.value = name;
            }

            if (name == _lastRecognizedName &&
                DateTime.now().difference(_lastDetectionTime).inSeconds < 5) {
              // Trùng tên với lần trước và trong vòng 5 giây, bỏ qua
            } else {
              _lastRecognizedName = name;
              recognizedName.value = name;
              _lastDetectionTime = DateTime.now();

              // UI: Thay vì Snackbar che màn hình, nên update Text trên UI
              // Nhưng nếu dùng snackbar thì dùng cái này cho đỡ spam
              if (!Get.isSnackbarOpen) {
                Get.snackbar(
                  "Thành công",
                  "Xin chào $name",
                  backgroundColor: Colors.green.withValues(alpha: 0.7),
                  colorText: Colors.white,
                );
              }
            }
          } else {
            recognizedName.value = "Unknown";
          }

          // Delay nhẹ 1 chút để user nhìn thấy kết quả
          await Future.delayed(const Duration(seconds: 2));

          _lastDetectionTime = DateTime.now(); // Reset thời gian
          isProcessing.value = false; // MỞ KHÓA LUỒNG
        }
      }
    } catch (e) {
      debugPrint("Lỗi xử lý frame: $e");
      isProcessing.value = false;
    }
  }

  // 1. Hàm gọi UI nhập tên (Giữ nguyên của bạn)
  Future<void> registerNewFace() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    TextEditingController nameController = TextEditingController();
    await Get.defaultDialog(
      title: "Nhập tên nhân viên",
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(hintText: "Ví dụ: Nguyen Van A"),
      ),
      textConfirm: "Lưu",
      textCancel: "Hủy",
      onConfirm: () async {
        String name = nameController.text.trim();
        if (name.isNotEmpty) {
          Get.back();
          // Gọi hàm xử lý file từ Gallery
          await _processRegistrationGallery(File(image.path), name);
        }
      },
    );
  }

  // 2. Hàm xử lý file ảnh từ Gallery
  Future<void> _processRegistrationGallery(File file, String name) async {
    isProcessing.value = true;
    try {
      debugPrint("⏳ Đang tạo vector từ ảnh thư viện...");

      // Lấy vector từ file ảnh
      List<double>? embedding = await _aiService.getEmbeddingFromImageFile(
        file,
      );

      if (embedding != null) {
        // Lưu vector vào DB với tên người dùng
        _aiService.registerUser(name, embedding);

        Get.snackbar(
          "Thành công",
          "Đã thêm nhân viên: $name",
          backgroundColor: Colors.green,
        );
      } else {
        Get.snackbar(
          "Lỗi",
          "Không tìm thấy khuôn mặt hợp lệ trong ảnh",
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      Get.snackbar("Lỗi", "Có sự cố: $e");
    } finally {
      isProcessing.value = false;
    }
  }

  // (Optional) Nếu bạn muốn làm nút "Đăng ký người đang đứng trước Camera"
  void registerCurrentFace(String name) {
    if (convertedImageTemp != null && faceTemp != null) {
      _aiService.registerFace(convertedImageTemp!, faceTemp!, name);
      Get.snackbar(
        "Thành công",
        "Đã lưu nhân viên: $name",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      // Reset lại tên để lần quét tới nó hiện tên mới luôn
      recognizedName.value = name;
    } else {
      Get.snackbar("Lỗi", "Chưa nhận diện được mặt để đăng ký");
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
