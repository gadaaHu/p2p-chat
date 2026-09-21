/// Small, stateless validators used by forms and by service-layer
/// input checks. No `BuildContext`, no localization — the UI wraps
/// these into `TextFormField` validators where needed.
class Validators {
  Validators._();

  static final _deviceIdRe = RegExp(r'^[0-9a-f]{16}$');
  static final _hexRe = RegExp(r'^[0-9a-fA-F]+$');
  static final _base64Re = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
  static final _base64UrlRe = RegExp(r'^[A-Za-z0-9_-]+={0,2}$');

  static bool isDeviceId(String s) => _deviceIdRe.hasMatch(s);

  static bool isHex(String s, {int? length}) =>
      _hexRe.hasMatch(s) && (length == null || s.length == length);

  static bool isBase64(String s) {
    if (s.isEmpty || s.length % 4 != 0) return false;
    return _base64Re.hasMatch(s);
  }

  static bool isBase64Url(String s) {
    if (s.isEmpty) return false;
    return _base64UrlRe.hasMatch(s);
  }

  /// Standard "non-empty, bounded" check for text fields. Returns null
  /// when valid so it plugs directly into `TextFormField.validator`.
  static String? bounded(
    String? v, {
    String label = 'Value',
    int min = 1,
    int max = 4096,
  }) {
    if (v == null || v.isEmpty) return '$label is required';
    if (v.length < min) return '$label is too short';
    if (v.length > max) return '$label is too long';
    return null;
  }

  /// Validates a display name. Trims, rejects control characters,
  /// enforces length.
  static String? displayName(String? v) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length > 64) return 'Name is too long';
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
      return 'Name contains invalid characters';
    }
    return null;
  }

  /// Validates a message body. Empty after trim is rejected; extremely
  /// long bodies are rejected with a clear message rather than truncated
  /// silently.
  static String? messageBody(String? v, {int max = 4000}) {
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Message is empty';
    if (trimmed.length > max) return 'Message is too long (max $max)';
    return null;
  }
}