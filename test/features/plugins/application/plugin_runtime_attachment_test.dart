import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/features/plugins/application/plugin_runtime_attachment.dart';

void main() {
  test('a retained plugin keeps its runtime after the page closes', () {
    final attachment = PluginRuntimeAttachment();
    attachment.attachUi('org.example.plugin');
    attachment.retain('org.example.plugin');

    attachment.detachUi('org.example.plugin');

    expect(attachment.shouldStopAfterDetach('org.example.plugin'), isFalse);
    expect(attachment.retains('org.example.plugin'), isTrue);
    expect(attachment.hasUi('org.example.plugin'), isFalse);
  });

  test('release stops a background plugin only when no page is attached', () {
    final attachment = PluginRuntimeAttachment();
    attachment.attachUi('org.example.plugin');
    attachment.retain('org.example.plugin');

    attachment.release('org.example.plugin');

    expect(attachment.shouldStopAfterRelease('org.example.plugin'), isFalse);
    attachment.detachUi('org.example.plugin');
    expect(attachment.shouldStopAfterDetach('org.example.plugin'), isTrue);
  });

  test('release stops a plugin that is only running in the background', () {
    final attachment = PluginRuntimeAttachment();
    attachment.retain('org.example.plugin');

    attachment.release('org.example.plugin');

    expect(attachment.shouldStopAfterRelease('org.example.plugin'), isTrue);
    expect(attachment.retains('org.example.plugin'), isFalse);
  });
}
