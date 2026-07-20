import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class GalleryPickedImage {
  const GalleryPickedImage({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

/// Flutter web: native `<input type="file" accept="image/*">` — reliable on
/// mobile browsers (image_picker often fails inside bottom sheets / WebViews).
Future<GalleryPickedImage?> pickGalleryImage() async {
  final completer = Completer<GalleryPickedImage?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..multiple = false;

  // Keep off-screen but in the DOM (some mobile browsers require it).
  input.style
    ..position = 'fixed'
    ..left = '-9999px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';
  web.document.body?.append(input);

  var settled = false;
  void finish(GalleryPickedImage? value) {
    if (settled) return;
    settled = true;
    input.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }
      final file = files.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      final rawName = file.name.trim();
      final name = rawName.isNotEmpty ? rawName : 'winner_claim.jpg';
      final reader = web.FileReader();
      reader.addEventListener(
        'loadend',
        (web.Event _) {
          try {
            final result = reader.result;
            if (result == null) {
              finish(null);
              return;
            }
            final buffer = result as JSArrayBuffer;
            final bytes = buffer.toDart.asUint8List();
            if (bytes.isEmpty) {
              finish(null);
              return;
            }
            finish(GalleryPickedImage(bytes: bytes, fileName: name));
          } catch (e) {
            // ignore: avoid_print
            print('[ClaimUI] web FileReader failed: $e');
            finish(null);
          }
        }.toJS,
      );
      reader.addEventListener(
        'error',
        (web.Event _) {
          finish(null);
        }.toJS,
      );
      reader.readAsArrayBuffer(file);
    }.toJS,
  );

  input.addEventListener(
    'cancel',
    (web.Event _) {
      finish(null);
    }.toJS,
  );

  // Open the system file picker — must stay in the user-gesture stack.
  input.click();

  return completer.future.timeout(
    const Duration(minutes: 3),
    onTimeout: () {
      finish(null);
      return null;
    },
  );
}
