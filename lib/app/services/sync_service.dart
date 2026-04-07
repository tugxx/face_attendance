import 'dart:io';
import 'dart:async';
import 'package:uuid/uuid.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http_parser/http_parser.dart';

import '../../app/services/log_service.dart';
import '../../app/network/api_service.dart';
import '../../app/services/web_socket_service.dart';
import '../../app/services/device_service.dart';
import '../../app/services/native_ai_service.dart';
import '../../app/utils/api_constants.dart';

class SyncService {
  // --- SINGLETON ---
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;

  bool _isSyncing = false; // Khóa luồng để không bị chạy đè nhiều vòng lặp
  bool _isPulling = false; // Khóa chống gọi đè

  Future<bool> _uploadBulkData(List<Map<String, dynamic>> records) async {
    try {
      String deviceId = DeviceService().deviceId;

      List<Map<String, dynamic>> logsPayload = records.map((record) {
        return {
          "id": record['id'],
          "student_id": record['student_id'],
          "timestamp": record['timestamp'],
          "method": "face",
          "confidence": record['confidence'],
          "liveness_score": record['liveness_score'],
          "is_offline_log": true,
        };
      }).toList();

      Map<String, dynamic> finalPayload = {
        "device_id": deviceId,
        "logs": logsPayload,
      };

      // 2. Bắn API
      final response = await ApiService().dio.post(
        ApiConstants.syncPushAttendanceBulk, // Đường dẫn API mới
        data: finalPayload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLog.info("☁️ Bắn Bulk JSON thành công: ${response.data}");
        return true;
      }
      return false;
    } catch (e) {
      if (e is DioException && e.response != null) {
        // DÒNG NÀY SẼ IN RA CHÍNH XÁC LỖI TỪ SERVER (VD: "student_id is required")
        AppLog.error("🔴 Lỗi 400 Chi tiết từ Django: ${e.response?.data}");
      } else {
        AppLog.error("🔴 Lỗi khi bắn Bulk JSON: $e");
      }
      return false;
    }
  }

  /// [BƯỚC 2] - Gửi từng ảnh một, gửi xong xóa file dọn rác
  Future<bool> _uploadSingleImage(Map<String, dynamic> record) async {
    final imagePath = record['image_path'];
    final logId = record['id'];
    final hiveKey = record['hive_key'];

    // Nếu lúc quẹt mặt không có ảnh (lỗi camera), thì bỏ qua upload ảnh và xóa log luôn
    if (imagePath == null || !File(imagePath).existsSync()) {
      await _deleteLocalRecord(hiveKey, imagePath);
      return true;
    }

    // Nếu có ảnh, tạo Multipart để ném lên
    try {
      final formData = FormData.fromMap({
        "evidence_image": await MultipartFile.fromFile(
          imagePath,
          filename: imagePath.split('/').last,
          contentType: MediaType('image', 'jpeg'),
        ),
      });

      // AppLog.info("Headers đang gửi: ${ApiService().dio.options.headers}");
      const storage = FlutterSecureStorage();
      final accessToken = await storage.read(key: 'access_token');
      // AppLog.info(
      //   "Đang ném ảnh lên với Token: ${accessToken?.substring(0, 10)}...",
      // );

      final response = await ApiService().dio.post(
        ApiConstants.syncPushAttendanceImage(
          logId,
        ), // Đường dẫn API Ảnh có truyền UUID
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          contentType:
              Headers.multipartFormDataContentType, // Ép Dio gửi Header chuẩn
          responseType: ResponseType.json,
        ),
      );

      // Nếu Django trả về 200 OK -> Ảnh đã nằm gọn trong ổ cứng Server
      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLog.info("📸 Đã upload xong ảnh cho Log: $logId");
        await _deleteLocalRecord(hiveKey, imagePath);
        return true;
      }
      return true;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404 || e.response?.statusCode == 400) {
          AppLog.warning(
            "🗑️ Server từ chối Log này (${e.response?.statusCode}). Xóa bỏ dữ liệu local!",
          );
          await _deleteLocalRecord(hiveKey, imagePath);
          return true;
        } else {
          // Các lỗi 500, 502, 504 hoặc rớt mạng (e.response == null) -> KHÔNG ĐƯỢC XÓA
          // Để nguyên trong Hive, lát nữa có mạng gửi lại!
          AppLog.error(
            "🔴 Lỗi Mạng/Server [${e.response?.statusCode ?? 'Timeout'}]. Sẽ thử lại sau.",
          );
          return false;
        }
      } else {
        AppLog.error("🔴 Lỗi Không xác định: $e");
        return false;
      }
    }
  }

  /// Hàm phụ trợ: Xóa sạch dấu vết offline sau khi hoàn thành nhiệm vụ
  Future<void> _deleteLocalRecord(dynamic hiveKey, String? imagePath) async {
    if (imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) await file.delete();
    }
    await Hive.box('AttendanceBox').delete(hiveKey);
  }

  void init() {
    AppLog.info("⚙️ Khởi động hệ thống Đồng bộ ngầm (SyncService)...");

    pullUsersFromServer();

    // 1. Cắm tai nghe lắng nghe mạng (Zalo Style)
    _networkSubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (!results.contains(ConnectivityResult.none)) {
        AppLog.info(
          "🌐 [MẠNG]: Đã có kết nối Internet! Kích hoạt vét máng Hive...",
        );
        syncPendingRecords();

        // Tiện tay nối lại luôn cái WebSocket nếu nó đang đứt
        WebSocketService().connect();
      }
    });
  }

  /// Hàm phụ 1: Chỉ xử lý TEXT (Bulk Upload)
  Future<void> syncPendingTextLogs(Box box) async {
    final keys = box.keys.toList();
    List<Map<String, dynamic>> pendingTextRecords = [];

    for (var key in keys) {
      final record = box.get(key);
      if (record != null && record['sync_status'] == 'PENDING') {
        var recordData = Map<String, dynamic>.from(record);
        recordData['hive_key'] = key;
        pendingTextRecords.add(recordData);
      }
    }

    if (pendingTextRecords.isEmpty) return;

    AppLog.info("🔄 Bắt đầu ĐẨY TEXT. Số lượng: ${pendingTextRecords.length}");

    // Bắn Bulk lên Django
    bool textSyncSuccess = await _uploadBulkData(pendingTextRecords);

    // Nếu Text lên thành công, đổi trạng thái TẤT CẢ các bản ghi này sang chờ tải Ảnh
    if (textSyncSuccess) {
      for (var record in pendingTextRecords) {
        final hiveKey = record['hive_key'];

        if (record['image_path'] != null) {
          // Có ảnh -> Chuyển trạng thái để hàm quét ảnh lo
          record['sync_status'] = 'IMAGE_PENDING';
          await box.put(hiveKey, record);
        } else {
          // Không có ảnh -> Xong nhiệm vụ, xóa sổ luôn
          await box.delete(hiveKey);
        }
      }
    }
  }

  /// Hàm phụ 2: Chỉ xử lý ẢNH (Xử lý IMAGE_PENDING)
  /// WebSocket gọi TRỰC TIẾP hàm này khi nó nhận được báo cáo "Text đã lên"
  Future<void> syncPendingImages([Box? box]) async {
    final currentBox = box ?? Hive.box('AttendanceBox');
    final keys = currentBox.keys.toList();

    for (var key in keys) {
      final record = currentBox.get(key);
      if (record != null && record['sync_status'] == 'IMAGE_PENDING') {
        var recordData = Map<String, dynamic>.from(record);
        recordData['hive_key'] = key;

        // Bắn từng ảnh một
        bool shouldContinue = await _uploadSingleImage(recordData);

        if (!shouldContinue) {
          AppLog.warning(
            "⚠️ Đứt kết nối khi đang đẩy ảnh! Dập cầu dao, ngừng sync các ảnh còn lại.",
          );
          break; // Đập vỡ vòng lặp, chờ lần sau có mạng chạy tiếp
        }
      }
    }
  }

  /// Hàm kích hoạt quá trình đồng bộ
  Future<void> syncPendingRecords() async {
    // Nếu đang đồng bộ dở thì bỏ qua, đợi lượt sau
    if (_isSyncing) return;

    final box = Hive.box('AttendanceBox');
    if (box.isEmpty) return; // Két rỗng thì thôi

    _isSyncing = true;
    try {
      // 1. DỌN BÀN SẠCH TEXT TRƯỚC (Quét PENDING)
      await syncPendingTextLogs(box);

      // 2. TEXT SẠCH RỒI THÌ CHUYỂN QUA ĐẨY ẢNH (Quét IMAGE_PENDING)
      await syncPendingImages(box);
    } finally {
      _isSyncing = false;
      AppLog.info("✅ Hoàn tất lượt đồng bộ.");
    }
  }

  /// Kéo danh sách học sinh (Khuôn mặt) từ Server về máy
  Future<void> pullUsersFromServer() async {
    if (_isPulling) return;
    _isPulling = true;
    AppLog.info("⬇️ Bắt đầu tiến trình KÉO dữ liệu từ Server...");

    try {
      final settingsBox = Hive.box('SettingsBox');
      final faceBox = Hive.box('face_db');

      // 1. Lấy Điểm Neo Thời Gian (Checkpoint)
      // Nếu là lần cài app đầu tiên, cái này sẽ là null -> Server sẽ trả về Toàn bộ DB
      String? lastSync = settingsBox.get('last_sync_time');

      int currentPage = 1;
      bool hasNextPage = true;
      String? newServerTime;
      int totalUpdated = 0;

      // 2. VÒNG LẶP PHÂN TRANG (PAGINATION)
      while (hasNextPage) {
        final response = await ApiService().dio.get(
          ApiConstants.syncPullUsers, // Đường dẫn API mà ta vừa chốt
          queryParameters: {
            if (lastSync != null) 'last_sync': lastSync,
            'page': currentPage,
            'page_size': 500, // Chia nhỏ mỗi lần tải 500 người
          },
        );

        if (response.statusCode == 200) {
          final data = response.data;

          // Tùy theo PaginationMixin của bạn cấu trúc thế nào, thường sẽ có field 'items'
          final items = data['items'] as List;
          newServerTime = data['server_time']; // Lấy mốc thời gian của Server

          if (items.isEmpty) break; // Nếu trang rỗng thì thoát vòng lặp

          // 3. XỬ LÝ DỮ LIỆU TỪNG NGƯỜI VÀO HIVE
          for (var user in items) {
            // Giả sử DTO của bạn trả về id, full_name, face_vector, is_active
            final studentId = user['id']
                .toString(); // Hoặc user['student_code']
            final isActive = user['is_active'] ?? true;

            if (!isActive) {
              // Học sinh nghỉ học -> Xóa khỏi máy chấm công
              await faceBox.delete(studentId);
              NativeAiService().removeFaceFromNative(studentId);
              totalUpdated++;
            } else {
              // Học sinh mới hoặc cập nhật mặt
              final faceVectorRaw = user['face_vector'];

              final String templateId =
                  user['template_id']?.toString() ?? const Uuid().v4();

              if (faceVectorRaw != null) {
                // Đảm bảo ép kiểu an toàn từ JSON Array (dynamic) sang List<double>
                List<double> vector = (faceVectorRaw as List)
                    .map((e) => double.parse(e.toString()))
                    .toList();

                if (vector.length == 192) {
                  await faceBox.put(studentId, {
                    'name': user['full_name'] ?? 'Unknown',
                    'template_id': templateId,
                    'vector': vector,
                  });

                  NativeAiService().addFaceToNative(
                    studentId,
                    vector,
                    templateId,
                  ); // 3. Cập nhật RAM C++ (Ghi đè hoặc Thêm mới)
                  totalUpdated++;
                }
              }
            }
          }

          // Kiểm tra xem còn trang tiếp theo không (dựa vào tổng số trang hoặc số item trả về)
          final totalPages = data['total_pages'] ?? 1;
          if (currentPage >= totalPages) {
            hasNextPage = false;
          } else {
            currentPage++;
          }
        } else {
          throw Exception("Lỗi API tải danh sách: ${response.statusCode}");
        }
      }

      if (totalUpdated > 0) {
        AppLog.info(
          "⚡ Đã live-update thành công $totalUpdated khuôn mặt vào RAM C++!",
        );
      }

      // 4. LƯU LẠI CHỐT THỜI GIAN (CHECKPOINT)
      if (newServerTime != null) {
        await settingsBox.put('last_sync_time', newServerTime);
        AppLog.info("✅ Đã kéo xong! Cập nhật last_sync: $newServerTime");
      }
    } catch (e) {
      AppLog.error("🔴 Lỗi khi Pull Users: $e");
    } finally {
      _isPulling = false;
    }
  }

  void dispose() {
    _networkSubscription?.cancel();
    AppLog.info("🛑 Đã tắt hệ thống Đồng bộ ngầm.");
  }
}
