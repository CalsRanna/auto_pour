import 'package:tapster/services/git_service.dart';
import 'package:test/test.dart';

void main() {
  group('GitService.stripVersionPrefix', () {
    test('strips leading v from tag', () {
      expect(GitService.stripVersionPrefix('v1.2.3'), '1.2.3');
    });

    test('keeps tags without v prefix', () {
      expect(GitService.stripVersionPrefix('1.2.3'), '1.2.3');
    });

    test('handles pre-release tags', () {
      expect(GitService.stripVersionPrefix('v1.2.3-beta.1'), '1.2.3-beta.1');
    });

    test('handles build metadata', () {
      expect(GitService.stripVersionPrefix('v1.2.3+build.5'), '1.2.3+build.5');
    });

    test('empty tag stays empty', () {
      expect(GitService.stripVersionPrefix(''), '');
    });
  });
}
