import 'package:tapster/utils/repo_utils.dart';
import 'package:test/test.dart';

void main() {
  group('parseRepoString', () {
    test('parses https URL', () {
      expect(
        parseRepoString('https://github.com/owner/repo'),
        ('owner', 'repo'),
      );
    });

    test('parses https URL with .git suffix', () {
      expect(
        parseRepoString('https://github.com/owner/repo.git'),
        ('owner', 'repo'),
      );
    });

    test('parses ssh URL', () {
      expect(
        parseRepoString('git@github.com:owner/repo.git'),
        ('owner', 'repo'),
      );
    });

    test('rejects URLs without owner/repo', () {
      expect(
        () => parseRepoString('https://github.com/single'),
        throwsFormatException,
      );
    });
  });

  group('resolveTapRepo', () {
    test('adds homebrew- prefix to tap name', () {
      expect(
        resolveTapRepo('CalsRanna/inspire'),
        ('CalsRanna', 'homebrew-inspire'),
      );
    });

    test('keeps existing homebrew- prefix', () {
      expect(
        resolveTapRepo('CalsRanna/homebrew-inspire'),
        ('CalsRanna', 'homebrew-inspire'),
      );
    });

    test('rejects taps without owner', () {
      expect(
        () => resolveTapRepo('inspire'),
        throwsFormatException,
      );
    });
  });

  group('defaultTapName', () {
    test('returns owner/tap for the shared tap', () {
      expect(defaultTapName('CalsRanna'), 'CalsRanna/tap');
    });

    test('resolves to the homebrew- prefixed repository', () {
      final tap = defaultTapName('CalsRanna');
      expect(resolveTapRepo(tap), ('CalsRanna', 'homebrew-tap'));
    });
  });

  group('defaultBucketName', () {
    test('returns owner/scoop-bucket', () {
      expect(defaultBucketName('CalsRanna'), 'CalsRanna/scoop-bucket');
    });
  });
}
