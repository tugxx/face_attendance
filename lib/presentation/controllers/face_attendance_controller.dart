import 'dart:io';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../app/utils/camera_utils.dart';
import '../../app/services/face_recognition_service.dart';
import '../../app/services/face_isolate_service.dart';
import '../../app/services/face_antispoofing_service.dart';
import '../../app/services/face_smoothier_service.dart';
import '../../app/services/log_service.dart';
import '../../app/services/web_socket_service.dart';
import '../../app/types/face_pipeline.dart';
import '../../app/services/sync_service.dart';
import '../../app/services/device_service.dart';

class FaceCheckinState {
  // Biến cấu hình
  static const int requiredRecognitionStreak =
      3; // Cần 3 lần nhận diện đúng tên
  // static const int requiredLivenessStreak = 3; // Cần 3 lần check liveness OK
  static const int requiredSpoofStreak = 5; // Cần 5 lần phát hiện giả mạo

  // Biến trạng thái runtime
  String? currentCandidate; // Tên người đang theo dõi
  int matchStreak = 0; // Đếm số lần nhận diện đúng liên tiếp
  int spoofStreak = 0; // Đếm số lần phát hiện giả mạo liên tiếp
  int livenessStreak = 0; // Đếm số lần liveness pass liên tiếp
  bool isSuccessCooldown = false; // Chế độ chờ sau khi điểm danh thành công

  int blurryStreak = 0;

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

  final FaceRecognitionService _recognitionService =
      Get.find<FaceRecognitionService>();
  final FaceAntiSpoofingService _spoofService =
      Get.find<FaceAntiSpoofingService>();

  final FaceIsolateService _isolateService = Get.find<FaceIsolateService>();

  final _smoother = BBoxSmoother();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // StreamSubscription<List<ConnectivityResult>>? _networkSubscription;

  var isInitialized = false.obs; // Cờ báo hiệu Camera đã bật chưa.
  var recognizedName = "Unknown".obs;
  // Cái "khóa" (Lock/Semaphore) để ngăn không cho xử lý quá nhiều frame cùng lúc (tránh tràn RAM).
  var isProcessing = false.obs;
  var isAiReady = false.obs;
  var errorMsg = "".obs;
  final RxBool isSpoofing = false.obs;

  DateTime _lastRecognitionTime = DateTime.fromMillisecondsSinceEpoch(0);
  late FaceDetector _faceDetector;
  var detectedFaces = <Face>[].obs;

  DateTime _lastBlurWarningTime = DateTime.now();

  CameraDescription? _currentCamera;

  var faceInstruction = "".obs;

  Pointer<Uint8>? nativeBuffer;
  int _currentBufferSize = 0;

  Map<int, String> verifiedFaces = {};
  final Map<int, int> _faceAttempts = {};

  // ------------------------------------------------------
  // HELPER
  // ------------------------------------------------------

  bool _shouldSkipRecognition() {
    // Nếu chưa đủ 500ms kể từ lần nhận diện trước -> Skip
    final now = DateTime.now();
    if (now.difference(_lastRecognitionTime).inMilliseconds < 500) {
      return true;
    }

    _lastRecognitionTime = now;

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

    // Lọc khuôn mặt quá to (Gần camera)
    // Lấy kích thước khung hình từ metadata của ML Kit (đã xử lý xoay chuẩn xác)
    final imageSize = inputImage.metadata?.size;
    if (imageSize != null) {
      final actualWidth = math.min(imageSize.width, imageSize.height);

      final widthRatio = face.boundingBox.width / actualWidth;

      // Ngưỡng : Mặt chiếm > % chiều ngang màn hình -> Quá gần
      if (widthRatio > 0.85) {
        // AppLog.warning(
        //   "Khuôn mặt quá gần camera! Tỷ lệ ngang: ${(widthRatio * 100).toInt()}%",
        // );
        faceInstruction.value = "⚠️ Quá gần! Vui lòng lùi ra xa";
        return null;
      }

      faceInstruction.value = "";
    }

    return face;
  }

  // Future<String?> _generateDebugPath() async {
  //   try {
  //     final dir = await getExternalStorageDirectory();
  //     if (dir != null) {
  //       // 1. Đặt tên file cố định
  //       final String path = '${dir.path}/debug_face.jpg';

  //       // 2. In đường dẫn ra console để debug
  //       AppLog.info("💾 File path: $path");

  //       return path;
  //     }
  //   } catch (e) {
  //     AppLog.warning("⚠️ Lỗi tạo đường dẫn: $e");
  //   }
  //   return null;
  // }

  Future<void> _handleCheckinSuccess({
    required String studentId,
    required double confidence,
    required double livenessScore,
    String? localImagePath, // Có thể làm tính năng lưu ảnh sau
  }) async {
    checkinState.isSuccessCooldown = true; // Khóa hệ thống

    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.play(
      AssetSource(
        'sounds/miraclei-sample_confirm_accept01_kofi_by_miraclei-364181.mp3',
      ),
    );

    HapticFeedback.vibrate();

    AppLog.info("🎉 CHECKIN SUCCESS: $studentId");

    recognizedName.value = studentId;

    // 1. Sinh UUID tại App
    final String recordUuid = const Uuid().v4();

    // 2. Gom dữ liệu chuẩn Thực tế
    Map<String, dynamic> offlineLog = {
      "id": recordUuid,
      "student_id": studentId,
      "device_id": DeviceService().deviceId,
      "timestamp": DateTime.now()
          .toUtc()
          .toIso8601String(), // Luôn dùng chuẩn UTC
      "confidence": confidence, // Ví dụ: 0.89 (89%)
      "liveness_score": livenessScore, // Ví dụ: 0.99 (99% là người thật)
      "sync_status": "PENDING", // Trạng thái chờ đồng bộ
      "image_path": localImagePath, // Nơi lưu ảnh offline trên điện thoại
    };

    final attendanceBox = Hive.box('AttendanceBox');
    await attendanceBox.put(recordUuid, offlineLog);

    final socketPayload = Map<String, dynamic>.from(offlineLog)
      ..remove('sync_status')
      ..remove('image_path');

    // 3. Bắn thẳng qua WebSocket
    WebSocketService().sendCheckinData(socketPayload);

    // Wait 3 giây rồi reset (Logic Python: success_mode active duration)
    await Future.delayed(const Duration(seconds: 3));

    SyncService().syncPendingRecords();

    recognizedName.value = "Unknown";
    checkinState.reset();
    checkinState.isSuccessCooldown = false; // Mở khóa lại
  }

  // ------------------------------------------------------
  // INIT FUNCTION
  // ------------------------------------------------------

  @override
  void onInit() async {
    super.onInit();

    // await _spoofService.initialize();

    try {
      // Bắt đầu quy trình khởi tạo
      isInitialized.value = false;
      isAiReady.value = false;

      isProcessing.value = false;

      // // Khởi động Worker (Chỉ 1 lần duy nhất)
      // await _isolateService.start();

      // // Khởi tạo Service Nhận diện khuôn mặt (Custom AI)
      // // Đây là bước nạp Model (ví dụ: mobilefacenet.tflite) và dữ liệu nhân viên vào RAM.
      // // Từ khóa 'await': Đợi nạp xong xuôi mới chạy dòng tiếp theo (tránh lỗi chưa load model mà đã dùng).
      // await _recognitionService.initialize();

      // 2. Cấu hình ML Kit
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast, // Ưu tiên độ chính xác
          enableContours:
              false, // Không cần vẽ đường viền bao quanh mặt (giúp giảm tải xử lý nếu không dùng để vẽ UI).
          // Bật tìm các điểm mốc (Mắt, mũi, miệng, má...).
          // QUAN TRỌNG: Dùng để căn chỉnh (align) khuôn mặt cho thẳng trước khi đưa vào AI nhận diện.
          enableLandmarks: true,
          enableClassification: false,
          enableTracking: true,
          minFaceSize: 0.15,
        ),
      );

      await startCamera();

      // Mọi thứ đã xong, giờ mới cho phép hiện UI Camera
      isInitialized.value = true;
      isAiReady.value = true;
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

      // Khối 1: Xử lý Lấy nét (Focus)
      try {
        // Chuyển sang AUTO thay vì LOCKED.
        // Điện thoại hay bị thay đổi khoảng cách cầm tay. Chuyển sang Auto để mặt lúc nào cũng nét.
        await cameraController!.setFocusMode(FocusMode.auto);
      } catch (e) {
        AppLog.warning("⚠️ Camera: Lỗi set FocusMode: $e");
      }

      // Khối 3: Cứ để Auto Exposure (XÓA ĐOẠN KHÓA SÁNG CŨ ĐI)
      try {
        // Đảm bảo camera luôn tự thích nghi với môi trường
        await cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        AppLog.warning("⚠️ Camera: Lỗi set ExposureMode: $e");
      }

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
    if (checkinState.isSuccessCooldown || recognizedName.value != "Unknown") {
      return;
    }

    if (isProcessing.value) return;

    // Khoá luồng xử lý nhận diện
    isProcessing.value = true;

    Face? face;

    try {
      // 1. Detect khuôn mặt (ML Kit - Giữ nguyên)
      face = await _detectFaceFromImage(image);

      // Nếu không có mặt -> Dừng
      if (face == null || face.trackingId == null) {
        _smoother.reset();
        if (checkinState.matchStreak > 0) {
          checkinState.matchStreak = 0;
          checkinState.blurryStreak = 0;
          // AppLog.warning("❌ Face lost. Reset streak.");
        }
        return;
      }

      int currentFaceId = face.trackingId!;
      if (_faceAttempts[currentFaceId] == null) {
        checkinState.matchStreak = 0;
        checkinState.spoofStreak = 0;
        checkinState.blurryStreak = 0; // Xóa sạch tàn dư của người trước!
        if (faceInstruction.value.isNotEmpty) faceInstruction.value = "";
      }
      final faceRect = _smoother.smooth(face.boundingBox);

      if (verifiedFaces.containsKey(currentFaceId)) {
        return; // Đã check-in rồi thì cho CPU nghỉ ngơi
      }

      // 2. Throttling (Giữ nguyên)
      if (_shouldSkipRecognition()) {
        return;
      }

      // 3. Chuẩn bị dữ liệu gửi sang Isolate
      final int totalBytes = image.planes.fold(
        0,
        (sum, plane) => sum + plane.bytes.length,
      );

      if (nativeBuffer == null || _currentBufferSize != totalBytes) {
        if (nativeBuffer != null) {
          calloc.free(nativeBuffer!);
        }
        nativeBuffer = calloc<Uint8>(totalBytes);
        _currentBufferSize = totalBytes;
      }

      // Copy nhanh từ mảng bytes của camera vào native buffer
      int offset = 0;
      for (var plane in image.planes) {
        nativeBuffer!.asTypedList(totalBytes).setAll(offset, plane.bytes);
        offset += plane.bytes.length;
      }

      // 4. Gửi sang Isolate
      // AppLog.info("🚀 Gửi ảnh YUV xuống C++ (Crop + Face + Spoof)...");

      final Map<String, dynamic>? aiResult = await _isolateService
          .processDualTaskInIsolate(
            address: nativeBuffer!.address,
            width: image.width,
            height: image.height,
            yStride: image.planes[0].bytesPerRow,
            face: face,
            rectX: faceRect.left.toInt(),
            rectY: faceRect.top.toInt(),
            rectW: faceRect.width.toInt(),
            rectH: faceRect.height.toInt(),
            rotation: cameraController?.description.sensorOrientation ?? 0,
            spoofSize: _spoofService.inputWidth,
            threshold: _recognitionService.threshold,
          );

      if (checkinState.isSuccessCooldown || recognizedName.value != "Unknown") {
        isProcessing.value = false;
        return;
      }

      if (aiResult == null) {
        AppLog.warning("⚠️ Isolate trả về null, bỏ qua frame này");
        isProcessing.value = false;
        return;
      }

      _faceAttempts[currentFaceId] = (_faceAttempts[currentFaceId] ?? 0) + 1;
      AppLog.info(
        "👀 Tracking ID $currentFaceId | Attempt: ${_faceAttempts[currentFaceId]} | Blurry Streak: ${checkinState.blurryStreak} | Spoof Streak: ${checkinState.spoofStreak}",
      );

      // Giới hạn max 10 khung hình (bao gồm cả mờ và nét)
      if (_faceAttempts[currentFaceId]! > 10) {
        AppLog.warning(
          "⏳ Tracking ID $currentFaceId đã cạn 10 lần thử! Đánh rớt.",
        );

        errorMsg.value = "Không thể nhận diện. Vui lòng thử lại!";

        // Dọn dẹp
        _faceAttempts.remove(currentFaceId);
        checkinState.matchStreak = 0;
        checkinState.spoofStreak = 0;

        // Phạt 2 giây
        checkinState.isSuccessCooldown = true;
        Future.delayed(const Duration(seconds: 2), () {
          checkinState.isSuccessCooldown = false;
          errorMsg.value = "";
        });

        return;
      }

      if (aiResult['status'] == 'blurry') {
        checkinState.blurryStreak++;
        final double qScore = aiResult['qualityScore'];
        AppLog.warning(
          "⚠️ Khung hình mờ bị loại (Score: ${qScore.toStringAsFixed(3)}), chờ frame tiếp theo...",
        );

        // Hiện cảnh báo cho người dùng
        if (checkinState.blurryStreak >= 3) {
          if (faceInstruction.value != "Ảnh bị mờ, vui lòng giữ yên đầu!") {
            faceInstruction.value = "Ảnh bị mờ, vui lòng giữ yên đầu!";
          }
        }

        _lastBlurWarningTime = DateTime.now();
        return;
      }

      checkinState.blurryStreak = 0;
      if (faceInstruction.value == "Ảnh bị mờ, vui lòng giữ yên đầu!") {
        // Chỉ xóa cảnh báo mờ nếu đã trôi qua ít nhất 800 milliseconds
        if (DateTime.now().difference(_lastBlurWarningTime).inMilliseconds >
            800) {
          faceInstruction.value = "";
        }
      } else if (faceInstruction.value.isNotEmpty) {
        // Các cảnh báo khác (nếu có) thì cứ xóa bình thường
        faceInstruction.value = "";
      }
      final String aiName = aiResult['name'] as String;
      final double aiDistance = aiResult['distance'] as double;
      final bool aiIsUnknown = aiResult['isUnknown'] as bool;
      final double spoofScore = aiResult['spoofScore'] as double;
      final double qScore = aiResult['qualityScore'];

      String detectedName = aiIsUnknown ? "Unknown" : aiName;
      bool isRealPerson = spoofScore > _spoofService.threshold;

      AppLog.info(
        "🔍 KẾT QUẢ AI -> Tên: $detectedName, Real Score: ${(spoofScore * 100).toStringAsFixed(1)}%>60%, Quality Score: ${(qScore * 100).toStringAsFixed(1)}%>40%",
      );

      if (detectedName != "Unknown" && isRealPerson) {
        // ✅ QUAN TRỌNG: Xóa lỗi cũ ngay khi nhận diện thành công
        if (errorMsg.value.isNotEmpty) {
          errorMsg.value = "";
        }

        checkinState.spoofStreak = 0;
        isSpoofing.value = false;

        // Nếu là người mới hoặc đang track dở người này
        if (detectedName == checkinState.currentCandidate) {
          checkinState.matchStreak++; // Tăng điểm tin cậy
        } else {
          // Đổi người -> Reset
          checkinState.currentCandidate = detectedName;
          checkinState.matchStreak = 1;
          // AppLog.info("🔄 Tracking new: $detectedName");
        }

        // AppLog.info(
        //   "🚀 Verified: $detectedName | Progress: ${checkinState.matchStreak}/3",
        // );

        // Đủ điều kiện check-in (Ví dụ: 3 lần liên tiếp đúng cả ID lẫn Liveness)
        if (checkinState.matchStreak >=
            FaceCheckinState.requiredRecognitionStreak) {
          recognizedName.value = checkinState.currentCandidate!;
          verifiedFaces[currentFaceId] = recognizedName.value;

          _faceAttempts.remove(currentFaceId);

          // 1. GỌI HÀM NÉN ẢNH LUÔN (Truyền đúng cái nativeBuffer đang dùng)
          final jpegBytes = FaceImagePipelineNative.encodeYuvToJpeg(
            ptrYuv: nativeBuffer!,
            width: image.width,
            height: image.height,
            rotation: cameraController?.description.sensorOrientation ?? 0,
          );

          String? localImagePath;

          // 2. LƯU THÀNH FILE JPG XUỐNG ĐIỆN THOẠI
          if (jpegBytes != null) {
            // Lấy thư mục ẩn của App (Người dùng không tự xóa được)
            final directory = await getApplicationDocumentsDirectory();
            final fileName =
                'evidence_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final file = File('${directory.path}/$fileName');

            await file.writeAsBytes(jpegBytes);
            localImagePath = file.path;
            // AppLog.info("📸 Đã lưu ảnh bằng chứng: $localImagePath");
          }

          unawaited(
            _handleCheckinSuccess(
              studentId: checkinState.currentCandidate!,
              confidence: aiDistance,
              livenessScore: spoofScore,
              localImagePath: localImagePath,
            ),
          );

          checkinState.isSuccessCooldown =
              true; // Bật cooldown ngay khi check-in thành công
        }
      } else {
        // Reset streak nếu đứt quãng
        checkinState.matchStreak = 0;

        // A. NẾU LÀ GIẢ MẠO (Spoof)
        if (!isRealPerson) {
          isSpoofing.value = true;

          checkinState.spoofStreak++;
          // AppLog.warning(
          //   "⚠️ SPOOF DETECTED for $detectedName | Streak: ${checkinState.spoofStreak}",
          // );

          if (checkinState.spoofStreak >=
              FaceCheckinState.requiredSpoofStreak) {
            errorMsg.value = "⚠️ Cảnh báo: Phát hiện khuôn mặt không hợp lệ!";

            // TODO: Gửi cảnh báo gian lận về server tại đây
            // unawaited(_reportSpoofToServer(detectedName));

            // Tuỳ chọn: Bật cooldown để khoá nhận diện trong 2-3 giây
            checkinState.isSuccessCooldown = true;

            Future.delayed(const Duration(seconds: 3), () {
              checkinState.isSuccessCooldown = false;
              errorMsg.value = ""; // Xóa chữ thông báo
              isSpoofing.value = false; // Xóa luôn viền đỏ
            });

            // Có thể reset spoofStreak sau khi đã cảnh báo, hoặc để nó giữ nguyên
            // cho đến khi frame nhận ra người thật (đã xử lý ở block trên)
            checkinState.spoofStreak = 0; // Reset sau khi đã cảnh báo
          }
        } else {
          // B. NẾU LÀ NGƯỜI THẬT NHƯNG KHÔNG NHẬN RA (Unknown)
          // Hoặc frame này bình thường trở lại -> Xóa lỗi "Giả mạo" đi
          isSpoofing.value = false;
          // checkinState.spoofStreak = 0;
          errorMsg.value = ""; // ✅ Reset về trạng thái bình thường
        }

        // Không reset currentCandidate ngay để tránh UI nhấp nháy, chỉ reset điểm
      }
    } catch (e, s) {
      AppLog.error("❌ Lỗi processFrame: $e");
      AppLog.error("Dấu vết (StackTrace):\n$s");
    } finally {
      // // Tổng kết thời gian 1 frame
      // sw.stop();

      await Future.delayed(const Duration(milliseconds: 400));

      isProcessing.value = false; // Mở khóa để xử lý frame tiếp theo
    }
  }

  @override
  void onClose() {
    // AppLog.info("🧹 Bắt đầu dọn dẹp tài nguyên màn hình Camera...");
    isProcessing.value = true;

    _audioPlayer.dispose();
    _faceDetector.close();
    verifiedFaces.clear();
    _faceAttempts.clear();

    // Dọn dẹp RAM
    if (nativeBuffer != null) {
      calloc.free(nativeBuffer!);
      nativeBuffer = null;
    }

    // Xử lý Camera an toàn
    if (cameraController != null) {
      try {
        cameraController!.dispose();
        cameraController = null;
        // AppLog.info("✅ Đã giải phóng Camera");
      } catch (e) {
        AppLog.error("❌ Lỗi khi đóng camera: $e");
      }
    }

    super.onClose();
  }
}
