import 'package:intl/intl.dart';

/// Parses any date/time string or object returned from the server
/// and converts it to local device DateTime (e.g. IST).
///
/// Handles:
/// 1. ISO-8601 with Z or offset ("2026-09-19T05:51:00.000Z", "2026-09-19T11:21:00+05:30")
/// 2. ISO-8601 naive ("2026-09-19T11:21:00")
/// 3. Plain time string ("11:21:00", "05:51")
/// 4. Plain date string ("2026-09-19")
/// 5. Already a DateTime object
DateTime? parseAppDateTime(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) {
    return val.isUtc ? val.toLocal() : val;
  }
  final str = val.toString().trim();
  if (str.isEmpty || str == 'null') return null;

  try {
    // If plain time e.g. "11:21:00" or "05:51"
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(str)) {
      final parts = str.split(':');
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? (int.tryParse(parts[2].split('.')[0]) ?? 0) : 0,
      );
    }

    // Standard DateTime parse
    DateTime dt = DateTime.parse(str);
    if (dt.isUtc) {
      dt = dt.toLocal();
    }
    return dt;
  } catch (_) {
    return null;
  }
}

/// Formats a DateTime or date/time string to "hh:mm a" (e.g. "11:21 AM") in local device time
String formatAppTime(dynamic val, {String placeholder = '-- : --'}) {
  final dt = parseAppDateTime(val);
  if (dt == null) return placeholder;
  return DateFormat('hh:mm a').format(dt);
}

/// Formats a DateTime or date/time string to "d MMM yyyy" (e.g. "19 Sep 2026")
String formatAppDate(dynamic val, {String placeholder = '--'}) {
  final dt = parseAppDateTime(val);
  if (dt == null) return placeholder;
  return DateFormat('d MMM yyyy').format(dt);
}
