import 'package:timezone/timezone.dart' as tz;

abstract interface class Clock {
  DateTime now();
}

class DeviceClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

String civilDate(DateTime instant, String zone) => tz.TZDateTime.from(
  instant,
  tz.getLocation(zone),
).toIso8601String().substring(0, 10);

String explicitIso(DateTime instant) {
  final minutes = instant.timeZoneOffset.inMinutes;
  final wall = DateTime.utc(
    instant.year,
    instant.month,
    instant.day,
    instant.hour,
    instant.minute,
    instant.second,
    instant.millisecond,
    instant.microsecond,
  ).toIso8601String().replaceAll(RegExp(r'Z$'), '');
  final sign = minutes < 0 ? '-' : '+';
  final hours = (minutes.abs() ~/ 60).toString().padLeft(2, '0');
  final rest = (minutes.abs() % 60).toString().padLeft(2, '0');
  return '$wall$sign$hours:$rest';
}

class ClockEstimate {
  const ClockEstimate(
    this.offsetMs,
    this.measuredAt, {
    this.serverTimestamp,
    this.roundTripMs,
    this.source = 'injected',
  });
  final int offsetMs;
  final DateTime measuredAt;
  final DateTime? serverTimestamp;
  final int? roundTripMs;
  final String source;
  // W08: server UTC - device UTC. Truncate toward zero, preserving sign.
  int get seconds => offsetMs ~/ 1000;
}

// Reject normalized invalid dates and timestamps without an explicit offset.
DateTime? parseExplicitTimestamp(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) return null;
  final numbers = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final [year, month, day, hour, minute, second] = numbers;
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final zone = match.group(7)!;
  if (zone != 'Z') {
    final hours = int.parse(zone.substring(1, 3));
    final minutes = int.parse(zone.substring(4, 6));
    if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
      return null;
    }
  }
  return DateTime.tryParse(value)?.toUtc();
}
