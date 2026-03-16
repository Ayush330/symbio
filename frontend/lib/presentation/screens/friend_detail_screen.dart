import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../widgets/glass_container.dart';
import 'favour_detail_screen.dart';

class FriendDetailScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  final double health;

  const FriendDetailScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.health,
  });

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  List<dynamic> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    try {
      final repo = context.read<FriendsRepository>();
      final activities = await repo.getFriendActivity(widget.friendId);
      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color get _healthColor {
    if (widget.health > 50) return const Color(0xFF00E676);
    if (widget.health > 0) return const Color(0xFFFFD740);
    if (widget.health > -30) return const Color(0xFFFF9100);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.friendName.toUpperCase(),
            style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: SymbioTheme.backgroundBlack)),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildHealthGauge(),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Text('ACTIVITY TIMELINE',
                          style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
                      const Spacer(),
                      Text('${_activities.length} events',
                          style: TextStyle(fontSize: 12, color: Colors.white24)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _activities.isEmpty
                          ? _buildEmptyActivity()
                          : _buildActivityList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthGauge() {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.favorite,
            color: _healthColor,
            size: 80,
            shadows: [
              Shadow(
                color: _healthColor.withOpacity(0.5),
                blurRadius: 40,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.health.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: _healthColor,
              letterSpacing: -2,
            ),
          ),
          Text(
            'CONNECTION SCORE',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 4,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showCreateFavourDialog(),
            icon: const Icon(Icons.add, color: Colors.black),
            label: const Text('CREATE FAVOUR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SymbioTheme.primaryBlue,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFavourDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SymbioTheme.surfaceGlass,
        title: const Text('New Favour', style: TextStyle(color: Colors.white, letterSpacing: 2)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g., Helped with interview prep',
            hintStyle: TextStyle(color: Colors.white24),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await context.read<FriendsRepository>().createFavour(widget.friendId, controller.text);
                Navigator.pop(context);
                _loadActivity(); // Refresh list
              }
            },
            child: const Text('SEND', style: TextStyle(color: SymbioTheme.primaryBlue)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyActivity() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline_outlined, size: 48, color: Colors.white10),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: TextStyle(color: Colors.white30, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a commitment to see your timeline grow.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        final f = _activities[index];
        final bool isGiven = f['initiator_id'] != widget.friendId;
        final Color baseColor = isGiven ? Colors.green : Colors.red;
        final int points = f['points'] ?? 10;
        final double opacity = (points / 50).clamp(0.3, 1.0);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FavourDetailScreen(favour: f)),
            ),
            child: GlassContainer(
              padding: const EdgeInsets.all(16),
              borderColor: baseColor.withOpacity(opacity),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['text'] ?? 'Legacy Commitment',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${f['category']?.toUpperCase() ?? 'OTHER'} • ${f['created_at'].toString().substring(0, 10)}',
                          style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4), letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${isGiven ? "+" : "-"}$points',
                    style: TextStyle(
                      color: baseColor.withOpacity(opacity),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACKNOWLEDGED':
        return const Color(0xFF00E676);
      case 'PENDING':
        return const Color(0xFFFFD740);
      case 'DENIED':
      case 'FLAKED':
        return const Color(0xFFFF5252);
      default:
        return Colors.white38;
    }
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _statusColor(status), letterSpacing: 0.5),
      ),
    );
  }
}
