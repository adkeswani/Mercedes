import 'package:flutter_test/flutter_test.dart';
import 'package:stage4/features/exercises/domain/youtube_url.dart';

void main() {
  group('extractYoutubeId', () {
    const id = 'dQw4w9WgXcQ';

    test('parses standard watch URLs', () {
      expect(extractYoutubeId('https://www.youtube.com/watch?v=$id'), id);
      expect(extractYoutubeId('https://youtube.com/watch?v=$id&t=30s'), id);
      expect(extractYoutubeId('http://m.youtube.com/watch?v=$id'), id);
    });

    test('parses short youtu.be URLs', () {
      expect(extractYoutubeId('https://youtu.be/$id'), id);
      expect(extractYoutubeId('https://youtu.be/$id?t=10'), id);
    });

    test('parses embed, shorts, and /v/ URLs', () {
      expect(extractYoutubeId('https://www.youtube.com/embed/$id'), id);
      expect(extractYoutubeId('https://www.youtube.com/shorts/$id'), id);
      expect(extractYoutubeId('https://www.youtube.com/v/$id'), id);
    });

    test('parses youtube-nocookie URLs', () {
      expect(
          extractYoutubeId('https://www.youtube-nocookie.com/embed/$id'), id);
    });

    test('returns null for non-YouTube URLs', () {
      expect(extractYoutubeId('https://vimeo.com/123456'), isNull);
      expect(extractYoutubeId('https://example.com/watch?v=$id'), isNull);
      expect(extractYoutubeId('not a url at all'), isNull);
      expect(extractYoutubeId(''), isNull);
    });

    test('returns null when the id is malformed', () {
      expect(extractYoutubeId('https://youtu.be/short'), isNull);
      expect(extractYoutubeId('https://www.youtube.com/watch?v='), isNull);
    });

    test('isYoutubeUrl mirrors extractYoutubeId', () {
      expect(isYoutubeUrl('https://youtu.be/$id'), isTrue);
      expect(isYoutubeUrl('https://vimeo.com/123456'), isFalse);
    });
  });
}
