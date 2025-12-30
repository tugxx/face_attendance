# face_attendance

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Structure

lib/
├── app/
│   ├── bindings/           # (Optional) Các binding khởi tạo toàn cục (nếu cần)
│   ├── core/               # Chứa các thứ dùng chung cho toàn app
│   │   ├── theme/          # Màu sắc, font chữ
│   │   ├── utils/          # Các hàm tiện ích (CameraUtils, MathUtils...)
│   │   └── values/         # String, assets path
│   ├── data/               # Layer xử lý dữ liệu (Clean Architecture)
│   │   ├── models/         # Các class Model (User, AttendanceLog...)
│   │   ├── providers/      # API Services (Dio, HTTP client)
│   │   └── repositories/   # Cầu nối giữa API và Controller
│   ├── modules/            # PHẦN QUAN TRỌNG NHẤT: Chia theo tính năng
│   │   └── face_attendance/# Tính năng điểm danh
│   │       ├── bindings/   # DI: Nơi bơm Controller vào View
│   │       │   └── face_attendance_binding.dart
│   │       ├── controllers/# Logic nghiệp vụ
│   │       │   └── face_attendance_controller.dart
│   │       ├── views/      # Giao diện
│   │       │   └── face_attendance_view.dart
│   │       └── widgets/    # Các widget nhỏ chỉ dùng cho màn hình này
│   │           └── face_detector_painter.dart
│   └── routes/             # Quản lý luồng đi (Navigation)
│       ├── app_pages.dart  # Bản đồ dẫn đường (Map URL với View + Binding)
│       └── app_routes.dart # Định nghĩa tên đường dẫn (String constant)
└── main.dart               # Entry point sạch sẽ