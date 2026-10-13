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
  const ClockEstimate(this.offsetMs, this.measuredAt);
  final int offsetMs;
  final DateTime measuredAt;
  // W08: server UTC - device UTC. Truncate toward zero, preserving sign.
  int get seconds => offsetMs ~/ 1000;
}
