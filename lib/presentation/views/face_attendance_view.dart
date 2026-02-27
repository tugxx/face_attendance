import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../controllers/face_attendance_controller.dart';
import '../widgets/face_detector_painter.dart';

class FaceAttendanceView extends GetView<FaceAttendanceController> {
  const FaceAttendanceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Obx(() {
        // 1. Xử lý lỗi
        if (controller.errorMsg.value.isNotEmpty) {
          return Center(
            child: Text(
              controller.errorMsg.value,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        }

        // 2. Màn hình Loading (Khi chưa init xong HOẶC camera chưa có)
        if (!controller.isInitialized.value ||
            controller.cameraController == null) {
          return Container(
            color: Colors.black, // Nền đen cho đồng bộ
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CircularProgressIndicator(color: Colors.blue), // Vòng xoay
                SizedBox(height: 20),
                Text(
                  "Đang tải dữ liệu & Camera...",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera Preview (Flutter tự xử lý scale/rotate để hiển thị full màn hình)
            CameraPreview(controller.cameraController!),

            // Layer 2: Vẽ khung
            if (controller.detectedFaces.isNotEmpty)
              SizedBox.expand(
                child: CustomPaint(
                  painter: FaceDetectorPainter(
                    controller.detectedFaces.toList(),
                    Size(
                      controller.cameraController!.value.previewSize!.width,
                      controller.cameraController!.value.previewSize!.height,
                    ),
                    InputImageRotationValue.fromRawValue(
                          controller
                              .cameraController!
                              .description
                              .sensorOrientation,
                        ) ??
                        InputImageRotation.rotation0deg,
                    controller.cameraController!.description.lensDirection,
                  ),
                ),
              ),

            // Layer UI điều khiển (Nút back, trạng thái text...)
            _buildOverlayUI(),
          ],
        );
      }),
    );
  }

  Widget _buildOverlayUI() {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black54, // Nền đen mờ
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24), // Viền nhẹ cho đẹp
          ),
          child: Obx(() {
            // LOGIC HIỂN THỊ TRẠNG THÁI THÔNG MINH
            String statusText = "";
            Color statusColor = Colors.white;

            if (controller.faceInstruction.value.isNotEmpty) {
              statusText = controller.faceInstruction.value;
              statusColor = Colors.orangeAccent; // Màu cam cảnh báo
            } else if (controller.isProcessing.value) {
              // 1. Đang chạy TFLite (Máy đang tính toán)
              statusText = "⏳ Đang xử lý hình ảnh...";
              statusColor = Colors.yellowAccent;
            } else if (controller.recognizedName.value != "Unknown") {
              // 2. Đã nhận diện ra tên
              statusText = "✅ Xin chào: ${controller.recognizedName.value}";
              statusColor = Colors.greenAccent;
            } else if (controller.detectedFaces.isNotEmpty) {
              // 3. Thấy mặt nhưng chưa nhận diện xong/chưa đủ điều kiện
              statusText = "🔍 Đang nhận diện...";
            } else {
              // 4. Không thấy ai
              statusText = "Xin hãy nhìn vào Camera";
            }

            return Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            );
          }),
        ),
      ),
    );
  }
}
