import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/modules/camera_attendance/views/camera_view.dart';

void main() async {
  // Đảm bảo Flutter Binding được khởi tạo trước khi làm gì khác
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    GetMaterialApp(
      title: 'Face Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Chạy thẳng vào màn hình Camera luôn để test
      home: const CameraAttendanceView(),
    ),
  );
}