import 'dart:io';
import 'dart:convert'; // Nhớ import cái này

void main() async {
  final port = 5000;
  // Để chắc ăn, hãy in đường dẫn thư mục hiện tại ra ngay lúc đầu
  stdout.writeln("📂 Thư mục làm việc hiện tại: ${Directory.current.path}");

  final directory = Directory('assets');
  if (!await directory.exists()) {
    await directory.create();
  }

  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    stdout.writeln('🚀 Server đang chạy tại: http://0.0.0.0:$port');

    await for (HttpRequest request in server) {
      if (request.method == 'POST') {
        stdout.writeln('📥 Đang nhận dữ liệu...');

        // 1. Đọc toàn bộ body request thành chuỗi String
        String content = await utf8.decoder.bind(request).join();
        
        try {
          // 2. Parse JSON để bóc tách dữ liệu
          var data = jsonDecode(content);
          
          // Lấy tên file từ client gửi (hoặc dùng mặc định)
          String filename = data['filename'] ?? 'face_db.json';
          // Lấy nội dung cốt lõi
          String fileContent = data['content']; 

          // 3. Ghi nội dung sạch xuống file
          final file = File('assets/$filename');
          await file.writeAsString(fileContent);

          stdout.writeln('✅ Đã lưu file sạch tại: ${file.absolute.path}');
          
          request.response
            ..statusCode = HttpStatus.ok
            ..write('Saved');
        } catch (e) {
          stdout.writeln('❌ Lỗi parse JSON: $e');
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('Invalid JSON format');
        }
        
        await request.response.close();
      } else {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..write('Only POST is allowed');
        await request.response.close();
      }
    }
  } catch (e) {
    stdout.writeln('❌ Lỗi Server: $e');
  }
}