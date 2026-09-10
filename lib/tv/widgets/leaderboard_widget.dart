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
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant LeaderboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.players.length != widget.players.length) {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!_scrollController.hasClients || _isPaused) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      if (maxScroll <= 0) return;

      if (_isScrollingDown) {
        if (currentScroll >= maxScroll - 1) {
          _isPaused = true;
          _isScrollingDown = false;
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted && _scrollController.hasClients) {
              _scrollController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeInOut,
              ).then((_) {
                Future.delayed(const Duration(milliseconds: 2000), () {
                  if (mounted) {
                    _isScrollingDown = true;
                    _isPaused = false;
                  }
                });
              });
            } else {
              _isPaused = false;
            }
          });
        } else {
          _scrollController.jumpTo(currentScroll + 0.8);
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isTop3
            ? rankColors[index].withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isTop3
              ? rankColors[index].withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTop3 ? rankColors[index] : Colors.white12,
            ),
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isTop3 ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              player.nickname.toUpperCase(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${player.cumulativeScore} pts',
            style: TextStyle(
              fontSize: 15,
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
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: AppTheme.neonYellow, size: 24),
              SizedBox(width: 8),
              Text(
                'LIVE LEADERBOARD',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                  color: AppTheme.neonCyan,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 18),
          if (widget.players.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No players joined yet...',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            Expanded(
              child: ShaderMask(
                shaderCallback: (Rect rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.92, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.players.length,
                  itemBuilder: (context, index) {
                    return _buildPlayerCard(widget.players[index], index);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
