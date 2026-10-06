import '../models/management_json.dart';

String civilDateIso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String civilDateDisplay(String iso) {
  managementDate(iso, 'data');
  return '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
}

String civilDateFromInput(String input) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(input.trim());
  if (match == null) throw const FormatException('Use DD/MM/AAAA.');
  final iso = '${match[3]}-${match[2]}-${match[1]}';
  if (int.parse(match[3]!) < 1) throw const FormatException('Data inválida.');
  return managementDate(iso, 'data');
}
