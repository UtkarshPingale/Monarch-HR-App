import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ── CONFIG ───────────────────────────────────────────────────────────────────
// Python PostgreSQL API Server URL
// Use "http://10.0.2.2:3001" for Android Emulator, or "http://192.168.1.111:3001" for physical phone/LAN, or when is port is live "http://175.100.175.42:3001"
const String baseUrl = "http://10.0.2.2:3001";

// ── HTTP helpers ──────────────────────────────────────────────────────────────
Future<Map<String, dynamic>> apiPost(String path, Map body, {String? token}) async {
  final r = await http.post(
    Uri.parse('$baseUrl$path'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
  return jsonDecode(r.body);
}

Future<Map<String, dynamic>> apiPut(String path, Map body, {String? token}) async {
  final r = await http.put(
    Uri.parse('$baseUrl$path'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
  return jsonDecode(r.body);
}

Future<List<dynamic>> apiGet(String path, {String? token}) async {
  final r = await http.get(
    Uri.parse('$baseUrl$path'),
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );
  if (r.statusCode == 200) {
    final decoded = jsonDecode(r.body);
    if (decoded is List) return decoded;
  }
  return [];
}

Future<dynamic> apiGetJson(String path, {String? token}) async {
  final r = await http.get(
    Uri.parse('$baseUrl$path'),
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );
  if (r.statusCode == 200) {
    return jsonDecode(r.body);
  }
  return null;
}

// ── Save route silently to DB ─────────────────────────────────────────────────
Future<void> saveRouteToDB(String shiftId, String token) async {
  try {
    await http.post(
      Uri.parse('$baseUrl/api/attendance/$shiftId/save-route'),
      headers: {'Authorization': 'Bearer $token'},
    );
  } catch (_) {}
}

// ── Location Helper ───────────────────────────────────────────────────────────
Future<Position?> getPosition() async {
  bool svc = await Geolocator.isLocationServiceEnabled();
  if (!svc) return null;
  LocationPermission perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return null;
  }
  if (perm == LocationPermission.deniedForever) return null;
  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}
