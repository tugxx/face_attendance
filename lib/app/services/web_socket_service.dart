import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../app/services/log_service.dart';
import '../../app/network/api_service.dart';
import '../../app/services/sync_service.dart';
import '../../app/utils/api_constants.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;

  bool _isReconnecting = false;

  final String serverUrl = ApiConstants.wsSync;

  final storage = FlutterSecureStorage();

  // Khởi tạo kết nối
  Future<void> connect() async {
    if (_isConnected || _isReconnecting) return;

    // Lấy token từ két sắt (Hive/FlutterSecureStorage)
    final accessToken = await storage.read(key: 'access_token');
    if (accessToken == null) {
      AppLog.error("Không có token, không thể kết nối WebSocket");
      return;
    }

    try {
      // 2. NỐI TOKEN VÀO URL thay vì dùng Header
      final wsUrl = Uri.parse('$serverUrl?token=$accessToken');
      AppLog.info("✅ Đang kết nối WebSocket tới $serverUrl...");

      final ws = await WebSocket.connect(
        wsUrl.toString(),
      ).timeout(const Duration(seconds: 5));

      _channel = IOWebSocketChannel.connect(ws);
      _isConnected = true;

      // Lắng nghe tin nhắn từ Server trả về
      _channel!.stream.listen(
        (message) {
          AppLog.info("📥 Server trả về: $message");
          _handleServerMessage(message);
        },
        onDone: () async {
          _isConnected = false;
          final closeCode = _channel!.closeCode;
          AppLog.warning("⚠️ WebSocket đóng. Mã lỗi: $closeCode");

          // Xử lý đúng cái mã 4001 bạn ném ra từ Django
          if (closeCode == 4001) {
            AppLog.error("🔴 Token hết hạn hoặc sai! Cần refresh token...");

            bool success = await ApiService().refreshToken();
            if (success) {
              AppLog.info("✅ Đã có Token mới, đang nối lại WebSocket...");
              connect(); // Mở lại luồng Socket với token mới
            }
          } else {
            // Rớt mạng bình thường -> Tự động nối lại
            _reconnect();
          }
        },
        onError: (error) {
          _isConnected = false;
          AppLog.error("🔴 Lỗi WebSocket: $error");
          _reconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      AppLog.error("🔴 Không thể kết nối WebSocket: $e");
    }
  }

  // Xử lý khi Server báo "Tao lưu thành công UUID này rồi"
  void _handleServerMessage(String message) async {
    try {
      final data = jsonDecode(message);
      final action = data['action'];

      if (action == 'SYNC_NOW') {
        AppLog.info("🔄 Server yêu cầu đồng bộ data mới: ${data['data']}");
        SyncService().pullUsersFromServer();
      } else if (action == 'CHECKIN_SUCCESS') {
        final successUuid = data['data']['uuid'];
        final box = Hive.box('AttendanceBox');

        // Tìm bản ghi trong két
        final record = box.get(successUuid);
        if (record != null) {
          Map<String, dynamic> updatedRecord = Map<String, dynamic>.from(
            record,
          );

          if (updatedRecord['image_path'] != null) {
            // Cú Trick: Đã xong Text, giờ chuyển trạng thái để đợi gửi Ảnh
            updatedRecord['sync_status'] = 'IMAGE_PENDING';
            await box.put(successUuid, updatedRecord);
            AppLog.info(
              "🧹 Socket đã báo Text thành công. Chuyển UUID $successUuid sang chờ đẩy Ảnh.",
            );

            // Kích hoạt SyncService ngầm để nó gắp cái ảnh bay lên Server luôn
            SyncService().syncPendingImages();
          } else {
            // Không có ảnh (Do thiết lập hoặc lỗi camera) -> Xóa sổ luôn cho nhẹ két
            await box.delete(successUuid);
            AppLog.info(
              "🧹 Đã xóa hoàn toàn UUID $successUuid (Không có ảnh đính kèm).",
            );
          }
        }
      }
    } catch (e) {
      AppLog.error("Lỗi parse tin nhắn từ server: $e");
    }
  }

  // Bắn data điểm danh lên server
  void sendCheckinData(Map<String, dynamic> checkinData) {
    if (_isConnected && _channel != null) {
      final payload = jsonEncode({"action": "checkin", "data": checkinData});
      _channel!.sink.add(payload);
      AppLog.info("🚀 Đã bắn WebSocket: $payload");
    } else {
      final uuid = checkinData['id'];
      AppLog.warning("⚠️ Mất kết nối! Log $uuid sẽ chờ đồng bộ lại sau.");
    }
  }

  void _reconnect() {
    if (_isReconnecting) return; // Đang đếm ngược rồi thì không đếm nữa
    _isReconnecting = true;

    AppLog.info("⏳ Mất kết nối. Sẽ thử kết nối lại sau 5 giây...");

    Future.delayed(const Duration(seconds: 5), () {
      _isReconnecting = false;
      connect();
    });
  }

  void dispose() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
