import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../blocs/friends_bloc.dart';
import '../widgets/glass_container.dart';
import '../widgets/kizuna_button.dart';
import 'friend_detail_screen.dart';
import 'invite_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    context.read<FriendsBloc>().add(LoadFriends());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CONNECTIONS', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InviteScreen()),
        ),
        backgroundColor: KizunaTheme.accentCyan,
        child: const Icon(Icons.person_add_alt_1, color: Colors.black),
      ),
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Container(color: KizunaTheme.backgroundBlack),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KizunaTheme.primaryBlue.withOpacity(0.04),
              ),
            ),
          ),
          BlocBuilder<FriendsBloc, FriendsState>(
            builder: (context, state) {
              if (state is FriendsLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is FriendsEmpty || state is FriendsInitial) {
                return _buildEmptyState();
              }
              if (state is FriendsLoaded) {
                return _buildContent(state.friends, state.requests);
              }
              if (state is FriendsError) {
                return Center(
                  child: Text('Something went wrong', style: TextStyle(color: Colors.white38)),
                );
              }
              return _buildEmptyState();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _pulseAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          KizunaTheme.primaryBlue.withOpacity(0.15),
                          KizunaTheme.primaryBlue.withOpacity(0.02),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.people_outline_rounded,
                      size: 56,
                      color: KizunaTheme.primaryBlue.withOpacity(0.4),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              "It's a little lonely in here...",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.6),
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Invite someone to start your Kizuna journey together.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.3),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 220,
              child: KizunaButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InviteScreen()),
                ),
                icon: Icons.send_rounded,
                label: 'INVITE SOMEONE',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<dynamic> friends, List<dynamic> requests) {
    return ListView(
      padding: const EdgeInsets.only(top: 120, left: 24, right: 24, bottom: 100),
      physics: const BouncingScrollPhysics(),
      children: [
        if (requests.isNotEmpty) ...[
          const Text(
            'FRIEND REQUESTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 16),
          ...requests.map((req) => _buildRequestItem(req)),
          const SizedBox(height: 32),
        ],
        if (friends.isNotEmpty) ...[
          const Text(
            'CONNECTIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 16),
          ...friends.map((friend) => _buildFriendItem(friend)),
        ] else if (requests.isEmpty) ...[
          // Only show empty state if both friends and requests are empty
          // (Handled by Bloc emitting FriendsEmpty instead)
        ],
      ],
    );
  }

  Widget _buildRequestItem(dynamic req) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KizunaTheme.accentCyan.withOpacity(0.1),
                border: Border.all(color: KizunaTheme.accentCyan.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  (req['name'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: KizunaTheme.accentCyan,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wants to connect',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => context.read<FriendsBloc>().add(AcceptFriendRequest(req['relationship_id'])),
                  icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 24,
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => context.read<FriendsBloc>().add(RejectFriendRequest(req['relationship_id'])),
                  icon: const Icon(Icons.cancel_rounded, color: Color(0xFFFF5252)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 24,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendItem(dynamic friend) {
    final karma = (friend['karma_score'] as num?)?.toDouble() ?? 1.0;
    final healthColor = KizunaTheme.getKarmaColor(karma);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FriendDetailScreen(
              friendId: friend['id'],
              friendName: friend['name'] ?? 'Unknown',
              friendEmail: friend['email'] ?? '',
              health: karma,
            ),
          ),
        ),
        child: GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Heart icon with health color
              Icon(
                Icons.favorite,
                color: healthColor,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      friend['email'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
              // Health score badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: healthColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: healthColor.withOpacity(0.3)),
                ),
                child: Text(
                  karma.toStringAsFixed(0),
                  style: TextStyle(
                    color: healthColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
