import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'theme/app_colors.dart';

enum Feature { tts, maleToFemale, femaleToMale, live }

enum Availability { checking, offline, ready, needsSetup, unavailable, phoneVoice }

/// Honest, server-driven availability for each feature. Buttons are enabled
/// only when the backend reports a working provider.
class FeatureStatus {
  const FeatureStatus(this.availability, this.message);

  final Availability availability;
  final String message;

  bool get ready => availability == Availability.ready;

  static FeatureStatus of(AppController app, Feature feature) {
    final server = serverOf(app, feature);
    // Text-to-speech still works offline with the phone's built-in Telugu voice.
    if (feature == Feature.tts && !server.ready && server.availability != Availability.checking) {
      return FeatureStatus(
        Availability.phoneVoice,
        'Server voices are not available yet (${server.message}). '
        "The phone's own Telugu voice works offline.",
      );
    }
    return server;
  }

  /// Availability of the server-side feature only (ignores the phone voice).
  static FeatureStatus serverOf(AppController app, Feature feature) {
    switch (app.connection) {
      case ServerConnection.checking:
        return const FeatureStatus(Availability.checking, 'Checking the server…');
      case ServerConnection.offline:
        return FeatureStatus(
          Availability.offline,
          'Server offline. ${app.lastError ?? ''} Check the server address in Settings.'.trim(),
        );
      case ServerConnection.online:
        break;
    }
    final health = app.health!;
    final cap = switch (feature) {
      Feature.tts => health.tts,
      Feature.maleToFemale || Feature.femaleToMale => health.voiceConversion,
      Feature.live => health.liveConversion,
    };
    if (cap.available) return const FeatureStatus(Availability.ready, 'Ready');
    if (feature == Feature.live) return FeatureStatus(Availability.unavailable, cap.reason);
    return FeatureStatus(Availability.needsSetup, cap.reason);
  }

  String get label => switch (availability) {
        Availability.checking => 'Checking…',
        Availability.offline => 'Offline',
        Availability.ready => 'Ready',
        Availability.needsSetup => 'Needs API setup',
        Availability.unavailable => 'Unavailable',
        Availability.phoneVoice => 'Phone voice',
      };

  IconData get icon => switch (availability) {
        Availability.checking => Icons.hourglass_top_rounded,
        Availability.offline => Icons.cloud_off_rounded,
        Availability.ready => Icons.check_circle_rounded,
        Availability.needsSetup => Icons.key_rounded,
        Availability.unavailable => Icons.block_rounded,
        Availability.phoneVoice => Icons.phone_android_rounded,
      };

  Color color(ColorScheme scheme) => switch (availability) {
        Availability.checking => scheme.outline,
        Availability.offline => AppColors.danger,
        Availability.ready => AppColors.success,
        Availability.needsSetup => AppColors.warning,
        Availability.unavailable => scheme.outline,
        Availability.phoneVoice => scheme.primary,
      };
}
