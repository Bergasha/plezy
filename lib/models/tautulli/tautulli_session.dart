import 'package:flutter/foundation.dart';

/// A single active Plex playback session, as reported by Tautulli's
/// `get_activity` command. Field names below match Tautulli's actual raw
/// JSON keys (snake_case), not any third-party client's transformed names.
@immutable
class TautulliSession {
  final String sessionKey;
  final String friendlyName;
  final String title;

  /// Show name for an episode session; null for movies/other media types.
  final String? grandparentTitle;
  final String mediaType;
  final String state;
  final double progressPercent;
  final String transcodeDecision;
  final int bandwidthKbps;
  final String? qualityProfile;

  const TautulliSession({
    required this.sessionKey,
    required this.friendlyName,
    required this.title,
    this.grandparentTitle,
    required this.mediaType,
    required this.state,
    required this.progressPercent,
    required this.transcodeDecision,
    required this.bandwidthKbps,
    this.qualityProfile,
  });

  /// Full display title: "Show Name - Episode Title" for episodes, otherwise
  /// just the title.
  String get displayTitle {
    final show = grandparentTitle;
    return (show != null && show.isNotEmpty) ? '$show - $title' : title;
  }

  factory TautulliSession.fromJson(Map<String, dynamic> json) {
    return TautulliSession(
      sessionKey: _asString(json['session_key']) ?? '',
      friendlyName: _asString(json['friendly_name']) ?? _asString(json['user']) ?? 'Unknown',
      title: _asString(json['title']) ?? '',
      grandparentTitle: _asString(json['grandparent_title']),
      mediaType: _asString(json['media_type']) ?? '',
      state: _asString(json['state']) ?? '',
      progressPercent: _asDouble(json['progress_percent']) ?? 0,
      transcodeDecision: _asString(json['transcode_decision']) ?? '',
      bandwidthKbps: _asInt(json['bandwidth']) ?? 0,
      qualityProfile: _asString(json['quality_profile']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TautulliSession &&
      other.sessionKey == sessionKey &&
      other.title == title &&
      other.state == state &&
      other.progressPercent == progressPercent &&
      other.transcodeDecision == transcodeDecision &&
      other.bandwidthKbps == bandwidthKbps;

  @override
  int get hashCode => Object.hash(sessionKey, title, state, progressPercent, transcodeDecision, bandwidthKbps);
}

// Tautulli returns most numeric fields as JSON strings, so parsing must
// accept both a native number and its string representation.
String? _asString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
