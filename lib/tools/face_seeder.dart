// import 'dart:convert';
// import 'dart:io';

// import 'package:dio/dio.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:image/image.dart' as img;
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:flutter_image_compress/flutter_image_compress.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:archive/archive.dart';

// import '../app/types/face_progress.dart';
// import 'model_service.dart';

// class FaceSeeder extends StatefulWidget {
//   const FaceSeeder({super.key});

//   @override
//   State<FaceSeeder> createState() => _FaceSeederState();
// }

// class _FaceSeederState extends State<FaceSeeder> {
//   String _status = "Sẵn sàng...";
//   bool _isProcessing = false;
//   final ToolAIService _aiService = ToolAIService();
//   late FaceDetector _faceDetector;

//   Map<String, List<List<double>>> tempMapEmbeddings = {};
//   final Map<String, int> _debugImageCounter = {};

//   // ---------------------------------------------------------------
//   //  Helper
//   // ---------------------------------------------------------------

//   // void _saveDebugCrop(List<double> pixels, String name) async {
//   //   try {
//   //     final extDir = await getExternalStorageDirectory(); // path_provider
//   //     final debugDir = Directory('${extDir!.path}/debug_seed_check');
//   //     if (!await debugDir.exists()) await debugDir.create(recursive: true);

//   //     // Convert List<double> [-1, 1] về lại Image [0, 255]
//   //     var imgOut = img.Image(width: 112, height: 112);
//   //     int ptr = 0;
//   //     for (int y = 0; y < 112; y++) {
//   //       for (int x = 0; x < 112; x++) {
//   //         int r = ((pixels[ptr++] * 128) + 128).toInt().clamp(0, 255);
//   //         int g = ((pixels[ptr++] * 128) + 128).toInt().clamp(0, 255);
//   //         int b = ((pixels[ptr++] * 128) + 128).toInt().clamp(0, 255);
//   //         imgOut.setPixelRgb(x, y, r, g, b);
//   //       }
//   //     }

//   //     File(
//   //       '${debugDir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.jpg',
//   //     ).writeAsBytes(img.encodeJpg(imgOut));
//   //     debugPrint("📸 Saved Debug Crop: $path");
//   //   } catch (e) {
//   //     debugPrint("Lỗi save debug: $e");
//   //   }
//   // }

//   // ---------------------------------------------------------------
//   //  Init
//   // ---------------------------------------------------------------

//   @override
//   void initState() {
//     super.initState();
//     // Khởi tạo ML Kit
//     _faceDetector = FaceDetector(
//       options: FaceDetectorOptions(
//         performanceMode: FaceDetectorMode.accurate,
//         enableLandmarks: true,
//         enableContours: false,
//       ),
//     );
//     // Khởi tạo AI Service (Load model TFLite)
//     _aiService.initialize();
//   }

//   // --- HÀM CHÍNH: XỬ LÝ VÀ XUẤT JSON ---
//   Future<void> _startSeeding() async {
//     setState(() {
//       _isProcessing = true;
//       _status = "Đang giải nén & Xử lý...";
//     });

//     _debugImageCounter.clear();
//     tempMapEmbeddings.clear();

//     // Bắt đầu bấm giờ
//     Stopwatch stopwatch = Stopwatch()..start();
//     int totalImagesProcessed = 0;

//     try {
//       final extDir = await getExternalStorageDirectory();
//       final debugDir = Directory('${extDir!.path}/debug_seeder');
//       if (await debugDir.exists()) {
//         await debugDir.delete(recursive: true);
//       }
//     } catch (_) {}

//     try {
//       // 1. Đọc file Zip từ Assets
//       final byteData = await rootBundle.load('assets/dataset.zip');
//       final buffer = byteData.buffer.asUint8List();

//       // 2. Giải nén
//       final archive = ZipDecoder().decodeBytes(buffer);

//       debugPrint("📦 Đã tìm thấy ${archive.length} file trong Zip.");

//       // 3. Duyệt từng file trong file Zip
//       for (final file in archive) {
//         if (file.isFile) {
//           final filename = file.name; // Ví dụ: dataset/xuantung/anh1.jpg

//           // Lọc chỉ lấy ảnh
//           if (!filename.toLowerCase().endsWith('.jpg') &&
//               !filename.toLowerCase().endsWith('.png') &&
//               !filename.toLowerCase().endsWith('.jpeg')) {
//             continue;
//           }

//           totalImagesProcessed++;

//           // Phân tích tên User từ đường dẫn trong Zip
//           // dataset/xuantung/anh1.jpg -> parts[-2] là xuantung
//           List<String> parts = filename.split('/');
//           if (parts.length < 2) continue;

//           // Nếu cấu trúc là dataset/xuantung/anh.jpg thì lấy parts[parts.length - 2]
//           // Nếu zip trực tiếp xuantung/anh.jpg thì lấy parts[0]
//           // Logic an toàn: Lấy tên thư mục chứa file
//           String name = parts[parts.length - 2];

//           debugPrint("⚡ Đang xử lý: $name - ${filename.split('/').last}");

//           // A. Ghi file ra bộ nhớ tạm (Cache) để ML Kit đọc
//           final tempDir = await getTemporaryDirectory();
//           final tempFile = File('${tempDir.path}/temp_img');
//           await tempFile.writeAsBytes(file.content as List<int>);

//           // B. Xử lý ảnh
//           await _processImageFile(tempFile, name);

//           // Xóa file tạm
//           if (await tempFile.exists()) await tempFile.delete();

//           final files = archive.files;
//           final index = files.indexOf(file);

//           setState(() {
//             _status = "Đang xử lý: $name (${index + 1}/${files.length})";
//           });
//         }
//       }

//       Map<String, List<double>> finalJsonData = {};
//       tempMapEmbeddings.forEach((user, embeddingsList) {
//         if (embeddingsList.isNotEmpty) {
//           finalJsonData[user] = _calculateMean(embeddingsList);
//         }
//       });

//       debugPrint("✅ Đã xử lý xong ${finalJsonData.length} người dùng!");

//       // --- SAU KHI XỬ LÝ XONG TẤT CẢ ẢNH ---
//       stopwatch.stop();

//       // 1. Lấy thông số chất lượng (Hàm vừa sửa ở trên)
//       var qualityStats = _validateDataQuality();

//       // 2. Lấy thông số hiệu năng
//       int totalTimeMs = stopwatch.elapsedMilliseconds;
//       double avgTimePerImage = totalImagesProcessed > 0
//           ? totalTimeMs / totalImagesProcessed
//           : 0.0;

//       // 3. Lấy thông tin Model (Size, Tên)
//       String modelName = ToolAIService.modelPath.split('/').last;
//       double modelSizeMB = 0.0;
//       try {
//         final byteData = await rootBundle.load(ToolAIService.modelPath);
//         modelSizeMB = byteData.lengthInBytes / (1024 * 1024);
//       } catch (e) {
//         debugPrint("Không lấy được size model: $e");
//       }

//       // 4. TẠO JSON BÁO CÁO (Cái bạn cần đây)
//       Map<String, dynamic> reportData = {
//         "model_info": {
//           "name": modelName,
//           "input_height": ToolAIService.inputHeight,
//           "input_width": ToolAIService.inputWidth,
//           "channels": ToolAIService.channels,
//           "output_dim": _aiService.outputSize,
//           "file_size_mb": double.parse(modelSizeMB.toStringAsFixed(2)),
//         },
//         "performance": {
//           "total_images": totalImagesProcessed,
//           "total_time_ms": totalTimeMs,
//           "avg_ms_per_image": double.parse(avgTimePerImage.toStringAsFixed(1)),
//         },
//         "quality_metrics": {
//           "avg_intra_sim": double.parse(
//             (qualityStats['intra_sim'] ?? 0.0).toStringAsFixed(4),
//           ),
//           "avg_inter_sim": double.parse(
//             (qualityStats['inter_sim'] ?? 0.0).toStringAsFixed(4),
//           ),
//           "quality_margin": double.parse(
//             (qualityStats['quality_score'] ?? 0.0).toStringAsFixed(4),
//           ),
//         },
//         // Kèm luôn dữ liệu vector để backup
//         // "database": finalJsonData
//       };

//       String reportJson = jsonEncode(reportData);
//       String safeModelName = modelName.replaceAll('.', '_');

//       // 5. Gửi File Báo Cáo
//       String reportFileName = "report_$safeModelName.json";
//       await _sendToServer(reportJson, filename: reportFileName);

//       // 6. Gửi File Database (Vector)
//       String dbJsonString = json.encode(finalJsonData);
//       String dbFileName = "db_$safeModelName.json";
//       await _sendToServer(dbJsonString, filename: dbFileName);
//     } catch (e) {
//       debugPrint("❌ Lỗi: $e");
//     } finally {
//       setState(() {
//         _isProcessing = false;
//       });
//     }
//   }

//   Future<void> _processImageFile(File tempFile, String name) async {
//     String? smallPath;

//     // bool isDebugMode = true;

//     const double minFacePercent = 0.1;

//     try {
//       // 1. Nén ảnh trước khi detect để tăng tốc (Giữ nguyên logic của bạn)
//       final Uint8List? compressedBytes =
//           await FlutterImageCompress.compressWithFile(
//             tempFile.path,
//             minWidth: 1280, // Giới hạn kích thước vừa phải
//             minHeight: 1280,
//             quality: 90,
//             format: CompressFormat.jpeg,
//           );

//       if (compressedBytes == null) return;

//       final tempDir = await getTemporaryDirectory();
//       smallPath =
//           '${tempDir.path}/temp_small_${DateTime.now().microsecondsSinceEpoch}.jpg';
//       final smallFile = File(smallPath);
//       await smallFile.writeAsBytes(compressedBytes);

//       // 2. Detect khuôn mặt
//       final inputImageFile = InputImage.fromFile(smallFile);
//       final faces = await _faceDetector.processImage(inputImageFile);

//       if (faces.isEmpty) return;

//       // Tìm khuôn mặt to nhất (Giữ nguyên logic của bạn)
//       Face mainFace = faces.reduce((curr, next) {
//         final currArea = curr.boundingBox.width * curr.boundingBox.height;
//         final nextArea = next.boundingBox.width * next.boundingBox.height;
//         return currArea > nextArea ? curr : next;
//       });

//       // if ((mainFace.headEulerAngleY ?? 0).abs() > 20 ||
//       //     (mainFace.headEulerAngleZ ?? 0).abs() > 20) {
//       //   debugPrint("⚠️ Bỏ qua $name: Mặt nghiêng quá mức.");
//       //   return;
//       // }

//       // 3. Xử lý ảnh bằng Dart Image (Thay cho OpenCV)
//       // Load ảnh vào RAM
//       img.Image? srcImage = await img.decodeImageFile(smallFile.path);

//       if (srcImage != null) {
//         // Tính toán chiều rộng mặt / chiều rộng ảnh
//         double faceWidth = mainFace.boundingBox.width;
//         double imageWidth = srcImage.width.toDouble();

//         // Nếu mặt nhỏ hơn 10% chiều rộng ảnh (hoặc bạn có thể set cứng > 80px)
//         if (faceWidth < (imageWidth * minFacePercent)) {
//           debugPrint(
//             "⚠️ Bỏ qua $name: Mặt quá nhỏ (${faceWidth.toInt()}px / ${imageWidth.toInt()}px)",
//           );
//           return;
//         }

//         // GỌI HÀM CẮT & CHUẨN HÓA MỚI (FaceAlignerDart)
//         // Hàm này trả về List<double> đã chuẩn hóa [-1, 1]
//         List<double>? facePixels = FaceProcessorNative.processFile(
//           smallFile.path,
//           mainFace,
//         );

//         // --- LOGIC GOM NHÓM EMBEDDING ---
//         if (facePixels != null) {
//           // if (isDebugMode) {
//           //   // Convert ngược pixels -> Image để lưu xem đúng mặt không
//           //   // (Chỉ chạy khi dev, tắt khi release)
//           //   _saveDebugCrop(facePixels, name);
//           // }

//           // 4. Generate Embedding từ Pixels
//           List<double> emb = await _aiService.generateEmbedding(facePixels);

//           // Lưu vào map tạm
//           if (!tempMapEmbeddings.containsKey(name)) {
//             tempMapEmbeddings[name] = [];
//           }
//           tempMapEmbeddings[name]!.add(emb);
//         }
//       }
//     } catch (e) {
//       debugPrint("⚠️ Lỗi xử lý ảnh batch: $e");
//     } finally {
//       // Dọn dẹp file tạm
//       if (smallPath != null) {
//         try {
//           await File(smallPath).delete();
//         } catch (_) {}
//       }
//       // Nghỉ tay cho Garbage Collector làm việc
//       await Future.delayed(const Duration(milliseconds: 50));
//     }
//   }

//   Map<String, double> _validateDataQuality() {
//     debugPrint("\n--- 🕵️ BẮT ĐẦU KIỂM TRA CHẤT LƯỢNG DỮ LIỆU ---");

//     double totalIntraSim = 0;
//     int intraCount = 0;

//     // 1. KIỂM TRA ĐỘ ỔN ĐỊNH (Cùng 1 người, các ảnh có giống nhau không?)
//     tempMapEmbeddings.forEach((name, embeddings) {
//       if (embeddings.length < 2) {
//         debugPrint("⚠️ $name: Chỉ có 1 ảnh -> Không thể kiểm tra độ ổn định.");
//         return;
//       }

//       double currentPersonSim = 0;
//       int count = 0;

//       // So sánh từng cặp ảnh của cùng 1 người
//       for (int i = 0; i < embeddings.length - 1; i++) {
//         for (int j = i + 1; j < embeddings.length; j++) {
//           double sim = _cosineSimilarity(embeddings[i], embeddings[j]);
//           currentPersonSim += sim;
//           count++;
//         }
//       }

//       double avgSim = currentPersonSim / count;
//       totalIntraSim += avgSim;
//       intraCount++;

//       // ĐÁNH GIÁ (Thang điểm Cosine):
//       // > 0.8: Tuyệt vời (Rất giống nhau)
//       // 0.6 - 0.8: Ổn
//       // < 0.6: Cảnh báo (Ảnh cùng 1 người mà nhìn khác nhau quá)
//       String quality = avgSim > 0.8
//           ? "✅ Tốt"
//           : (avgSim > 0.6 ? "⚠️ Tạm" : "❌ KHÔNG ỔN ĐỊNH");
//       debugPrint(
//         "👤 $name ($count cặp ảnh): Trung bình sai số = ${avgSim.toStringAsFixed(3)} -> $quality",
//       );
//     });

//     double avgIntra = intraCount > 0 ? totalIntraSim / intraCount : 0.0;

//     if (intraCount > 0) {
//       debugPrint(
//         "=> Sai số nội bộ trung bình toàn data: ${avgIntra.toStringAsFixed(3)}",
//       );
//     }

//     // 2. KIỂM TRA ĐỘ PHÂN BIỆT (Người A có khác người B không?)
//     debugPrint("\n--- ⚔️ KIỂM TRA PHÂN BIỆT GIỮA CÁC NGƯỜI DÙNG ---");
//     List<String> names = tempMapEmbeddings.keys.toList();

//     // Tính vector trung bình tạm thời để so sánh
//     Map<String, List<double>> means = {};
//     tempMapEmbeddings.forEach((k, v) => means[k] = _calculateMean(v));

//     double totalInterSim = 0;
//     int interCount = 0;

//     for (int i = 0; i < names.length - 1; i++) {
//       for (int j = i + 1; j < names.length; j++) {
//         String u1 = names[i];
//         String u2 = names[j];
//         double sim = _cosineSimilarity(means[u1]!, means[u2]!);

//         totalInterSim += sim;
//         interCount++;

//         String statusIcon;
//         String note = "";

//         // ĐÁNH GIÁ (Thang điểm Cosine):
//         // > 0.6: NGUY HIỂM (Hai người lạ mà giống nhau > 60%)
//         // 0.4 - 0.6: Hơi giống
//         // < 0.4: Tốt (Khác biệt rõ ràng)
//         if (sim > 0.6) {
//           statusIcon = "❌ NGUY HIỂM";
//           note = "(Dễ nhận nhầm)";
//         } else if (sim > 0.4) {
//           statusIcon = "⚠️ Hơi giống";
//           note = "(Cẩn thận)";
//         } else {
//           statusIcon = "✅ Tốt";
//         }

//         // IN RA TẤT CẢ CÁC CẶP (Theo yêu cầu của bạn)
//         debugPrint(
//           "$statusIcon $u1 vs $u2: Sim = ${sim.toStringAsFixed(3)} $note",
//         );
//       }
//     }

//     double avgInter = interCount > 0 ? totalInterSim / interCount : 0.0;

//     // --- PHẦN BỔ SUNG ĐỂ HẾT LỖI VÀ BÁO CÁO TỔNG QUAN ---
//     if (interCount > 0) {
//       debugPrint("--------------------------------------------------");
//       debugPrint(
//         "=> Khoảng cách tách biệt trung bình: ${avgInter.toStringAsFixed(3)}",
//       );

//       // Margin = (Giống nội bộ) - (Giống chéo). Càng lớn càng tốt.
//       double margin = avgIntra - avgInter;

//       if (margin > 0.4) {
//         debugPrint(
//           "🌟 TỔNG KẾT: Model phân biệt RẤT TỐT! (Margin: ${margin.toStringAsFixed(2)})",
//         );
//       } else if (margin > 0.2) {
//         debugPrint("✅ TỔNG KẾT: Model hoạt động ỔN.");
//       } else {
//         debugPrint("⚠️ TỔNG KẾT: Cảnh báo, dữ liệu khó phân biệt.");
//       }
//     }
//     debugPrint("--------------------------------------------------\n");

//     return {
//       "intra_sim": avgIntra,
//       "inter_sim": avgInter,
//       "quality_score": avgIntra - avgInter, // Điểm chất lượng
//     };
//   }

//   // --- HÀM TÍNH COSINE SIMILARITY (Thay thế Euclidean) ---
//   // Công thức: A . B (Vì vector đã được normalize độ dài = 1)
//   double _cosineSimilarity(List<double> v1, List<double> v2) {
//     double dot = 0.0;
//     for (int i = 0; i < v1.length; i++) {
//       dot += v1[i] * v2[i];
//     }
//     return dot;
//   }

//   // Hàm gửi JSON về Server Dart trên PC
//   Future<void> _sendToServer(
//     String jsonString, {
//     String filename = "face_db.json",
//   }) async {
//     debugPrint("📡 Đang gửi dữ liệu về máy tính...");

//     // Khởi tạo Dio
//     final dio = Dio();
//     try {
//       // SỬA IP TẠI ĐÂY (Dùng ipconfig trên PC để xem)
//       String serverUrl = "http://192.168.1.105:5000/upload-json";

//       var response = await dio.post(
//         serverUrl,
//         // Dio tự động chuyển Map này thành JSON
//         data: {"filename": filename, "content": jsonString},
//         // Cấu hình Header
//         options: Options(
//           headers: {"Content-Type": "application/json"},
//           sendTimeout: const Duration(seconds: 10), // Timeout sau 10s
//         ),
//       );

//       if (response.statusCode == 200) {
//         debugPrint("🎉 THÀNH CÔNG! File json đã nằm trong assets máy tính.");
//       } else {
//         debugPrint("⚠️ Server lỗi: ${response.statusCode}");
//       }
//     } catch (e) {
//       debugPrint("❌ Không kết nối được: $e");
//       debugPrint(
//         "👉 Kiểm tra lại IP máy tính và đảm bảo Server Dart đang chạy.",
//       );
//     }
//   }

//   // Hàm phụ: Tính trung bình
//   List<double> _calculateMean(List<List<double>> embeddings) {
//     int dim = embeddings[0].length;
//     List<double> mean = List.filled(dim, 0.0);
//     for (var emb in embeddings) {
//       for (int i = 0; i < dim; i++) {
//         mean[i] += emb[i];
//       }
//     }
//     for (int i = 0; i < dim; i++) {
//       mean[i] /= embeddings.length;
//     }
//     return mean;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Công cụ tạo dữ liệu FaceDB")),
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             if (_isProcessing) const CircularProgressIndicator(),
//             const SizedBox(height: 20),
//             Text(
//               _status,
//               textAlign: TextAlign.center,
//               style: const TextStyle(fontSize: 16),
//             ),
//             const SizedBox(height: 40),
//             ElevatedButton.icon(
//               onPressed: _isProcessing ? null : _startSeeding,
//               icon: const Icon(Icons.engineering),
//               label: const Text("Bắt đầu xử lý & Xuất JSON"),
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.all(20),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
