import 'package:tapster/services/github_service.dart';
import 'package:test/test.dart';

void main() {
  group('GitHubService.stripDigestPrefix', () {
    test('strips sha256: prefix', () {
      expect(
        GitHubService.stripDigestPrefix(
          'sha256:abcdef1234567890',
        ),
        'abcdef1234567890',
      );
    });

    test('keeps digests without prefix', () {
      expect(
        GitHubService.stripDigestPrefix('abcdef1234567890'),
        'abcdef1234567890',
      );
    });
  });

  group('ReleaseInfo.fromJson', () {
    test('parses tag and asset digests', () {
      final release = ReleaseInfo.fromJson({
        'tag_name': 'v1.2.3',
        'assets': [
          {
            'name': 'tapster',
            'digest': 'sha256:aaa111',
          },
          {
            'name': 'other',
            'digest': 'sha256:bbb222',
          },
        ],
      });

      expect(release.tagName, 'v1.2.3');
      expect(release.assetDigests['tapster'], 'aaa111');
      expect(release.assetDigests['other'], 'bbb222');
    });

    test('skips assets without digest', () {
      final release = ReleaseInfo.fromJson({
        'tag_name': 'v1.2.3',
        'assets': [
          {
            'name': 'no-digest',
            'digest': null,
          },
          {
            'name': 'with-digest',
            'digest': 'sha256:ccc333',
          },
        ],
      });

      expect(release.assetDigests.containsKey('no-digest'), isFalse);
      expect(release.assetDigests['with-digest'], 'ccc333');
    });

    test('handles empty assets', () {
      final release = ReleaseInfo.fromJson({
        'tag_name': 'v1.2.3',
        'assets': [],
      });

      expect(release.tagName, 'v1.2.3');
      expect(release.assetDigests, isEmpty);
    });
  });
}
