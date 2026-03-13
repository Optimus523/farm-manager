import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Helper class to safely access environment variables.
/// Handles the case where dotenv may not be initialized (production builds).
class EnvHelper {
  static bool _dotenvInitialized = false;

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _googleWebClient = String.fromEnvironment('GOOGLE_WEB_CLIENT');
  static const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _featherlessApiKey = String.fromEnvironment(
    'FEATHERLESS_API_KEY',
  );
  static const _baseUrl = String.fromEnvironment('BASE_URL');

  /// Mark dotenv as initialized (call after successful dotenv.load())
  static void markDotenvInitialized() {
    _dotenvInitialized = true;
  }

  /// Check if dotenv was successfully loaded
  static bool get isDotenvInitialized => _dotenvInitialized;

  /// Safely get an environment variable.
  /// First checks compile-time value (--dart-define), then falls back to dotenv.
  static String? get(String key) {
    // First, try compile-time environment variable
    final compileTimeValue = _getCompileTimeValue(key);
    if (compileTimeValue != null && compileTimeValue.isNotEmpty) {
      return compileTimeValue;
    }

    // Fall back to dotenv if it was loaded
    if (_dotenvInitialized) {
      try {
        return dotenv.env[key];
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Get compile-time value for known keys
  static String? _getCompileTimeValue(String key) {
    switch (key) {
      case 'SUPABASE_URL':
        return _supabaseUrl.isNotEmpty ? _supabaseUrl : null;
      case 'SUPABASE_ANON_KEY':
        return _supabaseAnonKey.isNotEmpty ? _supabaseAnonKey : null;
      case 'GOOGLE_WEB_CLIENT':
        return _googleWebClient.isNotEmpty ? _googleWebClient : null;
      case 'GEMINI_API_KEY':
        return _geminiApiKey.isNotEmpty ? _geminiApiKey : null;
      case 'FEATHERLESS_API_KEY':
        return _featherlessApiKey.isNotEmpty ? _featherlessApiKey : null;
      case 'BASE_URL':
        return _baseUrl.isNotEmpty ? _baseUrl : null;
      default:
        return null;
    }
  }

  /// Get environment variable with a default value
  static String getOrDefault(String key, String defaultValue) {
    return get(key) ?? defaultValue;
  }
}
