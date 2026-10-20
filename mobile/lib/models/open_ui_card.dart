class OpenUICard {
  final String type; // 'memory_vault_card', 'reminder_card', 'sos_emergency_card'
  final String title;
  final Map<String, dynamic> data;

  OpenUICard({
    required this.type,
    required this.title,
    required this.data,
  });

  factory OpenUICard.fromJson(Map<String, dynamic> json) {
    return OpenUICard(
      type: json['type'] ?? 'generic',
      title: json['title'] ?? '',
      data: json,
    );
  }
}
