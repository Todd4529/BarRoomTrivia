import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../data/trivia_repository.dart';
import '../models/question.dart';

/// Silent background service that checks and syncs weekly internet trivia questions.
/// Runs completely automatically on app launch with zero user intervention required.
class WeeklyTriviaSyncService {
  static const String _lastSyncKey = 'last_weekly_trivia_sync_timestamp';
  static const String _cachedQuestionsKey = 'cached_weekly_dynamic_questions';
  static const int _syncIntervalDays = 7;

  /// Background initialization called on app launch without blocking UI
  static Future<void> initializeBackgroundSync() async {
    try {
      // 1. Immediately load cached dynamic questions into TriviaRepository for offline play
      await _loadOfflineDynamicQuestions();

      // 2. Check if a weekly sync is due (> 7 days since last sync)
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString(_lastSyncKey);
      
      bool isDue = true;
      if (lastSyncStr != null) {
        final lastSyncDate = DateTime.tryParse(lastSyncStr);
        if (lastSyncDate != null) {
          final diff = DateTime.now().difference(lastSyncDate);
          if (diff.inDays < _syncIntervalDays) {
            isDue = false;
          }
        }
      }

      if (!isDue) {
        debugPrint('[WeeklyTriviaSyncService] Weekly trivia is up to date (last sync: $lastSyncStr).');
        return;
      }

      debugPrint('[WeeklyTriviaSyncService] Starting automatic weekly trivia background check...');

      // 3. Attempt silent fetch from Supabase
      List<Question> freshQuestions = [];
      try {
        final client = SupabaseConfig.client;
        final response = await client
            .from('questions')
            .select()
            .order('created_at', ascending: false)
            .limit(150)
            .timeout(const Duration(seconds: 4));

        if (response.isNotEmpty) {
          freshQuestions = response.map((item) => Question.fromJson(item)).toList();
          debugPrint('[WeeklyTriviaSyncService] Fetched ${freshQuestions.length} questions from Supabase.');
        }
      } catch (sbErr) {
        debugPrint('[WeeklyTriviaSyncService] Supabase query skipped/unavailable: $sbErr');
      }

      // 4. Fallback to GitHub Pages raw trivia pack if Supabase was empty/unreachable
      if (freshQuestions.isEmpty) {
        try {
          const packUrl = 'https://raw.githubusercontent.com/Todd4529/BarRoomTrivia/master/public/data/weekly_trivia_pack.json';
          final res = await http.get(Uri.parse(packUrl)).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final dynamic data = jsonDecode(res.body);
            if (data is List) {
              freshQuestions = data.map((item) => Question.fromJson(item as Map<String, dynamic>)).toList();
              debugPrint('[WeeklyTriviaSyncService] Fetched ${freshQuestions.length} questions from weekly pack CDN.');
            }
          }
        } catch (cdnErr) {
          debugPrint('[WeeklyTriviaSyncService] CDN pack fetch skipped: $cdnErr');
        }
      }

      // 5. Ingest fresh questions and update cache
      if (freshQuestions.isNotEmpty) {
        TriviaRepository.injectQuestions(freshQuestions);
        await _saveDynamicQuestionsToCache(prefs, freshQuestions);
        await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
        debugPrint('[WeeklyTriviaSyncService] Automatic sync complete: ${freshQuestions.length} questions added to game bank.');
      } else {
        // Even if network was unavailable, update timestamp so we don't spam network on every resume
        await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      }
    } catch (e) {
      debugPrint('[WeeklyTriviaSyncService] Error during silent background sync: $e');
    }
  }

  /// Loads bundled asset pack and cached dynamic questions into memory
  static Future<void> _loadOfflineDynamicQuestions() async {
    try {
      final List<Question> questions = [];
      final Set<String> seenTexts = {};

      // 1. Always load the comprehensive bundled asset pack (3,400+ real questions)
      try {
        final assetData = await rootBundle.loadString('assets/data/weekly_trivia_pack.json');
        final dynamic decodedAsset = jsonDecode(assetData);
        if (decodedAsset is List) {
          for (final item in decodedAsset) {
            final q = Question.fromJson(item as Map<String, dynamic>);
            final textLower = q.questionText.trim().toLowerCase();
            if (!seenTexts.contains(textLower)) {
              seenTexts.add(textLower);
              questions.add(q);
            }
          }
        }
      } catch (assetErr) {
        debugPrint('[WeeklyTriviaSyncService] Note on asset pack read: $assetErr');
      }

      // 2. Also merge any freshly synced questions saved in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cachedQuestionsKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final dynamic decoded = jsonDecode(cachedJson);
        if (decoded is List) {
          for (final item in decoded) {
            final q = Question.fromJson(item as Map<String, dynamic>);
            final textLower = q.questionText.trim().toLowerCase();
            if (!seenTexts.contains(textLower)) {
              seenTexts.add(textLower);
              questions.insert(0, q);
            }
          }
        }
      }

      if (questions.isNotEmpty) {
        TriviaRepository.injectQuestions(questions);
        debugPrint('[WeeklyTriviaSyncService] Loaded ${questions.length} real dynamic questions into memory.');
      }
    } catch (err) {
      debugPrint('[WeeklyTriviaSyncService] Failed to load offline dynamic questions: $err');
    }
  }

  /// Persists dynamic questions to SharedPreferences (keeping up to 500 recent questions)
  static Future<void> _saveDynamicQuestionsToCache(SharedPreferences prefs, List<Question> newQuestions) async {
    try {
      final cachedJson = prefs.getString(_cachedQuestionsKey);
      List<dynamic> existingList = [];
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson);
          if (decoded is List) existingList = decoded;
        } catch (_) {}
      }

      final existingTexts = existingList.map((e) => (e['question_text'] ?? '').toString().toLowerCase()).toSet();

      for (final q in newQuestions) {
        final textLower = q.questionText.toLowerCase();
        if (!existingTexts.contains(textLower)) {
          existingTexts.add(textLower);
          existingList.insert(0, q.toJson());
        }
      }

      // Cap at 500 questions in local cache
      final trimmed = existingList.take(500).toList();
      await prefs.setString(_cachedQuestionsKey, jsonEncode(trimmed));
    } catch (err) {
      debugPrint('[WeeklyTriviaSyncService] Failed to save questions to cache: $err');
    }
  }
}
