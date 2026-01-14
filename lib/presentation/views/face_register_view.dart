import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../controllers/face_register_controller.dart';
import '../widgets/face_detector_painter.dart'; 

class FaceRegisterView extends GetView<FaceRegisterController> {
  const FaceRegisterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (!controller.isInitialized.value || controller.cameraController == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera
            CameraPreview(controller.cameraController!),

            // 2. Khung xanh
            if (controller.detectedFaces.isNotEmpty)
               // ... (Copy đoạn SizedBox.expand + CustomPaint chuẩn V2 từ AttendanceView sang) ...
               SizedBox.expand(
                child: CustomPaint(
                  painter: FaceDetectorPainter(
                    controller.detectedFaces.toList(),
                    Size(
                      controller.cameraController!.value.previewSize!.width,
                      controller.cameraController!.value.previewSize!.height,
                    ),
                    InputImageRotationValue.fromRawValue(
                      controller.cameraController!.description.sensorOrientation
                    ) ?? InputImageRotation.rotation0deg,
                    controller.cameraController!.description.lensDirection,
                  ),
                ),
              ),

            // 3. Hướng dẫn & Loading Overlay
            if (controller.isRegistering.value)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text("Đang xử lý hình ảnh...", style: TextStyle(color: Colors.white, fontSize: 18)),
                    ],
                  ),
                ),
              )
            else
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Giữ khuôn mặt ổn định để tự động chụp",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            
            // Nút Back
            Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Get.back(),
              ),
            ),
          ],
        );
      }),
    );
  }
}