import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../blocs/friends_bloc.dart';
import '../widgets/glass_container.dart';
import 'commitment_portal.dart';
import 'favour_detail_screen.dart';

class FriendDetailScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String friendEmail;
  final double health;

  const FriendDetailScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.friendEmail,
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

  @override
  Widget build(BuildContext context) {
    return BlocListener<FriendsBloc, FriendsState>(
      listener: (context, state) {
        if (state is FriendsLoaded) {
          _loadActivity();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(widget.friendName.toUpperCase(),
              style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F0F1E),
                      KizunaTheme.primaryBlue.withOpacity(0.05),
                      const Color(0xFF0F0F1E),
                    ],
                  ),
                ),
              ),
            ),
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: KizunaTheme.primaryBlue))
                : SafeArea(
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
                                  style: const TextStyle(fontSize: 12, color: Colors.white24)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _activities.isEmpty
                              ? _buildEmptyActivity()
                              : _buildActivityList(),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthGauge() {
    return BlocBuilder<FriendsBloc, FriendsState>(
      builder: (context, state) {
        double currentHealth = widget.health;
        if (state is FriendsLoaded) {
          final friend = state.friends.firstWhere(
            (f) => f['id'] == widget.friendId,
            orElse: () => null,
          );
          if (friend != null) {
            currentHealth = (friend['karma_score'] as num?)?.toDouble() ?? currentHealth;
          }
        }

        return Column(
          children: [
            Icon(
              Icons.favorite,
              color: KizunaTheme.getKarmaColor(currentHealth),
              size: 80,
              shadows: [
                Shadow(
                  color: KizunaTheme.getKarmaColor(currentHealth).withOpacity(0.5),
                  blurRadius: 40,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              currentHealth.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: KizunaTheme.getKarmaColor(currentHealth),
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
              onPressed: () => _showCreateFavourPortal(),
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('CREATE FAVOUR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KizunaTheme.primaryBlue,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCreateFavourPortal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommitmentPortal(
        initialEmail: widget.friendEmail,
        targetUserId: widget.friendId,
      ),
    ).then((_) => _loadActivity());
  }

  Widget _buildEmptyActivity() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timeline_outlined, size: 48, color: Colors.white10),
          const SizedBox(height: 16),
          const Text(
            'No activity yet',
            style: TextStyle(color: Colors.white30, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a commitment to see your timeline grow.',
            style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 12),
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
}
