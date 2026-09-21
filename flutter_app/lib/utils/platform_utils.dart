import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Platform capabilities. Used to hide features that cannot work on a
/// given platform (e.g. QR camera on desktop) and to pick background
/// behavior appropriate to the platform.
class PlatformUtils {
  PlatformUtils._();

  static bool get isWeb => kIsWeb;

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isDesktop =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// QR scanning requires a camera. Web can use `getUserMedia`; mobile
  /// has camera plugins; desktop is unreliable and we hide it.
  static bool get supportsQrScanning => isMobile || isWeb;

  /// QR generation is pure rendering, available everywhere.
  static bool get supportsQrGeneration => true;

  /// Background polling of any kind is not a thing in a serverless app;
  /// this is kept for symmetry and future features.
  static bool get supportsBackgroundWork => isMobile || isDesktop;

  /// Number of concurrent WebRTC peer connections we allow. Mobile
  /// platforms handle this differently; keeping a low ceiling avoids
  /// memory pressure on older devices.
  static int get maxConcurrentPeers => isMobile ? 2 : 8;
}