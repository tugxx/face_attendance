import 'dart:io';
// import 'dart:typed_data';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
// import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
// import 'package:flutter_image_compress/flutter_image_compress.dart';
// import '../../../core/services/image_converter_ffi.dart';

import '../../../core/utils/camera_utils.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/values/face_progress.dart';
// import '../../../core/utils/image_utils.dart';
// import '../../../core/utils/image_converter.dart';

class FaceAttendanceController extends GetxController {
  CameraController? cameraController;
  final FaceRecognitionService _aiService =
      FaceRecognitionService(); // Instance AI

  var isInitialized = false.obs; // Cờ báo hiệu Camera đã bật chưa.
  var recognizedName = "Unknown".obs;
  var isProcessing = false
      .obs; // Cái "khóa" (Lock/Semaphore) để ngăn không cho xử lý quá nhiều frame cùng lúc (tránh tràn RAM).
  var errorMsg = "".obs;

  // String _lastRecognizedName = "";
  DateTime _lastDetectionTime = DateTime.now().subtract(
    const Duration(seconds: 10),
  );

  late FaceDetector _faceDetector;
  var detectedFaces = <Face>[].obs;
  CameraDescription? _currentCamera;

  img.Image? convertedImageTemp;
  Face? faceTemp;

  bool _isBusy = false;

  bool _shouldSkipFrame() {
    if (_isBusy || isProcessing.value) return true;
    if (DateTime.now().difference(_lastDetectionTime).inMilliseconds < 500) {
      return true;
    }
    return false;
  }

  Future<Face?> _detectFaceFromImage(CameraImage image) async {
    final inputImage = CameraUtils.convertCameraImageToInputImage(
      image,
      _currentCamera!,
    );
    if (inputImage == null) return null;

    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    final face = faces.first;
    // Lọc khuôn mặt quá nhỏ (rác)
    if (face.boundingBox.width < 80) return null;

    return face;
  }

  void _lockProcessing() {
    isProcessing.value = true;
    _lastDetectionTime = DateTime.now();
  }

  // Logic toán học tính toán vùng Crop (đã tách ra cho gọn)
  Rect _calculateCropRect(Face face, int imgWidth, int imgHeight) {
    double centerX = face.boundingBox.center.dx;
    double centerY = face.boundingBox.center.dy;

    // Scale factor 0.5 (Lấy rộng ra 50%)
    double maxSide = max(face.boundingBox.width, face.boundingBox.height);
    double sideLength = maxSide * 1.5;

    double x = centerX - sideLength / 2;
    double y = centerY - sideLength / 2;

    // Boundary check (Giữ nguyên logic của bạn nhưng dùng class Rect của Dart)
    x = x < 0 ? 0 : x;
    y = y < 0 ? 0 : y;

    if (x + sideLength > imgWidth) sideLength = imgWidth - x;
    if (y + sideLength > imgHeight) sideLength = imgHeight - y;

    return Rect.fromLTWH(x, y, sideLength, sideLength);
  }

  Future<String?> _generateDebugPath() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        // 1. Đặt tên file cố định
        final String path = '${dir.path}/debug_face.jpg';

        // 2. In đường dẫn ra console để debug
        debugPrint("💾 File path: $path");

        return path;
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi tạo đường dẫn: $e");
    }
    return null;
  }

  Future<void> _performRecognition(List<int> faceBytes) async {
    debugPrint("🤖 Isolate xong. Predict...");
    // 1. Tái tạo cv.Mat từ bytes nhận được
    // Kích thước cố định 112x112 (do Isolate đã warpAffine về size này)
    // Type là CV_8UC3 (3 kênh màu BGR)
    cv.Mat faceMat = cv.Mat.fromList(112, 112, cv.MatType.CV_8UC3, faceBytes);

    try {
      // 2. Gọi Service (Lúc này Service nhận vào cv.Mat chuẩn chỉ)
      final result = await _aiService.predict(faceMat);

      if (!result.isUnknown) {
        // ✅ SUCCESS
        recognizedName.value = result.name;
        Get.snackbar(
          "Thành công",
          "Xin chào ${result.name} (${result.distance.toStringAsFixed(2)})",
          backgroundColor: const Color(0xAA4CAF50),
          colorText: Colors.white,
          duration: const Duration(seconds: 1),
        );

        // cameraController?.stopImageStream();
        await Future.delayed(const Duration(seconds: 2));
        // SystemNavigator.pop(); // Hoặc navigate đi đâu đó

        // 👉 QUAN TRỌNG: Reset lại tên để UI biết là đã xong phiên này
        recognizedName.value = "";

        // 👉 QUAN TRỌNG NHẤT: Mở khóa để xử lý frame tiếp theo
        isProcessing.value = false;
      } else {
        // ⚠️ UNKNOWN
        recognizedName.value = "Unknown";
        debugPrint("⚠️ Người lạ (Dist: ${result.distance.toStringAsFixed(2)})");
        isProcessing.value = false;
      }
    } catch (e) {
      debugPrint("❌ Lỗi AI Predict: $e");
      isProcessing.value = false;
    } finally {
      // 3. Quan trọng: Giải phóng bộ nhớ Mat sau khi dùng xong
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

  @override
  void onInit() async {
    super.onInit();
    await _aiService.initialize();

    // 2. Cấu hình ML Kit
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate, // Ưu tiên độ chính xác
        enableContours: false,
        enableLandmarks: true,
        enableClassification: false,
        minFaceSize: 0.15,
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
      ResolutionPreset.high, // Đừng dùng High, dùng Medium cho nhẹ
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
    // 1. Kiểm tra điều kiện chạy (Throttling & Busy state)
    if (_shouldSkipFrame()) return;

    _isBusy = true;

    try {
      // 2. Detect khuôn mặt (ML Kit)
      final Face? face = await _detectFaceFromImage(image);

      // Nếu không có mặt hoặc đang xử lý frame khác -> Dừng
      if (face == null || isProcessing.value) return;

      // 3. Lock process để bắt đầu xử lý chuyên sâu
      _lockProcessing();

      // 4. Chuẩn bị dữ liệu cho Isolate
      // LƯU Ý: Chỉ clone bytes khi thực sự cần thiết (Tiết kiệm hiệu năng)
      final rawBytes = _cloneCameraBytes(image);
      final debugPath = await _generateDebugPath();

      // Tính toán vùng crop
      final cropRect = _calculateCropRect(face, image.width, image.height);

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
        debugPath: debugPath,
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
      _isBusy = false;
      _safeguardUnlock(); // Đảm bảo không bị deadlock
    }
  }

  // Hàm hỗ trợ Clone (Copy sâu) dữ liệu ảnh
  Uint8List _cloneCameraBytes(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    // Tính kích thước chuẩn NV21: Y (w*h) + UV (w*h/2)
    final int targetSize = width * height + ((width * height) ~/ 2);
    final buffer = Uint8List(targetSize);

    try {
      // TRƯỜNG HỢP 1: Camera trả về đúng 3 Planes (Y, U, V) - Chuẩn Android
      if (image.planes.length == 3) {
        final yPlane = image.planes[0];
        // final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        // 1. Copy Y (Luôn đúng)
        buffer.setRange(0, width * height, yPlane.bytes);

        // 2. Copy UV
        // Mẹo: Trên Android, Plane V thường chứa cả U xen kẽ (VUVU...)
        // Check pixelStride để biết nó có xen kẽ không
        if (vPlane.bytesPerPixel == 2) {
          // Đây là dạng NV21 chuẩn, ta copy luôn plane V vào phần sau của buffer
          // Lưu ý: C++ của bạn đang đọc UV xen kẽ, nên cách này an toàn nhất.
          int uvOffset = width * height;
          int bytesToCopy = vPlane.bytes.length;

          // Chỉ copy nếu đủ chỗ, tránh Crash
          if (uvOffset + bytesToCopy <= targetSize) {
            buffer.setRange(uvOffset, uvOffset + bytesToCopy, vPlane.bytes);
          } else {
            // Nếu buffer V quá lớn, chỉ lấy đúng phần mình cần
            buffer.setRange(
              uvOffset,
              targetSize,
              vPlane.bytes.sublist(0, targetSize - uvOffset),
            );
          }
        } else {
          // Trường hợp hiếm: 3 plane rời rạc (I420), phải ghép tay (chậm hơn xíu nhưng an toàn)
          // Logic ghép tay phức tạp, nhưng tạm thời cứ fill 0 vào UV để không crash C++
          // (Ảnh sẽ đen trắng nhưng app không chết)
        }
      }
      // TRƯỜNG HỢP 2: Camera trả về 1 Plane duy nhất (Thường là YUV gói chung hoặc Raw)
      else if (image.planes.length == 1) {
        final plane = image.planes[0];
        final int rowStride = plane.bytesPerRow; // ĐÂY LÀ CHÌA KHÓA
        // final int pixelStride = plane.bytesPerPixel ?? 1;

        // TH1: Dữ liệu sạch (Stride == Width) -> Copy nhanh
        if (rowStride == width) {
          int copyLen = plane.bytes.length > targetSize
              ? targetSize
              : plane.bytes.length;
          buffer.setRange(0, copyLen, plane.bytes.sublist(0, copyLen));
        }
        // TH2: Có Padding (Stride > Width) -> Phải lọc bỏ rác
        else {
          // A. Copy vùng Y (Luminance)
          // Duyệt qua từng dòng, chỉ lấy đúng 'width' bytes, bỏ phần thừa
          for (int row = 0; row < height; row++) {
            int srcPos = row * rowStride;
            int dstPos = row * width;

            // Copy 1 hàng
            buffer.setRange(
              dstPos,
              dstPos + width,
              plane.bytes.sublist(srcPos, srcPos + width),
            );
          }

          // B. Copy vùng UV (Chrominance)
          // Vùng UV bắt đầu ngay sau vùng Y (tính theo stride gốc)
          int uvSrcStart = height * rowStride;
          int uvDstStart = width * height;

          // Vùng UV có chiều cao = height / 2
          for (int row = 0; row < height ~/ 2; row++) {
            int srcPos = uvSrcStart + (row * rowStride);
            int dstPos = uvDstStart + (row * width);

            // Kiểm tra biên để không crash nếu buffer thiếu
            if (srcPos + width <= plane.bytes.length &&
                dstPos + width <= buffer.length) {
              buffer.setRange(
                dstPos,
                dstPos + width,
                plane.bytes.sublist(srcPos, srcPos + width),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi copy bytes: $e");
      // Trả về buffer rỗng hoặc đen xì còn hơn là làm Crash app
      return Uint8List(targetSize);
    }

    return buffer;
  }

  // // 1. Hàm gọi UI nhập tên (Giữ nguyên của bạn)
  // Future<void> registerNewFace() async {
  //   final ImagePicker picker = ImagePicker();
  //   final XFile? image = await picker.pickImage(source: ImageSource.gallery);
  //   if (image == null) return;

  //   TextEditingController nameController = TextEditingController();
  //   await Get.defaultDialog(
  //     title: "Nhập tên nhân viên",
  //     content: TextField(
  //       controller: nameController,
  //       decoration: const InputDecoration(hintText: "Ví dụ: Nguyen Van A"),
  //     ),
  //     textConfirm: "Lưu",
  //     textCancel: "Hủy",
  //     onConfirm: () async {
  //       String name = nameController.text.trim();
  //       if (name.isNotEmpty) {
  //         Get.back();
  //         // Gọi hàm xử lý file từ Gallery
  //         await _processRegistrationGallery(File(image.path), name);
  //       }
  //     },
  //   );
  // }

  // // 2. Hàm xử lý file ảnh từ Gallery
  // Future<void> _processRegistrationGallery(File file, String name) async {
  //   isProcessing.value = true;
  //   try {
  //     debugPrint("⏳ Đang tạo vector từ ảnh thư viện...");

  //     // Lấy vector từ file ảnh
  //     List<double>? embedding = await _aiService.getEmbeddingFromImageFile(
  //       file,
  //     );

  //     if (embedding != null) {
  //       // Lưu vector vào DB với tên người dùng
  //       _aiService.registerUser(name, embedding);

  //       Get.snackbar(
  //         "Thành công",
  //         "Đã thêm nhân viên: $name",
  //         backgroundColor: Colors.green,
  //       );
  //     } else {
  //       Get.snackbar(
  //         "Lỗi",
  //         "Không tìm thấy khuôn mặt hợp lệ trong ảnh",
  //         backgroundColor: Colors.red,
  //       );
  //     }
  //   } catch (e) {
  //     Get.snackbar("Lỗi", "Có sự cố: $e");
  //   } finally {
  //     isProcessing.value = false;
  //   }
  // }

  // // (Optional) Nếu bạn muốn làm nút "Đăng ký người đang đứng trước Camera"
  // void registerCurrentFace(String name) {
  //   if (convertedImageTemp != null && faceTemp != null) {
  //     _aiService.registerFace(convertedImageTemp!, faceTemp!, name);
  //     Get.snackbar(
  //       "Thành công",
  //       "Đã lưu nhân viên: $name",
  //       backgroundColor: Colors.green,
  //       colorText: Colors.white,
  //     );

  //     // Reset lại tên để lần quét tới nó hiện tên mới luôn
  //     recognizedName.value = name;
  //   } else {
  //     Get.snackbar("Lỗi", "Chưa nhận diện được mặt để đăng ký");
  //   }
  // }

  @override
  void onClose() {
    _faceDetector.close();
    cameraController?.stopImageStream();
    cameraController?.dispose();
    super.onClose();
  }
}
