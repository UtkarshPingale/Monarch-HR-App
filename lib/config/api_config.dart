import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ── CONFIG ───────────────────────────────────────────────────────────────────
// Python PostgreSQL API Server URL
// Use "http://10.0.2.2:3001" for Android Emulator, or "http://192.168.1.111:3001" for physical phone/LAN, or when is port is live "http://175.100.175.42:3001"
const String baseUrl = "http://175.100.175.42:3001";

// ── HTTP helpers ──────────────────────────────────────────────────────────────
Future<Map<String, dynamic>> apiPost(String path, Map body, {String? token}) async {
  try {
    final r = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    return jsonDecode(r.body);
  } catch (e) {
    return {'error': 'Network timeout or connection error. Please try again.'};
  }
}

Future<Map<String, dynamic>> apiPut(String path, Map body, {String? token}) async {
  try {
    final r = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    return jsonDecode(r.body);
  } catch (e) {
    return {'error': 'Network timeout or connection error. Please try again.'};
  }
}

Future<List<dynamic>> apiGet(String path, {String? token}) async {
  try {
    final r = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      final decoded = jsonDecode(r.body);
      if (decoded is List) return decoded;
    }
  } catch (_) {}
  return [];
}

Future<dynamic> apiGetJson(String path, {String? token}) async {
  try {
    final r = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      return jsonDecode(r.body);
    }
  } catch (_) {}
  return null;
}

// ── Save route silently to DB ─────────────────────────────────────────────────
Future<void> saveRouteToDB(String shiftId, String token) async {
  try {
    await http.post(
      Uri.parse('$baseUrl/api/attendance/$shiftId/save-route'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 6));
  } catch (_) {}
}

// ── Location Helper ───────────────────────────────────────────────────────────
Future<Position?> getPosition() async {
  try {
    bool svc = await Geolocator.isLocationServiceEnabled().timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
    if (!svc) {
      return await Geolocator.getLastKnownPosition();
    }
    LocationPermission perm = await Geolocator.checkPermission().timeout(
      const Duration(seconds: 3),
      onTimeout: () => LocationPermission.denied,
    );
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 5),
        onTimeout: () => LocationPermission.denied,
      );
      if (perm == LocationPermission.denied) {
        return await Geolocator.getLastKnownPosition();
      }
    }
    if (perm == LocationPermission.deniedForever) {
      return await Geolocator.getLastKnownPosition();
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  } catch (_) {
    return await Geolocator.getLastKnownPosition();
  }
}
