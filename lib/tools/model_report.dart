class ModelReport {
  final String modelName;
  final String inputType; // Float32 hay Int8
  final double modelSizeMB; // Dung lượng file
  final int outputDim; // 512 hay 128...
  final double avgIntraDist; // Sai số nội bộ (Càng nhỏ càng tốt)
  final double avgInterDist; // Độ tách biệt (Càng lớn càng tốt)
  final double accuracyScore; // Điểm số tự tính (Inter / Intra)
  final int processingTimeMs; // Thời gian xử lý trung bình mỗi ảnh

  ModelReport({
    required this.modelName,
    required this.inputType,
    required this.modelSizeMB,
    required this.outputDim,
    required this.avgIntraDist,
    required this.avgInterDist,
    required this.accuracyScore,
    required this.processingTimeMs,
  });

  Map<String, dynamic> toJson() => {
    "model": modelName,
    "type": inputType,
    "size_mb": modelSizeMB,
    "dim": outputDim,
    "intra_dist": avgIntraDist,
    "inter_dist": avgInterDist,
    "score": accuracyScore,
    "speed_ms": processingTimeMs,
  };
}
