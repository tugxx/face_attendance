// import 'package:camera/camera.dart';
// import 'package:flutter/foundation.dart';
// import 'package:get/get.dart';
// import 'package:permission_handler/permission_handler.dart';

// class CameraAttendanceController extends GetxController {
//   CameraController? cameraController;
//   var isInitialized = false.obs;
//   var errorMsg = "".obs;
//   var isLoading = false.obs;

//   // Mới: Danh sách camera để hiển thị lên UI (Dropdown)
//   var availableCamerasList = <CameraDescription>[].obs;

//   // Mới: Camera đang được chọn
//   var selectedCameraDesc = Rxn<CameraDescription>();

//   // @override
//   // void onInit() {
//   //   super.onInit();
//   // }

//   Future<void> startCamera() async {
//     isLoading.value = true;
//     errorMsg.value = "";

//     try {
//       // 1. Xin quyền (Chỉ cần thiết trên Mobile, Web sẽ tự hỏi khi khởi tạo)
//       if (!kIsWeb) {
//         var status = await Permission.camera.request();
//         if (!status.isGranted) {
//           errorMsg.value = "Bạn cần cấp quyền Camera để sử dụng tính năng này!";
//           isLoading.value = false;
//           return;
//         }
//       }

//       // else {
//       //   var status = await Permission.camera.request();
//       //   if (!status.isGranted) {
//       //      errorMsg.value = "Cần cấp quyền Camera";
//       //      return;
//       //   }
//       // }

//       // // 2. Lấy danh sách Camera
//       // debugPrint("Đang gọi availableCameras()...");
//       // List<CameraDescription> cameras = [];
//       // try {
//       //   cameras = await availableCameras();
//       // } catch (e) {
//       //   debugPrint("Lỗi khi lấy danh sách camera: $e");
//       //   errorMsg.value = "Không thể đọc danh sách Camera. Hãy tắt các ứng dụng khác (Zoom/Zalo) rồi thử lại.";
//       //   isLoading.value = false;
//       //   return;
//       // }

//       // 2. Lấy danh sách Camera (CÓ CƠ CHẾ THỬ LẠI)
//       debugPrint("Đang gọi availableCameras()...");
//       List<CameraDescription> cameras = [];

//       // --- BẮT ĐẦU LOGIC RETRY ---
//       int retryCount = 0;
//       const int maxRetries = 3;

//       while (retryCount < maxRetries) {
//         try {
//           cameras = await availableCameras();
//           if (cameras.isNotEmpty) break; // Lấy được rồi thì thoát vòng lặp
//         } catch (e) {
//           debugPrint("Lần thử $retryCount thất bại: $e");
//           if (retryCount == maxRetries - 1) {
//              // Nếu là lần cuối cùng mà vẫn lỗi thì ném lỗi ra ngoài
//              rethrow;
//           }
//           // Chờ 1 giây trước khi thử lại (Để trình duyệt kịp nhả camera cũ ra)
//           await Future.delayed(const Duration(seconds: 1));
//           retryCount++;
//         }
//       }

//       debugPrint("Đã lấy xong danh sách Camera: ${cameras.length}");

//       if (cameras.isEmpty) {
//         errorMsg.value = "Không tìm thấy Camera nào kết nối với máy tính!";
//         isLoading.value = false;
//         return;
//       }

//       // Cập nhật danh sách camera vào biến để UI dùng
//       availableCamerasList.assignAll(cameras);

//       // 3. Chọn Camera mặc định ban đầu
//       CameraDescription initialCamera;
//       if (kIsWeb) {
//          // Web: Mặc định lấy cái đầu tiên
//          initialCamera = cameras.first;
//       } else {
//          // Mobile: Ưu tiên camera trước
//          initialCamera = cameras.firstWhere(
//            (camera) => camera.lensDirection == CameraLensDirection.front,
//            orElse: () => cameras.first,
//          );
//       }

//       // Gán tạm giá trị để dropdown hiện lên
//       selectedCameraDesc.value = initialCamera;

//       // 4. Khởi tạo Camera đã chọn
//       await selectCamera(initialCamera);

//       // // 4. Khởi tạo Controller
//       // cameraController = CameraController(
//       //   initialCamera, // Dùng biến đã chọn ở trên
//       //   // Trên Web, ResolutionPreset.max hoặc medium thường ổn định hơn low
//       //   kIsWeb ? ResolutionPreset.medium : ResolutionPreset.low,
//       //   enableAudio: false,
//       //   imageFormatGroup: kIsWeb ? null : ImageFormatGroup.yuv420,
//       // );

//       // await cameraController!.initialize();
//       // isInitialized.value = true;
//     } catch (e) {
//       debugPrint("Lỗi Camera chi tiết: $e"); // Xem log ở Terminal/Console

//       if (e is CameraException) {
//         if (e.code == 'cameraNotReadable') {
//           errorMsg.value =
//               "Trình duyệt không đọc được Camera. Hãy tắt các app khác (Zoom, Zalo) và thử lại.";
//         } else if (e.code == 'CameraAccessDenied') {
//           errorMsg.value =
//               "Bạn đã chặn quyền Camera. Hãy bấm vào biểu tượng ổ khóa trên thanh địa chỉ để mở lại.";
//         } else {
//           errorMsg.value = "Lỗi Camera: ${e.description}";
//         }
//       } else {
//         errorMsg.value = "Lỗi không xác định: $e";
//       }
//     } finally {
//       // QUAN TRỌNG: Dù thành công hay thất bại đều phải tắt loading
//       isLoading.value = false;
//     }
//   }

//   Future<void> selectCamera(CameraDescription cameraDesc) async {
//     try {
//       isLoading.value = true;
//       isInitialized.value = false; // Tắt preview tạm thời

//       // Quan trọng: Hủy camera cũ nếu đang chạy
//       if (cameraController != null) {
//         await cameraController!.dispose();
//       }

//       // Cập nhật biến camera đang chọn
//       selectedCameraDesc.value = cameraDesc;

//       // Khởi tạo controller mới
//       cameraController = CameraController(
//         cameraDesc,
//         kIsWeb ? ResolutionPreset.medium : ResolutionPreset.low,
//         enableAudio: false,
//         imageFormatGroup: kIsWeb ? null : ImageFormatGroup.yuv420,
//       );

//       await cameraController!.initialize();
//       isInitialized.value = true;

//     } catch (e) {
//       debugPrint("Lỗi Camera: $e");
//       if (e is CameraException) {
//         if (e.code == 'cameraNotReadable') {
//           errorMsg.value = "Trình duyệt không đọc được Camera. Hãy tắt các app khác.";
//         } else if (e.code == 'CameraAccessDenied') {
//           errorMsg.value = "Bạn đã chặn quyền Camera.";
//         } else {
//           errorMsg.value = "Lỗi Camera: ${e.description}";
//         }
//       } else {
//         errorMsg.value = "Lỗi không xác định: $e";
//       }
//     } finally {
//       isLoading.value = false;
//     }
//   }

//   @override
//   void onClose() {
//     cameraController?.dispose();
//     super.onClose();
//   }
// }

// controllers/camera_attendance_controller.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:face_attendance/app/camera_utils.dart'; // Import file utils ở trên

class CameraAttendanceController extends GetxController {
  CameraController? cameraController;
  var isInitialized = false.obs;
  var errorMsg = "".obs;

  // Biến quản lý Face Detection
  late FaceDetector _faceDetector;
  var isBusy = false; // Cờ để chặn spam frame
  var detectedFaces = <Face>[].obs; // Danh sách mặt tìm thấy để vẽ lên UI

  // Camera hiện tại
  CameraDescription? _currentCamera;

  @override
  void onInit() {
    super.onInit();
    // Cấu hình nhận diện: Ưu tiên tốc độ (performance), không cần landmark mắt mũi miệng chi tiết
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableLandmarks: false,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> startCamera() async {
    errorMsg.value = "";
    try {
      // 1. Xin quyền
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        errorMsg.value = "Vui lòng cấp quyền Camera trong cài đặt";
        return;
      }

      // 2. Lấy danh sách cam
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        errorMsg.value = "Không tìm thấy Camera";
        return;
      }

      // Ưu tiên cam trước cho điểm danh
      _currentCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      await _initializeController(_currentCamera!);
    } catch (e) {
      errorMsg.value = "Lỗi khởi tạo: $e";
    }
  }

  Future<void> _initializeController(CameraDescription camera) async {
    cameraController = CameraController(
      camera,
      ResolutionPreset.medium, // Medium là đủ cho AI, High sẽ làm chậm máy
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup
                .nv21 // Android chuẩn NV21
          : ImageFormatGroup.bgra8888, // iOS chuẩn BGRA
    );

    try {
      await cameraController!.initialize();
      isInitialized.value = true;

      // 3. Bắt đầu Stream ảnh để xử lý AI
      await cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      errorMsg.value = "Không thể mở Camera: $e";
    }
  }

  // --- LOGIC XỬ LÝ ẢNH (CORE) ---
  void _processCameraImage(CameraImage image) async {
    // Nếu đang xử lý frame trước đó thì bỏ qua frame này (Throttling)
    if (isBusy || _currentCamera == null) return;
    isBusy = true;

    try {
      // 1. Convert sang định dạng ML Kit
      final inputImage = CameraUtils.convertCameraImageToInputImage(
        image,
        _currentCamera!,
      );
      if (inputImage == null) {
        isBusy = false;
        return;
      }

      // 2. Gọi AI để detect
      final faces = await _faceDetector.processImage(inputImage);

      // 3. Cập nhật UI (Vẽ khung chữ nhật)
      detectedFaces.value = faces;

      // 4. Logic Nghiệp vụ: Nếu tìm thấy mặt -> Check Condition
      if (faces.isNotEmpty) {
        // Lấy mặt to nhất
        final mainFace = faces.first;

        // 3. SỬA LỖI WARNING: Dùng biến mainFace vào log để không bị báo unused
        debugPrint("Face bounding box: ${mainFace.boundingBox}");

        // Logic mẫu: Nếu mặt đủ to thì chụp
        // if (mainFace.boundingBox.width > 200) { 
        //    _captureAndRecognize(); 
        // }

        // Ví dụ: Kiểm tra xem mặt có đủ to không (tránh người đứng quá xa)
        // Rect boundingBox = mainFace.boundingBox;
        // if (boundingBox.width > 200) {
        //    _captureAndRecognize();
        // }

        debugPrint("Tìm thấy ${faces.length} khuôn mặt");
      }
    } catch (e) {
      debugPrint("Lỗi AI: $e");
    } finally {
      isBusy = false; // Mở khóa để xử lý frame tiếp theo
    }
  }

  // 4. SỬA LỖI WARNING: Thêm ignore để IDE không báo lỗi hàm chưa dùng
  // ignore: unused_element
  Future<void> _captureAndRecognize() async {
    try {
      // Dừng stream để chụp ảnh nét nhất
      await cameraController?.stopImageStream();
      XFile photo = await cameraController!.takePicture();

      // 5. SỬA LỖI WARNING: Dùng biến photo
      debugPrint("Đã chụp ảnh tạm tại: ${photo.path}");

      // Gửi photo.path lên server API tại đây...

      // Sau khi gửi xong thì mở lại stream để điểm danh tiếp
      // await cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint("Lỗi chụp ảnh: $e");
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
