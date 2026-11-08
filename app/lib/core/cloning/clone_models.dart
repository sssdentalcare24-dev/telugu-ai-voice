import '../free/local_audio_store.dart';

/// A language a cloned voice can speak (and the script it is written in).
class CloneLanguage {
  const CloneLanguage(this.code, this.name, this.native, this.scriptStart, this.scriptEnd, {this.sample, this.script});

  final String code; // ISO 639-1, as the server uses
  final String name;
  final String native;

  /// Unicode block of the language's script (Latin for English).
  final int scriptStart;
  final int scriptEnd;

  /// Example text for the Text to Speech box.
  final String? sample;

  /// A sentence to read aloud when recording a voice (about 10 seconds).
  final String? script;

  String get label => code == 'en' ? name : '$native · $name';

  /// True when [text] contains at least one letter of this language's script.
  bool matches(String text) => text.runes.any((r) => r >= scriptStart && r <= scriptEnd);

  static CloneLanguage byCode(String code) => all.firstWhere((l) => l.code == code, orElse: () => all.first);

  static const List<CloneLanguage> all = [
    CloneLanguage(
      'te', 'Telugu', 'తెలుగు', 0x0C00, 0x0C7F,
      sample: 'నమస్కారం! ఎలా ఉన్నారు? భోజనం చేశారా? ఈరోజు మీతో మాట్లాడాలని అనిపించింది.',
      script: 'నమస్కారం! ఈ రోజు వాతావరణం చాలా బాగుంది. నేను ఉదయాన్నే లేచి, కాఫీ తాగి, '
          'మా ఇంటి దగ్గర ఉన్న పార్కులో కొద్దిసేపు నడిచాను.',
    ),
    CloneLanguage(
      'hi', 'Hindi', 'हिन्दी', 0x0900, 0x097F,
      sample: 'नमस्ते! आप कैसे हैं? क्या आपने खाना खाया? आज आपसे बात करने का मन हुआ।',
      script: 'नमस्ते! आज मौसम बहुत अच्छा है। मैंने सुबह चाय पी और घर के पास वाले पार्क में थोड़ी देर सैर की।',
    ),
    CloneLanguage(
      'en', 'English', 'English', 0x0041, 0x007A,
      sample: 'Hello! How are you? Have you eaten? I felt like talking to you today.',
      script: 'Hello! The weather is lovely today. I had a cup of coffee this morning '
          'and took a short walk in the park near my home.',
    ),
    CloneLanguage('ta', 'Tamil', 'தமிழ்', 0x0B80, 0x0BFF, sample: 'வணக்கம்! எப்படி இருக்கிறீர்கள்?'),
    CloneLanguage('kn', 'Kannada', 'ಕನ್ನಡ', 0x0C80, 0x0CFF, sample: 'ನಮಸ್ಕಾರ! ಹೇಗಿದ್ದೀರಿ?'),
    CloneLanguage('ml', 'Malayalam', 'മലയാളം', 0x0D00, 0x0D7F, sample: 'നമസ്കാരം! സുഖമാണോ?'),
    CloneLanguage('mr', 'Marathi', 'मराठी', 0x0900, 0x097F, sample: 'नमस्कार! तुम्ही कसे आहात?'),
    CloneLanguage('bn', 'Bengali', 'বাংলা', 0x0980, 0x09FF, sample: 'নমস্কার! আপনি কেমন আছেন?'),
    CloneLanguage('gu', 'Gujarati', 'ગુજરાતી', 0x0A80, 0x0AFF, sample: 'નમસ્તે! તમે કેમ છો?'),
    CloneLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ', 0x0A00, 0x0A7F, sample: 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ! ਤੁਸੀਂ ਕਿਵੇਂ ਹੋ?'),
    CloneLanguage('or', 'Odia', 'ଓଡ଼ିଆ', 0x0B00, 0x0B7F, sample: 'ନମସ୍କାର! ଆପଣ କେମିତି ଅଛନ୍ତି?'),
    CloneLanguage('as', 'Assamese', 'অসমীয়া', 0x0980, 0x09FF, sample: 'নমস্কাৰ! আপুনি কেনে আছে?'),
  ];
}

/// What a cloning provider can do and needs (from the server, or built in for
/// the free on-phone mode).
class CloneProviderInfo {
  const CloneProviderInfo({
    required this.name,
    required this.label,
    required this.paid,
    required this.ready,
    required this.message,
    required this.minSeconds,
    required this.maxSeconds,
    required this.recommended,
    required this.needsTranscript,
    required this.languages,
    required this.crossLingual,
    required this.supportsSpeed,
  });

  factory CloneProviderInfo.fromJson(Map<String, dynamic> j) => CloneProviderInfo(
        name: j['name'] as String? ?? '',
        label: j['label'] as String? ?? (j['name'] as String? ?? ''),
        paid: j['paid'] == true,
        ready: j['ready'] == true,
        message: j['message'] as String? ?? '',
        minSeconds: (j['min_seconds'] as num?)?.toDouble() ?? 5,
        maxSeconds: (j['max_seconds'] as num?)?.toDouble() ?? 30,
        recommended: j['recommended'] as String? ?? '',
        needsTranscript: j['needs_transcript'] == true,
        languages: [for (final l in (j['languages'] as List? ?? const [])) if (l is String) l],
        crossLingual: j['cross_lingual'] == true,
        supportsSpeed: j['supports_speed'] == true,
      );

  /// The free engine used on the phone: AI4Bharat IndicF5 (zero-shot cloning).
  static const indicF5OnPhone = CloneProviderInfo(
    name: 'indicf5',
    label: 'AI4Bharat IndicF5 · free',
    paid: false,
    ready: true,
    message: 'Free public Hugging Face server; a few voices per day for each internet connection.',
    minSeconds: 5,
    maxSeconds: 15,
    recommended: 'Read the sentence below in a quiet room: 8–12 seconds, one person only.',
    needsTranscript: true,
    languages: ['te', 'hi', 'ta', 'kn', 'ml', 'mr', 'bn', 'gu', 'pa', 'or', 'as'],
    crossLingual: true,
    supportsSpeed: false, // the app changes speed itself (see time_stretch.dart)
  );

  final String name;
  final String label;
  final bool paid;
  final bool ready;
  final String message;
  final double minSeconds;
  final double maxSeconds;
  final String recommended;
  final bool needsTranscript;
  final List<String> languages;
  final bool crossLingual;
  final bool supportsSpeed;
}

/// The speaker's consent, saved with every voice.
class ConsentRecord {
  const ConsentRecord({required this.relationship, required this.statement, this.speakerName});

  /// 'self' (my own voice) or 'permission' (the speaker allowed it).
  final String relationship;
  final String statement;
  final String? speakerName;

  Map<String, Object?> toJson({DateTime? acceptedAt}) => {
        'confirmed': true,
        'relationship': relationship,
        'statement': statement,
        if (speakerName != null && speakerName!.isNotEmpty) 'speaker_name': speakerName,
        if (acceptedAt != null) 'accepted_at': acceptedAt.toUtc().toIso8601String(),
      };

  static String statementFor(String relationship) => relationship == 'self'
      ? 'This is my own voice. I agree to create an AI copy of it and will not use it to deceive or impersonate anyone.'
      : 'The speaker in this recording gave me explicit permission to create an AI copy of their voice. '
          'I will not use it to deceive or impersonate anyone.';
}

/// A saved personal voice.
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.recordingLanguage,
    required this.provider,
    required this.status,
    required this.createdAt,
    this.providerVoiceId,
    this.transcript,
    this.consent = const {},
    this.sample,
    this.preview,
    this.warning,
  });

  final String id;
  final String name;

  /// 'female' or 'male' – a label; the voice is always the recorded speaker's.
  final String category;
  final String recordingLanguage;
  final String provider;

  /// draft | ready | failed
  final String status;
  final DateTime createdAt;
  final String? providerVoiceId;
  final String? transcript;
  final Map<String, dynamic> consent;
  final LocalAudio? sample;
  final LocalAudio? preview;

  /// e.g. "Voice saved, but the preview could not be made now".
  final String? warning;

  bool get ready => status == 'ready';

  VoiceProfile copyWith({LocalAudio? preview, String? warning}) => VoiceProfile(
        id: id,
        name: name,
        category: category,
        recordingLanguage: recordingLanguage,
        provider: provider,
        status: status,
        createdAt: createdAt,
        providerVoiceId: providerVoiceId,
        transcript: transcript,
        consent: consent,
        sample: sample,
        preview: preview ?? this.preview,
        warning: warning,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'recording_language': recordingLanguage,
        'provider': provider,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'provider_voice_id': providerVoiceId,
        'transcript': transcript,
        'consent': consent,
        'sample': sample?.toJson(),
        'preview': preview?.toJson(),
      };

  static VoiceProfile? fromLocalJson(Object? json) {
    if (json is! Map) return null;
    try {
      return VoiceProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        recordingLanguage: json['recording_language'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        providerVoiceId: json['provider_voice_id'] as String?,
        transcript: json['transcript'] as String?,
        consent: Map<String, dynamic>.from(json['consent'] as Map? ?? const {}),
        sample: LocalAudio.fromJson(json['sample']),
        preview: LocalAudio.fromJson(json['preview']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Progress callback for long steps (uploading, cloning, generating).
typedef CloneProgress = void Function(double fraction, String message);
