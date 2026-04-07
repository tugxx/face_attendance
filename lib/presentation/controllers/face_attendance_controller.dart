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
import '../../app/extensions/app_profiler.dart';
import '../../app/services/ml_kit_face_service.dart';
import '../../app/services/face_quality_service.dart';

class FaceCheckinState {
  // Biến cấu hình
  static const int requiredRecognitionStreak =
      3; // Cần 3 lần nhận diện đúng tên
  static const int requiredSpoofStreak = 5; // Cần 5 lần phát hiện giả mạo

  // Biến trạng thái runtime
  String? currentCandidate; // Tên người đang theo dõi
  int matchStreak = 0; // Đếm số lần nhận diện đúng liên tiếp
  int spoofStreak = 0; // Đếm số lần phát hiện giả mạo liên tiếp
  int livenessStreak = 0; // Đếm số lần liveness pass liên tiếp
  bool isSuccessCooldown = false; // Chế độ chờ sau khi điểm danh thành công

  int blurryStreak = 0;

  final Stopwatch sessionTimer = Stopwatch();

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

  final _mlKitService = Get.find<MLKitFaceService>();

  final FaceAntiSpoofingService _spoofService =
      Get.find<FaceAntiSpoofingService>();

  final FaceQualityAssessor _qualityService = Get.find<FaceQualityAssessor>();

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
  var detectedFaces = <Face>[].obs;

  DateTime _lastBlurWarningTime = DateTime.now();

  CameraDescription? _currentCamera;

  var faceInstruction = "".obs;

  Pointer<Uint8>? nativeBuffer;
  int _currentBufferSize = 0;

  Map<int, String> verifiedFaces = {};
  final Map<int, int> _faceAttempts = {};

  bool _isIsolateRunning = false;

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
    final faces = await _mlKitService.processImage(inputImage);

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
        faceInstruction.value = "⚠️ Quá gần! Vui lòng lùi ra xa";
        return null;
      }

      if (faceInstruction.value.isNotEmpty) {
        faceInstruction.value = "";
      }
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

  Future<String?> _saveEvidenceImage(
    Uint8List? jpegBytes,
    bool isHardNegative,
  ) async {
    if (jpegBytes == null) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final prefix = isHardNegative ? 'hard_negative' : 'evidence';
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(jpegBytes);
      return file.path;
    } catch (e) {
      AppLog.error("Lỗi lưu ảnh bằng chứng: $e");
      return null;
    }
  }

  Future<void> _handleCheckinSuccess({
    required String studentId,
    required double confidence,
    required double livenessScore,
    required double qualityScore,
    required int totalCheckinTimeMs,
    required int detectTimeMs,
    required int isolateTimeMs,
    required int totalAttempts,
    required int spoofStreakEncountered,
    String? matchedTemplateId,
    String? imposterName,
    double? margin,
    bool isHardNegative = false,
    Uint8List? jpegBytes,
  }) async {
    checkinState.isSuccessCooldown = true; // Khóa hệ thống

    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.play(
      AssetSource(
        'sounds/miraclei-sample_confirm_accept01_kofi_by_miraclei-364181.mp3',
      ),
    );

    HapticFeedback.vibrate();

    // AppLog.info("🎉 CHECKIN SUCCESS: $studentId");

    recognizedName.value = studentId;

    // 1. Sinh UUID tại App
    final String recordUuid = const Uuid().v4();
    final now = DateTime.now();

    // 👉 Tự xử lý dữ liệu nội bộ
    final String currentEventType = "in"; // TODO: Logic IN/OUT
    final String finalLocation = "unknown_gps"; // TODO: Logic lấy GPS
    // final String? shiftCode = _getCurrentShiftCode(); // Tự gọi nội bộ

    // 👉 Tự gọi hàm lưu file
    final String? localImagePath = await _saveEvidenceImage(
      jpegBytes,
      isHardNegative,
    );

    // 2. Gom dữ liệu chuẩn Thực tế
    Map<String, dynamic> offlineLog = {
      "id": recordUuid,
      "student_id": studentId,
      "device_id": DeviceService().deviceId,
      "location_code": finalLocation,
      // "shift_code": shiftCode,
      "check_in_time": now.toUtc().toIso8601String(),
      "event_date":
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
      "event_type": currentEventType,
      "method": "face",

      "confidence_score": confidence,
      "liveness_score": livenessScore,
      "face_quality_score": qualityScore,
      "matched_template_id": matchedTemplateId,

      "total_checkin_time_ms": totalCheckinTimeMs,
      "total_attempts_needed": totalAttempts,
      "blurry_streak_encountered": checkinState.blurryStreak,
      "spoof_streak_encountered": spoofStreakEncountered,

      "quality_model_used": _qualityService.modelName,
      "liveness_model_used": _spoofService.modelName,
      "recognition_model_used": _recognitionService.modelName,

      "telemetry_data": {
        "time_mlkit_detect_ms": detectTimeMs,
        "time_cpp_isolate_ms": isolateTimeMs,
        "total_pipeline_ms": detectTimeMs + isolateTimeMs,

        "closest_imposter_name": imposterName,
        "confusion_margin": margin,
      },

      "is_hard_negative": isHardNegative,

      "is_offline_log": false,
      "sync_status": "PENDING",
      "image_path": localImagePath,
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

    try {
      // Bắt đầu quy trình khởi tạo
      isInitialized.value = false;
      isAiReady.value = false;
      isProcessing.value = false;

      await startCamera();

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

    final profiler = AppProfiler()..start();

    Face? face;

    try {
      // 1. Detect khuôn mặt (ML Kit - Giữ nguyên)
      face = await profiler.measureStep(
        "DetectFace",
        () async => _detectFaceFromImage(image),
      );

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

        checkinState.sessionTimer.reset();
        checkinState.sessionTimer.start();
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
      _isIsolateRunning = true;
      final Map<String, dynamic>? aiResult;

      try {
        aiResult = await profiler.measureStep(
          "IsolateC++",
          () async => await _isolateService.processDualTaskInIsolate(
            address: nativeBuffer!.address,
            width: image.width,
            height: image.height,
            yStride: image.planes[0].bytesPerRow,
            face: face!,
            rectX: faceRect.left.toInt(),
            rectY: faceRect.top.toInt(),
            rectW: faceRect.width.toInt(),
            rectH: faceRect.height.toInt(),
            rotation: cameraController?.description.sensorOrientation ?? 0,
            spoofSize: _spoofService.inputWidth,
            recognitionThreshold: _recognitionService.threshold,
            spoofThreshold: _spoofService.threshold,
            qualityThreshold: _qualityService.threshold,
          ),
        );
      } finally {
        _isIsolateRunning = false;
      }

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
        checkinState.sessionTimer.stop(); // Dừng đồng hồ
        AppLog.warning(
          "⏳ Đánh rớt ID $currentFaceId sau ${checkinState.sessionTimer.elapsedMilliseconds}ms do cạn 10 lần thử.",
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
      final double aiScore = aiResult['score'] as double;
      final bool aiIsUnknown = aiResult['isUnknown'] as bool;
      final double spoofScore = aiResult['spoofScore'] as double;
      final double qScore = aiResult['qualityScore'];
      final String? matchedTemplateId = aiResult['matchedTemplateId'];

      final String? imposterName = aiResult['imposterName'];
      final double imposterScore = aiResult['imposterScore'] ?? -1.0;

      final double margin = aiScore - imposterScore;
      final bool isHardNegative = margin < 0.15;

      String detectedName = aiIsUnknown ? "Unknown" : aiName;
      bool isRealPerson = spoofScore > _spoofService.threshold;

      AppLog.info(
        "🔍 KẾT QUẢ AI -> Tên: $detectedName, Real Score: ${(spoofScore * 100).toStringAsFixed(1)}%>60%, Quality Score: ${(qScore * 100).toStringAsFixed(1)}%>37%",
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

        // Đủ điều kiện check-in
        if (checkinState.matchStreak >=
            FaceCheckinState.requiredRecognitionStreak) {
          checkinState.sessionTimer.stop();
          final int totalCheckinTime =
              checkinState.sessionTimer.elapsedMilliseconds;

          AppLog.info(
            "🎉 CHECKIN SUCCESS: $detectedName | ⏱️ TỔNG THỜI GIAN THỰC TẾ (TTC): ${totalCheckinTime}ms",
          );

          recognizedName.value = checkinState.currentCandidate!;
          verifiedFaces[currentFaceId] = recognizedName.value;

          _faceAttempts.remove(currentFaceId);

          checkinState.isSuccessCooldown = true;

          // 1. GỌI HÀM NÉN ẢNH LUÔN (Truyền đúng cái nativeBuffer đang dùng)
          final jpegBytes = await profiler.measureStep("Encode_JPEG", () async {
            return FaceImagePipelineNative.encodeYuvToJpeg(
              ptrYuv: nativeBuffer!,
              width: image.width,
              height: image.height,
              rotation: cameraController?.description.sensorOrientation ?? 0,
            );
          });

          final int detectTime = profiler.getMetric("DetectFace") ?? 0;
          final int isolateTime = profiler.getMetric("IsolateC++") ?? 0;

          unawaited(
            _handleCheckinSuccess(
              studentId: checkinState.currentCandidate!,
              confidence: aiScore,
              livenessScore: spoofScore,
              qualityScore: qScore,
              totalCheckinTimeMs: totalCheckinTime,
              detectTimeMs: detectTime,
              isolateTimeMs: isolateTime,
              totalAttempts: _faceAttempts[currentFaceId] ?? 0,
              spoofStreakEncountered: checkinState.spoofStreak,
              matchedTemplateId: matchedTemplateId,
              imposterName: imposterName,
              margin: margin,
              isHardNegative: isHardNegative,
              jpegBytes: jpegBytes,
            ),
          );
        }
      } else {
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

            // ==========================================
            // 🎯 TODO: THU THẬP DATA TRAINING ANTI-SPOOFING
            // Gọi hàm encodeYuvToJpeg (như lúc check-in thành công) để nén ảnh.
            // Sau đó lưu file prefix 'spoof_evidence_...' và bắn API gửi về Server.
            // Dữ liệu này cực kỳ quý giá để train lại model chống in ảnh/dùng điện thoại!
            // unawaited(_reportSpoofToServer(detectedName, localImagePath));
            // ==========================================

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
      profiler.report();

      await Future.delayed(const Duration(milliseconds: 400));

      isProcessing.value = false; // Mở khóa để xử lý frame tiếp theo
    }
  }

  @override
  void onClose() {
    // AppLog.info("🧹 Bắt đầu dọn dẹp tài nguyên màn hình Camera...");
    final wasProcessing = isProcessing.value;
    isProcessing.value = true;

    _audioPlayer.dispose();
    verifiedFaces.clear();
    _faceAttempts.clear();

    if (cameraController != null) {
      try {
        // Dừng đẩy frame mới để tránh lỗi buffer
        if (cameraController!.value.isStreamingImages) {
          cameraController!.stopImageStream();
        }
        cameraController!.dispose();
        cameraController = null;
      } catch (e) {
        AppLog.error("❌ Lỗi khi đóng camera: $e");
      }
    }

    _safeFreeMemory(wasProcessing);

    super.onClose();
  }

  Future<void> _safeFreeMemory(bool isAiBusy) async {
    if (nativeBuffer == null) return;

    int timeoutCount = 0;
    while (_isIsolateRunning && timeoutCount < 20) {
      // Vòng lặp chờ tối đa 20 * 50ms = 1 giây (Timeout an toàn)
      await Future.delayed(const Duration(milliseconds: 50));
      timeoutCount++;
    }

    // Nếu quá 1 giây mà C++ chưa xong -> Cảnh báo (Hiếm khi xảy ra)
    if (_isIsolateRunning) {
      AppLog.warning(
        "⚠️ Isolate C++ tốn quá nhiều thời gian để đóng, ép giải phóng RAM!",
      );
    }

    if (nativeBuffer != null) {
      calloc.free(nativeBuffer!);
      nativeBuffer = null;
    }
  }
}
