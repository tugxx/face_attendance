class ApiConstants {
  ApiConstants._(); // Private constructor

  // BASE URL TÙY CHỈNH (Đổi 1 chỗ, ăn toàn app)
  // Khi nào dùng tên miền thật thì bạn chỉ cần mở file này ra đổi 1 dòng là xong
  static const String url = 'essence-hollow-mines-predicted.trycloudflare.com';

  static const String baseUrl = 'https://$url/api';

  static const String wsSync = 'wss://$url/ws/sync/';

  // ==========================================
  // NHÓM AUTH (XÁC THỰC)
  // ==========================================
  static const String login = '/account/login';
  static const String register = '/account/register';
  static const String refreshToken = '/token/refresh';

  // ==========================================
  // NHÓM SYNC (ĐỒNG BỘ OFFLINE/ONLINE)
  // ==========================================
  // 1. Kéo data học sinh từ Server về
  static const String syncPullUsers = '/offline_sync/users/pull';

  // 2. Đẩy 1 cục JSON điểm danh lên Server
  static const String syncPushAttendanceBulk =
      '/offline_sync/attendance/push-bulk';

  // 3. Đẩy từng file ảnh lên (Dùng hàm vì có gắn thêm logId động ở cuối)
  static String syncPushAttendanceImage(String logId) =>
      '/offline_sync/attendance/push-image/$logId';

  // ==========================================
  // NHÓM FACE (KHUÔN MẶT)
  // ==========================================
  static const String faceRegister = '/face/register/'; // Ví dụ cho sau này
}
