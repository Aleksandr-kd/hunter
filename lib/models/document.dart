/// Документ пользователя (охотничий билет, разрешение и т.д.).
class Document {
  final String? id;
  final String? supabaseId; // id из таблицы user_documents
  final String title;
  final DateTime? expiryDate;

  Document({
    this.id,
    this.supabaseId,
    required this.title,
    this.expiryDate,
  });

  Document copyWith({
    String? supabaseId,
    DateTime? expiryDate,
  }) {
    return Document(
      id: id,
      supabaseId: supabaseId ?? this.supabaseId,
      title: title,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supabase_id': supabaseId,
      'title': title,
      'expiry_date': expiryDate?.toIso8601String(),
    };
  }

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] as String?,
      supabaseId: map['supabase_id'] as String?,
      title: map['title'] as String? ?? '',
      expiryDate: map['expiry_date'] != null
          ? DateTime.tryParse(map['expiry_date'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Document && runtimeType == other.runtimeType && title == other.title;

  @override
  int get hashCode => title.hashCode;
}
