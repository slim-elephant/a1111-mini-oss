import 'package:flutter_test/flutter_test.dart';
import 'package:a1111_mini/core/api/api_models.dart';
import 'package:a1111_mini/core/api/connection_retry.dart';

void main() {
  test('retries a failed probe then returns the success', () async {
    var calls = 0;
    final status = await withConnectionRetries(() async {
      calls++;
      if (calls < 2) {
        return const ConnectionStatus(
          connected: false,
          error: 'Could not reach ComfyUI. Check the address, or that LM Mini Connect is running.',
        );
      }
      return const ConnectionStatus(connected: true, currentModel: 'sdxl.safetensors');
    });
    expect(calls, 2);
    expect(status.connected, isTrue);
    expect(status.currentModel, 'sdxl.safetensors');
  });

  test('does not retry a rejected token', () async {
    var calls = 0;
    final status = await withConnectionRetries(() async {
      calls++;
      return const ConnectionStatus(
        connected: false,
        error: 'Relay rejected the token. Re-scan the QR code in LM Mini Connect.',
      );
    });
    expect(calls, 1);
    expect(status.connected, isFalse);
  });

  test('cloudflare 502 body maps to relay-session copy', () {
    expect(
      proxyErrorMessage('error code: 502'),
      kRelayDesktopMissingMessage,
    );
    expect(
      proxyErrorMessage({
        'error': {'message': 'Desktop is not connected. Open LM Mini Connect on your computer.'},
      }),
      contains('Desktop is not connected'),
    );
  });

  test('gives up after two attempts on a dropped connection', () async {
    var calls = 0;
    await withConnectionRetries(() async {
      calls++;
      return const ConnectionStatus(
        connected: false,
        error: 'Could not reach A1111. Check the address, or that LM Mini Connect is running.',
      );
    });
    expect(calls, 2);
  });

  test('does not retry timeouts or empty errors', () async {
    for (final error in ['Connection timed out', '', null]) {
      var calls = 0;
      final status = await withConnectionRetries(() async {
        calls++;
        return ConnectionStatus(connected: false, error: error);
      });
      expect(calls, 1, reason: 'error: $error');
      expect(status.error, error);
    }
  });

  test('warns only when every model listing came back empty', () {
    expect(noModelsWarning([0]), 'Connected, but no models found');
    expect(noModelsWarning([0, 0, 0]), isNotNull);
    expect(noModelsWarning([0, 3, 0]), isNull);
    expect(noModelsWarning([0, null]), isNull);
    expect(noModelsWarning([]), isNull);
  });
}
