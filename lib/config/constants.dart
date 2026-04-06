/// App-wide constants
class AppConstants {
  AppConstants._();

  // ─── Supabase ───
  static const String supabaseUrl = 'https://kksqdyylahmfaiyhpcga.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_dGqHrkm9TO7uCeFWPGZfBw_Liqoe0sY';

  // ─── API Base URL ───
  static const String baseUrl = 'https://gottesdienst.vercel.app';

  // ─── Legacy Groq Whisper Proxy (kept for compatibility) ───
  static const String transcribeUrl = '$baseUrl/api/transcribe';

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

  // ─── VPS Audio Service (Hetzner) ───
  static const String ytAudioServiceUrl = 'http://5.75.154.45';
  static const String ytAudioApiKey = 'LN2285jE-ILVSkERWsvUk_G5ZLKcusHcnEAKg3MSbFQ';

  // ─── Transcription ───
  static const int transcriptionIntervalMs = 4000;
  static const int maxTranscriptLines = 5;
  static const String defaultLanguage = 'de';

  // ─── Auto-rotate hero interval ───
  static const int heroRotateIntervalSec = 30;
}

class YouTubeChannel {
  final String id;
  final String name;

  const YouTubeChannel({required this.id, required this.name});
}
