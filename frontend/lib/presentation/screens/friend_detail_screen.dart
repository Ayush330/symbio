import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../widgets/glass_container.dart';

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
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _healthColor.withOpacity(0.15),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: CircularProgressIndicator(
                value: (widget.health.abs() / 100).clamp(0.0, 1.0),
                strokeWidth: 6,
                backgroundColor: Colors.white10,
                color: _healthColor,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.health.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: _healthColor,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  'HEALTH',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        final activity = _activities[index];
        final isLast = index == _activities.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line + dot
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor(activity['status'] ?? ''),
                        boxShadow: [
                          BoxShadow(
                            color: _statusColor(activity['status'] ?? '').withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: Colors.white10,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Activity card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                activity['entity_name'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _buildStatusChip(activity['status'] ?? ''),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              activity['entity_type'] == 'MATERIAL'
                                  ? Icons.monetization_on_outlined
                                  : Icons.favorite_outline,
                              size: 14,
                              color: Colors.white30,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              activity['entity_type'] ?? '',
                              style: TextStyle(fontSize: 11, color: Colors.white30, letterSpacing: 1),
                            ),
                            const Spacer(),
                            Text(
                              'Rating: ${activity['rating'] ?? 0}',
                              style: TextStyle(fontSize: 12, color: SymbioTheme.primaryBlue.withOpacity(0.7)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'by ${activity['initiator_name'] ?? 'Unknown'}',
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.2)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
