// // views/camera_view.dart
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// // Import Controller của bạn (Hãy sửa đường dẫn nếu báo lỗi)
// import '../controllers/camera_controller.dart';


// // 2. CLASS VẼ KHUNG MẶT (Painter)
// // Mình gộp vào đây luôn để file View nhận diện được
// class FaceDetectorPainter extends CustomPainter {
//   final List<Face> faces;
//   final Size absoluteImageSize;
//   final InputImageRotation rotation;

//   FaceDetectorPainter(this.faces, this.absoluteImageSize, this.rotation);

//   @override
//   void paint(Canvas canvas, Size size) {
//     final Paint paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3.0
//       ..color = Colors.greenAccent; // Màu khung: Xanh lá

//     for (final Face face in faces) {
//       // Logic Scale: Cực kỳ quan trọng để vẽ đúng vị trí trên màn hình điện thoại
//       // Vì ảnh Camera (ví dụ 1280x720) khác kích thước màn hình (ví dụ 400x800)
      
//       final double scaleX = size.width / absoluteImageSize.width;
//       final double scaleY = size.height / absoluteImageSize.height;

//       // Tính toán lại tọa độ khung bao (BoundingBox) theo tỉ lệ màn hình
//       // Lưu ý: Cam trước thường bị lật ngược (Mirror), cần xử lý lật lại nếu cần
//       // Ở đây mình vẽ đơn giản, nếu bị lệch thì cần tính toán thêm logic 'flip'
      
//       final left = face.boundingBox.left * scaleX;
//       final top = face.boundingBox.top * scaleY;
//       final right = face.boundingBox.right * scaleX;
//       final bottom = face.boundingBox.bottom * scaleY;

//       canvas.drawRect(
//         Rect.fromLTRB(left, top, right, bottom),
//         paint,
//       );
//     }
//   }

//   @override
//   bool shouldRepaint(FaceDetectorPainter oldDelegate) {
//     return oldDelegate.faces != faces;
//   }
// }


// // 3. CLASS VIEW CHÍNH
// class CameraAttendanceView extends GetView<CameraAttendanceController> {
//   const CameraAttendanceView({super.key});

//   @override
//   Widget build(BuildContext context) {
//     // Nếu chưa binding ở Route thì put tạm ở đây để test
//     Get.put(CameraAttendanceController());

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Obx(() {
//         // TRƯỜNG HỢP 1: Có lỗi
//         if (controller.errorMsg.value.isNotEmpty) {
//           return Center(
//             child: Padding(
//               padding: const EdgeInsets.all(20),
//               child: Text(
//                 controller.errorMsg.value, 
//                 style: const TextStyle(color: Colors.red),
//                 textAlign: TextAlign.center,
//               ),
//             ),
//           );
//         }

//         // TRƯỜNG HỢP 2: Chưa khởi tạo xong
//         if (!controller.isInitialized.value || controller.cameraController == null) {
//           return Center(
//             child: ElevatedButton.icon(
//               onPressed: controller.startCamera,
//               icon: const Icon(Icons.camera_alt),
//               label: const Text("Bắt đầu Điểm danh"),
//             ),
//           );
//         }

//         // TRƯỜNG HỢP 3: Camera đã chạy -> Hiển thị Preview + Khung mặt
//         var camera = controller.cameraController!.value;
//         // Lấy kích thước ảnh gốc từ camera sensor (Ví dụ: 720x1280)
//         // Nếu null thì lấy mặc định Size.zero để tránh crash
//         final Size imageSize = Size(
//           camera.previewSize?.height ?? 0, 
//           camera.previewSize?.width ?? 0,
//         ); 
//         // Lưu ý: Android camera trả về chiều ngang/dọc ngược nhau nên cần cẩn thận swap width/height tuỳ orientation
        
//         return Stack(
//           fit: StackFit.expand,
//           children: [
//             // Layer 1: Camera Preview
//             CameraPreview(controller.cameraController!),

//             // Layer 2: Vẽ khung mặt (Overlay)
//             if (controller.detectedFaces.isNotEmpty)
//               Positioned.fill(
//                 child: CustomPaint(
//                   painter: FaceDetectorPainter(
//                     controller.detectedFaces.toList(),
//                     imageSize, 
//                     InputImageRotation.rotation0deg,
//                   ),
//                 ),
//               ),

//             // Layer 3: UI Hướng dẫn / Trạng thái
//             Positioned(
//               bottom: 80,
//               left: 20,
//               right: 20,
//               child: Center(
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                   decoration: BoxDecoration(
//                     color: Colors.black54,
//                     borderRadius: BorderRadius.circular(30),
//                     border: Border.all(color: Colors.white24)
//                   ),
//                   child: Text(
//                     controller.detectedFaces.isEmpty 
//                       ? "Xin hãy nhìn vào Camera" 
//                       : "Đang xác thực khuôn mặt...",
//                     style: const TextStyle(
//                       color: Colors.white, 
//                       fontSize: 16, 
//                       fontWeight: FontWeight.w500
//                     ),
//                   ),
//                 ),
//               ),
//             ),
            
//             // Nút Back
//             Positioned(
//               top: 50,
//               left: 20,
//               child: CircleAvatar(
//                 backgroundColor: Colors.black45,
//                 child: IconButton(
//                   icon: const Icon(Icons.arrow_back, color: Colors.white),
//                   onPressed: () => Get.back(),
//                 ),
//               ),
//             )
//           ],
//         );
//       }),
//     );
//   }
// }