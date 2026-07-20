import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class GalleryPickedImage {
  const GalleryPickedImage({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

/// Native / non-web: use image_picker plugin.
Future<GalleryPickedImage?> pickGalleryImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 85,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;
  final name = file.name.trim();
  return GalleryPickedImage(
    bytes: bytes,
    fileName: name.isNotEmpty ? name : 'winner_claim.jpg',
  );
}
