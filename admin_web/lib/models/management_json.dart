Map<String, dynamic> managementObject(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Objeto JSON inválido.');
  }
  return Map<String, dynamic>.from(value);
}

String managementString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field deve ser texto não vazio.');
  }
  return value.trim();
}

String? managementOptionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field deve ser texto ou null.');
  return value;
}

String managementDate(Object? value, String field) {
  final text = managementString(value, field);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw FormatException('$field exige AAAA-MM-DD.');
  }
  final date = DateTime.tryParse('${text}T00:00:00Z');
  if (date == null || date.toIso8601String().substring(0, 10) != text) {
    throw FormatException('$field contém data inválida.');
  }
  return text;
}
