import 'package:clash_go/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version comparison', () {
    test('strips the tag prefix', () {
      expect(UpdateService.normalizeVersion('v1.2.3'), '1.2.3');
      expect(UpdateService.normalizeVersion(' V2.0.0 '), '2.0.0');
    });

    test('compares release versions', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('0.9.9', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.10.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0+2', '1.0.0'), isFalse);
    });

    test('orders prereleases below the final release', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0-beta.2'), isTrue);
      expect(UpdateService.isNewer('1.0.0-beta.2', '1.0.0-beta.1'), isTrue);
      expect(UpdateService.isNewer('1.0.0-beta.1', '1.0.0-beta.2'), isFalse);
      expect(UpdateService.isNewer('1.0.0-beta', '1.0.0-alpha'), isTrue);
      expect(UpdateService.isNewer('1.0.0-beta.1', '1.0.0'), isFalse);
    });
  });

  group('release parsing', () {
    test('reads the tag from the latest redirect target', () {
      final release = UpdateService.releaseFromUri(
        Uri.parse('https://github.com/ChenL-eon/ClashGo/releases/tag/v1.4.2'),
      );
      expect(release, isNotNull);
      expect(release!.version, '1.4.2');
      expect(release.url, 'https://github.com/ChenL-eon/ClashGo/releases/tag/v1.4.2');
    });

    test('ignores the unredirected latest URL', () {
      expect(
        UpdateService.releaseFromUri(
          Uri.parse('https://github.com/ChenL-eon/ClashGo/releases/latest'),
        ),
        isNull,
      );
    });

    test('reads the first entry of the releases atom feed', () {
      const atom = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>tag:github.com,2008:Repository/1/v1.5.0-beta.1</id>
    <link type="text/html" href="https://github.com/ChenL-eon/ClashGo/releases/tag/v1.5.0-beta.1" rel="alternate"/>
    <title>v1.5.0-beta.1</title>
  </entry>
  <entry>
    <link href="https://github.com/ChenL-eon/ClashGo/releases/tag/v1.4.2" rel="alternate"/>
    <title>v1.4.2</title>
  </entry>
</feed>''';
      final release = UpdateService.parseAtom(atom);
      expect(release, isNotNull);
      expect(release!.version, '1.5.0-beta.1');
      expect(release.url, contains('/releases/tag/v1.5.0-beta.1'));
    });

    test('returns null for malformed feeds', () {
      expect(UpdateService.parseAtom(''), isNull);
      expect(UpdateService.parseAtom('<feed></feed>'), isNull);
      expect(
        UpdateService.parseAtom('<entry><title>v1.0.0</title></entry>'),
        isNull,
      );
    });
  });
}
