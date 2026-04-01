abstract class Routes {
  Routes._(); // Private constructor để không ai khởi tạo được class này

  // AUTH
  static const login = '/account/login';
  static const register = '/account/register';

  // MAIN
  static const home = '/';

  // FEATURES
  static const faceAttendance = '/face/attendance';
  static const faceRegister = '/face/register';
}
