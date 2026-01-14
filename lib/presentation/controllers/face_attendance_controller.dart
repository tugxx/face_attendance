import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/types/face_progress.dart';

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

  Future<void> _performRecognition(List<int> jpgBytes) async {
    debugPrint("🤖 Isolate xong. Predict...");
    // imdecode: Tự động hiểu file JPG và bung ra thành Ma trận điểm ảnh (Mat)
    // cv.IMREAD_COLOR: Đảm bảo đọc đủ 3 kênh màu BGR
    cv.Mat faceMat = cv.imdecode(Uint8List.fromList(jpgBytes), cv.IMREAD_COLOR);

    if (faceMat.isEmpty) {
       debugPrint("⚠️ Lỗi: Ảnh decode ra bị rỗng!");
       faceMat.dispose();
       isProcessing.value = false;
       return;
    }

    try {
      debugPrint("🤖 Đang nhận diện...");

      // 2. Gọi AI Service dự đoán
      final result = await _aiService.predict(faceMat);

      // 3. Xử lý kết quả
      if (!result.isUnknown) {
        // success
        recognizedName.value = result.name;
        debugPrint(
          "✅ NHẬN DIỆN THÀNH CÔNG: ${result.name} || Score: ${result.distance.toStringAsFixed(4)}",
        );

        Get.snackbar(
          "Điểm danh thành công",
          "Xin chào, ${result.name}!",
          backgroundColor: Colors.green.withValues(alpha: 0.9),
          colorText: Colors.white,
          icon: const Icon(Icons.check_circle, color: Colors.white),
          duration: const Duration(seconds: 2),
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(10),
        );

        await Future.delayed(const Duration(seconds: 3));
        // SystemNavigator.pop(); // Hoặc navigate đi đâu đó

        // 4. Reset trạng thái để chuẩn bị cho người tiếp theo
        recognizedName.value = ""; // Xóa tên trên màn hình
        isProcessing.value = false; // Mở khóa luồng
      } else {
        recognizedName.value = "Unknown";
        debugPrint("⚠️ Người lạ (Dist: ${result.distance.toStringAsFixed(2)})");
        isProcessing.value = false; // Mở khóa ngay lập tức
      }
    } catch (e) {
      debugPrint("❌ Lỗi AI Predict: $e");
      isProcessing.value = false;
    } finally {
      // Giải phóng bộ nhớ Mat sau khi dùng xong
      faceMat.dispose();
    }
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
          performanceMode: FaceDetectorMode.accurate, // Ưu tiên độ chính xác
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
        ResolutionPreset.high,
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

    Face? face;
    try {
      // 2. Detect khuôn mặt (ML Kit)
      face = await _detectFaceFromImage(image);
    } catch (e) {
      debugPrint("Error detecting: $e");
    } finally {
      // 🛑 QUAN TRỌNG: Mở khóa ngay lập tức để frame sau có thể tiếp tục vẽ khung
      // Dù có tìm thấy mặt hay không, dù có lỗi hay không, cũng phải mở cửa.
      _isDetecting = false;
    }

    // Nếu không có mặt hoặc đang xử lý frame khác -> Dừng
    if (face == null) return;

    // 2. Kiểm tra điều kiện Throttling (500ms mới nhận diện 1 lần)
    if (_shouldSkipRecognition()) return;

    // 3. Khoá luồng để bắt đầu xử lý (ko nhận frame mới)
    _lockProcessing();

    try {
      // 4. Chuẩn bị dữ liệu cho Isolate
      final rawBytes = CameraUtils.cloneCameraBytes(image);

      // final debugPath = await _generateDebugPath();

      // Tính toán vùng crop
      final cropRect = CameraUtils.calculateCropRect(face, image.width, image.height);

      final request = FaceProcessRequest(
        yuvBytes: rawBytes,
        width: image.width,
        height: image.height,
        face: face, // Đã truyền face chuẩn
        cropX: cropRect.left.toInt(),
        cropY: cropRect.top.toInt(),
        cropW: cropRect.width.toInt(),
        cropH: cropRect.height.toInt(),
        sensorOrientation: _currentCamera!.sensorOrientation,
        isAndroid: Platform.isAndroid,
        // debugPath: debugPath,
        rootToken: RootIsolateToken.instance,
      );

      // 5. Gửi sang Isolate (Nặng nhất)
      debugPrint("🚀 Gửi task sang Isolate...");
      final List<int>? alignedFaceBytes = await compute(
        isolateFaceProcessor,
        request,
      );

      // 6. Predict & Update UI
      if (alignedFaceBytes != null) {
        await _performRecognition(alignedFaceBytes);
      } else {
        // Isolate trả về null (lỗi xử lý ảnh) -> Unlock ngay
        isProcessing.value = false;
      }
    } catch (e, s) {
      debugPrint("❌ Lỗi processFrame: $e");
      debugPrintStack(stackTrace: s);
      isProcessing.value = false; // Mở khóa nếu lỗi
    } finally {
      // _isBusy = false;
      _safeguardUnlock(); // Đảm bảo không bị deadlock
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
