import 'package:flutter/material.dart';

import 'api/api_models.dart';
import 'state/app_controller.dart';
import 'theme/app_colors.dart';

enum Feature { tts, maleToFemale, femaleToMale, live, cloning }

enum Availability { checking, offline, ready, needsSetup, unavailable, freeOnline }

/// Honest availability for each feature. Server features are enabled only when
/// the backend reports a working provider; otherwise text-to-speech and the
/// recorded conversions fall back to the free online engines (Hugging Face).
/// Live conversion has no free streaming engine, so it stays unavailable.
class FeatureStatus {
  const FeatureStatus(this.availability, this.message);

  final Availability availability;
  final String message;

  bool get ready => availability == Availability.ready;

  static FeatureStatus of(AppController app, Feature feature) {
    final server = serverOf(app, feature);
    if (feature == Feature.live || server.ready || server.availability == Availability.checking) return server;
    if (feature == Feature.cloning) {
      return const FeatureStatus(
        Availability.freeOnline,
        'Voices are saved on this phone and spoken by the free AI4Bharat IndicF5 server on Hugging Face. '
        'Needs internet; a few voices per day for each internet connection.',
      );
    }
    return FeatureStatus(
      Availability.freeOnline,
      feature == Feature.tts
          ? 'Uses the free natural Telugu voice (AI4Bharat IndicF5 on Hugging Face). Needs internet; '
              "your text is sent there. The phone's own Telugu voice also works offline."
          : 'Uses the free Seed-VC engine on Hugging Face. Needs internet; your recording is uploaded there '
              'to be converted. The free server allows only a few conversions per day for each internet connection.',
    );
  }

  /// Availability of the server-side feature only (ignores the free engines).
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
      Feature.cloning => health.voiceCloning ?? Capability(available: false, providers: const []),
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
        Availability.freeOnline => 'Free online',
      };

  IconData get icon => switch (availability) {
        Availability.checking => Icons.hourglass_top_rounded,
        Availability.offline => Icons.cloud_off_rounded,
        Availability.ready => Icons.check_circle_rounded,
        Availability.needsSetup => Icons.key_rounded,
        Availability.unavailable => Icons.block_rounded,
        Availability.freeOnline => Icons.cloud_done_rounded,
      };

  Color color(ColorScheme scheme) => switch (availability) {
        Availability.checking => scheme.outline,
        Availability.offline => AppColors.danger,
        Availability.ready => AppColors.success,
        Availability.needsSetup => AppColors.warning,
        Availability.unavailable => scheme.outline,
        Availability.freeOnline => AppColors.success,
      };
}
