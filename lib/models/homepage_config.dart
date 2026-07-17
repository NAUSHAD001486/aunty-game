/// Admin-managed offer block for the web landing page.
///
/// Firestore: `game_metadata/homepage_config`
/// Preferred keys: offer_image_url, offer_title, offer_desc
/// Legacy keys still accepted: offer_image, offer_price, …
class HomepageConfig {
  const HomepageConfig({
    this.offerImage = '',
    this.offerTitle = '',
    this.offerDesc = '',
    this.offerPrice = '',
  });

  final String offerImage;
  final String offerTitle;
  final String offerDesc;
  final String offerPrice;

  bool get hasOffer =>
      offerImage.trim().isNotEmpty ||
      offerTitle.trim().isNotEmpty ||
      offerDesc.trim().isNotEmpty ||
      offerPrice.trim().isNotEmpty;

  factory HomepageConfig.fromMap(Map<String, dynamic> data) {
    return HomepageConfig(
      offerImage: _asString(data['offer_image_url']).isNotEmpty
          ? _asString(data['offer_image_url'])
          : _asString(data['offer_image']),
      offerTitle: _asString(data['offer_title']),
      offerDesc: _asString(data['offer_desc']),
      offerPrice: _asString(data['offer_price']),
    );
  }

  static String _asString(Object? value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}
