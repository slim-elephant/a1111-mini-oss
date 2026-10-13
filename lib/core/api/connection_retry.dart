import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_models.dart';

const kRelayDesktopMissingMessage =
    'LM Mini Connect is not on this relay session. Open Connect and keep the computer awake — sleep or closing the lid drops it. You do not need a new QR unless Connect generated a new one.';

/// Best-effort message from a Dio/relay error body.
String? proxyErrorMessage(Object? data) {
  if (data is Map) {
    final err = data['error'];
    if (err is Map && err['message'] != null) {
      return err['message'].toString();
    }
    if (err is String && err.trim().isNotEmpty) return err.trim();
    if (data['message'] is String) return data['message'] as String;
  }
  if (data is String && data.trim().isNotEmpty) {
    final text = data.trim();
    try {
      return proxyErrorMessage(jsonDecode(text));
    } catch (_) {
      if (text.toLowerCase().contains('error code: 502')) {
        return kRelayDesktopMissingMessage;
      }
      return text.length > 180 ? text.substring(0, 180) : text;
    }
  }
  return null;
}

String humanizeStatusCode(DioException e, {required String unreachable}) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'Connection timed out';
  }
  if (e.type == DioExceptionType.connectionError) {
    return 'Could not reach $unreachable. Check the address, or that LM Mini Connect is running.';
  }
  final code = e.response?.statusCode;
  final message = proxyErrorMessage(e.response?.data);
  if (code == 401) {
    return 'Relay rejected the token. Re-scan the QR code in LM Mini Connect.';
  }
  if (code == 502 || code == 503) {
    if (message != null &&
        !message.toLowerCase().contains('error code: 502')) {
      return message;
    }
    return kRelayDesktopMissingMessage;
  }
  return message ?? e.message ?? e.toString();
}

/// Receive timeout for status probes. Generation requests keep the client's
/// long timeout; a probe that has not answered in this window is down.
const kProbeReceiveTimeout = Duration(seconds: 8);

/// Per-request options for status probes.
Options probeOptions() => Options(receiveTimeout: kProbeReceiveTimeout);

/// Shown when a probe gets a 200 that is not JSON (captive portal, proxy,
/// some other web app on that port).
String unexpectedResponseMessage(String backend) =>
    'Got an unexpected response — is this really an $backend server?';

/// Shown when the port answers as the other backend.
String wrongBackendMessage({required String found, required String expected}) =>
    'This looks like $found, not $expected. Change the provider or port.';

bool isNotFound(DioException e) =>
    e.type == DioExceptionType.badResponse && e.response?.statusCode == 404;

/// Warning for a reachable server with nothing to generate with. [counts]
/// are model counts per folder/endpoint; null means that listing failed, in
/// which case we stay quiet rather than guess.
String? noModelsWarning(List<int?> counts) {
  if (counts.isEmpty || counts.any((c) => c == null)) return null;
  if (counts.fold<int>(0, (a, c) => a + c!) > 0) return null;
  return 'Connected, but no models found';
}

/// Retries a relay/LAN probe once. The first request after pairing often
/// hits a connection reset while Connect is still finishing host-status.
Future<ConnectionStatus> withConnectionRetries(
  Future<ConnectionStatus> Function() probe, {
  int attempts = 2,
}) async {
  ConnectionStatus? last;
  for (var i = 0; i < attempts; i++) {
    if (i > 0) {
      await Future<void>.delayed(Duration(milliseconds: 400 * i));
    }
    last = await probe();
    if (last.connected || !_shouldRetry(last)) return last;
  }
  return last!;
}

/// Only transient connection drops are worth a second try. Timeouts already
/// waited a full probe window, and unknown errors should surface as-is.
bool _shouldRetry(ConnectionStatus status) {
  final error = (status.error ?? '').toLowerCase();
  if (error.isEmpty) return false;
  if (error.contains('rejected the token') ||
      error.contains('scan the qr') ||
      error.contains('401') ||
      error.contains('timed out') ||
      error.contains('timeout')) {
    return false;
  }
  return error.contains('could not reach') ||
      error.contains('not connected') ||
      error.contains('relay session') ||
      error.contains('502') ||
      error.contains('503') ||
      error.contains('socket') ||
      error.contains('connection');
}
