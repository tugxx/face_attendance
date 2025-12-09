// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:face_attendance/app/modules/camera_attendance/controllers/camera_controller.dart';

// class CameraAttendanceView extends GetView<CameraAttendanceController> {
//   const CameraAttendanceView({super.key});

//   @override
//   Widget build(BuildContext context) {
//     // Inject Controller vào View (nếu chưa có Binding thì Get.put tạm ở đây)
//     Get.put(CameraAttendanceController());

//     // Trong Widget build của bạn
//     GetX<CameraAttendanceController>(
//       init: CameraAttendanceController(),
//       builder: (controller) {
//         return Column(
//           children: [
//             // Phần hiển thị Camera Preview (Giữ nguyên của bạn)
//             if (controller.isInitialized.value &&
//                 controller.cameraController != null)
//               AspectRatio(
//                 aspectRatio: controller.cameraController!.value.aspectRatio,
//                 child: CameraPreview(controller.cameraController!),
//               )
//             else
//               Container(
//                 height: 300,
//                 color: Colors.black,
//                 child: Center(
//                   child: controller.isLoading.value
//                       ? CircularProgressIndicator()
//                       : Text(
//                           controller.errorMsg.value,
//                           style: TextStyle(color: Colors.white),
//                         ),
//                 ),
//               ),

//             SizedBox(height: 20),

//             // --- PHẦN CHỌN CAMERA MỚI ---
//             // Chỉ hiện khi có danh sách camera
//             if (controller.availableCamerasList.isNotEmpty)
//               Padding(
//                 padding: const EdgeInsets.all(8.0),
//                 child: DropdownButton<CameraDescription>(
//                   isExpanded: true,
//                   value:
//                       controller.selectedCameraDesc.value, // Giá trị hiện tại
//                   items: controller.availableCamerasList.map((camera) {
//                     return DropdownMenuItem(
//                       value: camera,
//                       // Hiển thị tên camera (trên Web thường là "Camera 1", "FaceTime Camera"...)
//                       child: Text(
//                         "Cam ${controller.availableCamerasList.indexOf(camera) + 1}: ${camera.name} (${camera.lensDirection})",
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     );
//                   }).toList(),
//                   onChanged: (CameraDescription? newCamera) {
//                     if (newCamera != null) {
//                       // Gọi hàm chuyển camera trong controller
//                       controller.selectCamera(newCamera);
//                     }
//                   },
//                 ),
//               ),
//           ],
//         );
//       },
//     );

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Obx(() {
//         // TRƯỜNG HỢP 1: Đang tải (đang xin quyền hoặc khởi động cam)
//         if (controller.isLoading.value) {
//           return const Center(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 CircularProgressIndicator(),
//                 SizedBox(height: 10),
//                 Text(
//                   "Đang khởi động Camera...",
//                   style: TextStyle(color: Colors.white),
//                 ),
//               ],
//             ),
//           );
//         }

//         // TRƯỜNG HỢP 2: Có lỗi -> Hiện lỗi + Nút thử lại
//         if (controller.errorMsg.value.isNotEmpty) {
//           return Center(
//             child: Padding(
//               padding: const EdgeInsets.all(20.0),
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   const Icon(Icons.error_outline, color: Colors.red, size: 48),
//                   const SizedBox(height: 10),
//                   Text(
//                     controller.errorMsg.value,
//                     style: const TextStyle(color: Colors.white, fontSize: 16),
//                     textAlign: TextAlign.center,
//                   ),
//                   const SizedBox(height: 20),
//                   ElevatedButton.icon(
//                     onPressed: () => controller.startCamera(), // Thử lại
//                     icon: const Icon(Icons.refresh),
//                     label: const Text("Thử lại"),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         }

//         // TRƯỜNG HỢP 3: Camera đã sẵn sàng -> Hiển thị Preview
//         if (controller.isInitialized.value &&
//             controller.cameraController != null) {
//           return Stack(
//             alignment: Alignment.center,
//             children: [
//               // 1. Màn hình Camera full
//               SizedBox(
//                 width: double.infinity,
//                 height: double.infinity,
//                 child: CameraPreview(controller.cameraController!),
//               ),

//               // 2. Lớp phủ hướng dẫn
//               Positioned(
//                 bottom: 50,
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 20,
//                     vertical: 10,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Colors.black54,
//                     borderRadius: BorderRadius.circular(20),
//                   ),
//                   child: const Text(
//                     "Đưa khuôn mặt vào khung hình",
//                     style: TextStyle(color: Colors.white, fontSize: 16),
//                   ),
//                 ),
//               ),

//               // Nút tắt/back (tuỳ chọn)
//               Positioned(
//                 top: 40,
//                 left: 20,
//                 child: IconButton(
//                   icon: const Icon(Icons.arrow_back, color: Colors.white),
//                   onPressed: () => Get.back(),
//                 ),
//               ),
//             ],
//           );
//         }

//         // TRƯỜNG HỢP 4 (Mặc định): Chưa làm gì cả -> Hiện nút Bấm để bắt đầu
//         // Đây là bước quan trọng để Chrome không chặn Camera
//         return Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const Icon(Icons.camera_alt, size: 60, color: Colors.grey),
//               const SizedBox(height: 20),
//               const Text(
//                 "Hệ thống điểm danh khuôn mặt",
//                 style: TextStyle(color: Colors.white, fontSize: 18),
//               ),
//               const SizedBox(height: 30),
//               ElevatedButton(
//                 style: ElevatedButton.styleFrom(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 30,
//                     vertical: 15,
//                   ),
//                 ),
//                 onPressed: () {
//                   // Gọi hàm startCamera khi người dùng bấm nút
//                   controller.startCamera();
//                 },
//                 child: const Text("Bắt đầu Camera"),
//               ),
//             ],
//           ),
//         );
//       }),
//     );
//   }
// }

// views/camera_view.dart

// 1. CÁC IMPORT CẦN THIẾT
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// Import Controller của bạn (Hãy sửa đường dẫn nếu báo lỗi)
import '../controllers/camera_controller.dart';


// 2. CLASS VẼ KHUNG MẶT (Painter)
// Mình gộp vào đây luôn để file View nhận diện được
class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final InputImageRotation rotation;

  FaceDetectorPainter(this.faces, this.absoluteImageSize, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.greenAccent; // Màu khung: Xanh lá

    for (final Face face in faces) {
      // Logic Scale: Cực kỳ quan trọng để vẽ đúng vị trí trên màn hình điện thoại
      // Vì ảnh Camera (ví dụ 1280x720) khác kích thước màn hình (ví dụ 400x800)
      
      final double scaleX = size.width / absoluteImageSize.width;
      final double scaleY = size.height / absoluteImageSize.height;

      // Tính toán lại tọa độ khung bao (BoundingBox) theo tỉ lệ màn hình
      // Lưu ý: Cam trước thường bị lật ngược (Mirror), cần xử lý lật lại nếu cần
      // Ở đây mình vẽ đơn giản, nếu bị lệch thì cần tính toán thêm logic 'flip'
      
      final left = face.boundingBox.left * scaleX;
      final top = face.boundingBox.top * scaleY;
      final right = face.boundingBox.right * scaleX;
      final bottom = face.boundingBox.bottom * scaleY;

      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}


// 3. CLASS VIEW CHÍNH
class CameraAttendanceView extends GetView<CameraAttendanceController> {
  const CameraAttendanceView({super.key});

  @override
  Widget build(BuildContext context) {
    // Nếu chưa binding ở Route thì put tạm ở đây để test
    Get.put(CameraAttendanceController());

    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        // TRƯỜNG HỢP 1: Có lỗi
        if (controller.errorMsg.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                controller.errorMsg.value, 
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // TRƯỜNG HỢP 2: Chưa khởi tạo xong
        if (!controller.isInitialized.value || controller.cameraController == null) {
          return Center(
            child: ElevatedButton.icon(
              onPressed: controller.startCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text("Bắt đầu Điểm danh"),
            ),
          );
        }

        // TRƯỜNG HỢP 3: Camera đã chạy -> Hiển thị Preview + Khung mặt
        var camera = controller.cameraController!.value;
        // Lấy kích thước ảnh gốc từ camera sensor (Ví dụ: 720x1280)
        // Nếu null thì lấy mặc định Size.zero để tránh crash
        final Size imageSize = Size(
          camera.previewSize?.height ?? 0, 
          camera.previewSize?.width ?? 0,
        ); 
        // Lưu ý: Android camera trả về chiều ngang/dọc ngược nhau nên cần cẩn thận swap width/height tuỳ orientation
        
        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Camera Preview
            CameraPreview(controller.cameraController!),

            // Layer 2: Vẽ khung mặt (Overlay)
            if (controller.detectedFaces.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: FaceDetectorPainter(
                    controller.detectedFaces.toList(),
                    imageSize, 
                    InputImageRotation.rotation0deg,
                  ),
                ),
              ),

            // Layer 3: UI Hướng dẫn / Trạng thái
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white24)
                  ),
                  child: Text(
                    controller.detectedFaces.isEmpty 
                      ? "Xin hãy nhìn vào Camera" 
                      : "Đang xác thực khuôn mặt...",
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 16, 
                      fontWeight: FontWeight.w500
                    ),
                  ),
                ),
              ),
            ),
            
            // Nút Back
            Positioned(
              top: 50,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Get.back(),
                ),
              ),
            )
          ],
        );
      }),
    );
  }
}