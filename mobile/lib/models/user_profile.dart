class EmergencyContact {
  final String id;
  final String displayName;
  final String relationship;
  final String phoneE164;
  final String kind;

  EmergencyContact({
    required this.id,
    required this.displayName,
    required this.relationship,
    required this.phoneE164,
    this.kind = 'emergency',
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] ?? '',
      displayName: json['display_name'] ?? '',
      relationship: json['relationship'] ?? '',
      phoneE164: json['phone_e164'] ?? '',
      kind: json['kind'] ?? 'emergency',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'relationship': relationship,
    'phone_e164': phoneE164,
    'kind': kind,
  };
}

class UserProfile {
  final String id;
  final String phoneE164;
  final String displayName;
  final String persona; // 'elder' (55+) or 'ear' (20-50)
  final String ageBand;
  final String gender;
  final String companionName;
  final String companionGender;
  final String preferredTone; // 'respectful' or 'friendly'
  final String locale; // 'en-IN' or 'hi-IN'
  final String wakeWordPhrase;
  final String email;
  final String occupation;
  final List<String> talkTopics;
  final List<EmergencyContact> emergencyContacts;

  UserProfile({
    required this.id,
    required this.phoneE164,
    required this.displayName,
    this.email = 'peeyush.panthari@gmail.com',
    this.occupation = '',
    this.talkTopics = const [],
    required this.persona,
    required this.ageBand,
    required this.gender,
    required this.companionName,
    required this.companionGender,
    required this.preferredTone,
    required this.locale,
    required this.wakeWordPhrase,
    this.emergencyContacts = const [],
  });

  bool get isElder => persona == 'elder';

  UserProfile copyWith({
    String? id,
    String? phoneE164,
    String? displayName,
    String? email,
    String? occupation,
    List<String>? talkTopics,
    String? persona,
    String? ageBand,
    String? gender,
    String? companionName,
    String? companionGender,
    String? preferredTone,
    String? locale,
    String? wakeWordPhrase,
    List<EmergencyContact>? emergencyContacts,
  }) {
    return UserProfile(
      id: id ?? this.id,
      phoneE164: phoneE164 ?? this.phoneE164,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      occupation: occupation ?? this.occupation,
      talkTopics: talkTopics ?? this.talkTopics,
      persona: persona ?? this.persona,
      ageBand: ageBand ?? this.ageBand,
      gender: gender ?? this.gender,
      companionName: companionName ?? this.companionName,
      companionGender: companionGender ?? this.companionGender,
      preferredTone: preferredTone ?? this.preferredTone,
      locale: locale ?? this.locale,
      wakeWordPhrase: wakeWordPhrase ?? this.wakeWordPhrase,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    var contactsJson = json['emergency_contacts'] as List? ?? [];
    List<EmergencyContact> contacts =
        contactsJson.map((c) => EmergencyContact.fromJson(c)).toList();

    var topicsJson = json['talk_topics'] as List? ?? [];
    List<String> topics = topicsJson.map((t) => t.toString()).toList();

    return UserProfile(
      id: json['id'] ?? '',
      phoneE164: json['phone_e164'] ?? '',
      displayName: json['display_name'] ?? 'Friend',
      email: json['email'] ?? 'peeyush.panthari@gmail.com',
      occupation: json['occupation'] ?? '',
      talkTopics: topics,
      persona: json['persona'] ?? 'elder',
      ageBand: json['age_band'] ?? '55-64',
      gender: json['gender'] ?? 'unspecified',
      companionName: json['companion_name'] ?? 'Nuvin',
      companionGender: json['companion_gender'] ?? 'female',
      preferredTone: json['preferred_tone'] ?? 'respectful',
      locale: json['locale'] ?? 'en-IN',
      wakeWordPhrase: json['wake_word_phrase'] ?? 'Hey Nuvin',
      emergencyContacts: contacts,
    );
  }
}
