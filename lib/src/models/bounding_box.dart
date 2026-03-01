/// Bounding rectangle for a detected pose.
///
/// All values are normalized to [0.0, 1.0] relative to the image dimensions.
///
/// ## Example
///
/// ```dart
/// if (pose.boundingBox != null) {
///   final box = pose.boundingBox!;
///
///   // Convert to pixel coordinates
///   final rect = Rect.fromLTWH(
///     box.left * imageWidth,
///     box.top * imageHeight,
///     box.width * imageWidth,
///     box.height * imageHeight,
///   );
///
///   canvas.drawRect(rect, paint);
/// }
/// ```
class BoundingBox {
  /// Left edge position (normalized 0-1).
  final double left;

  /// Top edge position (normalized 0-1).
  final double top;

  /// Width (normalized 0-1).
  final double width;

  /// Height (normalized 0-1).
  final double height;

  /// Creates a new [BoundingBox].
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Right edge position (normalized 0-1).
  double get right => left + width;

  /// Bottom edge position (normalized 0-1).
  double get bottom => top + height;

  /// Center X position (normalized 0-1).
  double get centerX => left + width / 2;

  /// Center Y position (normalized 0-1).
  double get centerY => top + height / 2;

  /// Area of the bounding box (normalized).
  double get area => width * height;

  /// Create a [BoundingBox] from a JSON map.
  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  /// Convert this bounding box to a JSON map.
  Map<String, dynamic> toJson() {
    return {'left': left, 'top': top, 'width': width, 'height': height};
  }

  @override
  String toString() {
    return 'BoundingBox(left: ${left.toStringAsFixed(3)}, '
        'top: ${top.toStringAsFixed(3)}, '
        'width: ${width.toStringAsFixed(3)}, '
        'height: ${height.toStringAsFixed(3)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoundingBox &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);
}
