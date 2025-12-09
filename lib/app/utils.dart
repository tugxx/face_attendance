import 'dart:math';

// Hàm tính độ tương đồng (Cosine Similarity)
// Trả về giá trị từ -1.0 đến 1.0 (Càng gần 1.0 là càng giống)
double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
  if (vectorA.length != vectorB.length) return 0.0;

  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < vectorA.length; i++) {
    dotProduct += vectorA[i] * vectorB[i];
    normA += vectorA[i] * vectorA[i];
    normB += vectorB[i] * vectorB[i];
  }

  if (normA == 0 || normB == 0) return 0.0;
  
  return dotProduct / (sqrt(normA) * sqrt(normB));
}