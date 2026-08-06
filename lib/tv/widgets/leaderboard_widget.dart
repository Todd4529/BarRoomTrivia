import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/models/player.dart';
import '../../shared/theme/app_theme.dart';

class LeaderboardWidget extends StatefulWidget {
  final List<Player> players;

  const LeaderboardWidget({super.key, required this.players});

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget> {
  late final ScrollController _scrollController;
  Timer? _autoScrollTimer;
  bool _isScrollingDown = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_scrollController.hasClients) return;

      final remainingCount = widget.players.length > 3 ? widget.players.length - 3 : 0;
      if (remainingCount <= 2) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      if (maxScroll <= 0) return;

      if (_isScrollingDown) {
        if (currentScroll >= maxScroll - 2) {
          _isScrollingDown = false;
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && _scrollController.hasClients) {
              _scrollController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
              ).then((_) {
                _isScrollingDown = true;
              });
            }
          });
        } else {
          _scrollController.jumpTo(currentScroll + 1.2);
        }
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildPlayerCard(Player player, int index) {
    final isTop3 = index < 3;
    final rankColors = [
      AppTheme.neonYellow,
      Colors.grey.shade300,
      const Color(0xFFCD7F32), // Bronze
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTop3
            ? rankColors[index].withOpacity(0.12)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3
              ? rankColors[index].withOpacity(0.4)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTop3 ? rankColors[index] : Colors.white12,
            ),
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isTop3 ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              player.nickname.toUpperCase(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${player.cumulativeScore} pts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isTop3 ? rankColors[index] : AppTheme.neonCyan,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top3Players = widget.players.take(3).toList();
    final remainingPlayers = widget.players.length > 3 ? widget.players.sublist(3) : <Player>[];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.emoji_events, color: AppTheme.neonYellow, size: 28),
              SizedBox(width: 10),
              Text(
                'LIVE LEADERBOARD',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppTheme.neonCyan,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),

          if (widget.players.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No players joined yet...',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else ...[
            // Static Top 3 Pinned Cards
            ...List.generate(top3Players.length, (idx) {
              return _buildPlayerCard(top3Players[idx], idx);
            }),

            // Scrollable Remaining Players List (#4 and below)
            if (remainingPlayers.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Divider(color: Colors.white12, height: 16),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: remainingPlayers.length,
                  itemBuilder: (context, index) {
                    return _buildPlayerCard(remainingPlayers[index], index + 3);
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
