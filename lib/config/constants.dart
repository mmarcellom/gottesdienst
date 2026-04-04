/// App-wide constants
class AppConstants {
  AppConstants._();

  // ─── Supabase ───
  static const String supabaseUrl = 'https://kksqdyylahmfaiyhpcga.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_dGqHrkm9TO7uCeFWPGZfBw_Liqoe0sY';

  // ─── Groq Whisper Proxy (Vercel) ───
  static const String transcribeUrl = 'https://gottesdienst.vercel.app/api/transcribe';

  // ─── YouTube Channels ───
  static const List<YouTubeChannel> channels = [
    YouTubeChannel(
      id: 'UClwRpYWCJg4gjBN7jGS1YQg',
      name: 'MKSB Berlin',
    ),
    YouTubeChannel(
      id: 'UCe5RLZXC8gLthqHDlfSEcQg',
      name: 'German Translation',
    ),
    YouTubeChannel(
      id: 'UCT1daN9Wn27s2QnmCJfzj9g',
      name: 'KwaSizabantu Mission',
    ),
    YouTubeChannel(
      id: 'UCfGfpoL_rXoPkkp6HH1y-2g',
      name: 'Kwasizabantu Romania',
    ),
  ];

  // ─── Transcription ───
  static const int transcriptionIntervalMs = 4000;
  static const int maxTranscriptLines = 5;
  static const String defaultLanguage = 'de';

  // ─── Auto-rotate hero interval ───
  static const int heroRotateIntervalSec = 8;
}

class YouTubeChannel {
  final String id;
  final String name;

  const YouTubeChannel({required this.id, required this.name});
}
