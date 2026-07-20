/// Cross-platform gallery image pick (bytes + filename).
library;

export 'gallery_image_picker_stub.dart'
    if (dart.library.js_interop) 'gallery_image_picker_web.dart';
