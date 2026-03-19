import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/auth_repository.dart';
import '../blocs/dashboard_bloc.dart';
import '../blocs/auth_bloc.dart';
import '../../data/models/favour_models.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';
import 'commitment_portal.dart';
import '../../core/utils/name_utils.dart';

class KizunaDashboard extends StatefulWidget {
  const KizunaDashboard({super.key});

  @override
  State<KizunaDashboard> createState() => _KizunaDashboardState();
}

class _KizunaDashboardState extends State<KizunaDashboard> with TickerProviderStateMixin {
  late AnimationController _scoreGlow;
  late Animation<double> _glowAnim;
  late AnimationController _typewriterController;
  late AnimationController _cursorController;
  late AnimationController _heartbeatController;
  late Animation<double> _heartAnimation;
  String _displayName = "";

  @override
  void initState() {
    super.initState();
    _scoreGlow = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.18).animate(
      CurvedAnimation(parent: _scoreGlow, curve: Curves.easeInOut),
    );

    _typewriterController = AnimationController(vsync: this);
    _cursorController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);

    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _heartAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 70,
      ),
    ]).animate(_heartbeatController);

    // Initial display name from any existing state if needed
    final state = context.read<DashboardBloc>().state;
    _syncDisplayNameState(state);
  }

  void _syncDisplayNameState(DashboardState state) {
    if (state.stats?.name != null) {
      final newName = NameUtils.getFirstName(state.stats!.name);
      if (newName != _displayName) {
        setState(() {
          _displayName = newName;
        });
        final String textToAnimate = "¡HOLA! ${_displayName.toUpperCase()}";
        _typewriterController.duration = Duration(milliseconds: textToAnimate.length * 80);
        _typewriterController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _scoreGlow.dispose();
    _typewriterController.dispose();
    _cursorController.dispose();
    _heartbeatController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('KIZUNA', style: TextStyle(letterSpacing: 6, fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          IconButton(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.power_settings_new_rounded, color: KizunaTheme.primaryBlue, size: 22),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient background orbs
          const RepaintBoundary(
            child: _KizunaDashboardBackground(),
          ),
          BlocListener<DashboardBloc, DashboardState>(
            listener: (context, state) {
              if (state.pendingActions.isNotEmpty) {
                _showHandshakeNotification(context, state.pendingActions.last);
              }
              // Keep display name in sync with BLoC stats
              _syncDisplayNameState(state);
            },
            child: BlocBuilder<DashboardBloc, DashboardState>(
              builder: (context, state) {
                final stats = state.stats;
                return SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      RepaintBoundary(
                        child: _buildGreeting(context, stats?.name),
                      ),
                      const SizedBox(height: 6),
                      RepaintBoundary(
                        child: _buildReciprocityHeart(state.reciprocityScore, stats?.karmaScore ?? 1.0),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: state.isLoadingStats && stats == null
                            ? const Center(child: CircularProgressIndicator())
                            : stats == null
                                ? const Center(child: Text('Failed to load stats', style: TextStyle(color: Colors.white38)))
                                : RepaintBoundary(child: _buildStatsContent(stats)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReciprocityHeart(double reciprocityScore, double karmaScore) {
    Color heartColor = KizunaTheme.getKarmaColor(karmaScore);
    String status;

    if (reciprocityScore > 60) {
      status = 'PROVIDER';
    } else if (reciprocityScore >= 40) {
      status = 'BALANCED';
    } else {
      status = 'RECEIVER';
    }

    return Column(
      children: [
        SizedBox(
          width: 220,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Glowing Backdrop
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (context, child) {
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: heartColor.withValues(alpha: _glowAnim.value),
                          blurRadius: 25,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  );
                },
              ),
              // The Heart (Heartbeat Animation)
              ScaleTransition(
                scale: _heartAnimation,
                child: ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      heartColor,
                      heartColor.withValues(alpha: 0.7),
                    ],
                  ).createShader(bounds),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 100,
                    color: Colors.white,
                  ),
                ),
              ),
              // Info Button
              Positioned(
                top: -8,
                right: -8,
                child: IconButton(
                  onPressed: () => _showAlgorithmInfo(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.info_outline, size: 14, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Label & Info
        Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: heartColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: heartColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w900,
                  color: heartColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              KizunaTheme.getKarmaDescription(karmaScore),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAlgorithmInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KizunaTheme.primaryBlue.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.auto_awesome_outlined, color: KizunaTheme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 16),
            const Text('KARMA ALGO', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Karma Score represents your total social contribution based on favours and points, with diminishing returns as you grow.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            _buildAlgoRule('📈', 'GROWTH', 'Early efforts count more. It gets harder to reach 100!'),
            const SizedBox(height: 16),
            _buildAlgoRule('🌈', 'SPECTRUM', 'Heart color shifts: 🔴 (1) → 🟡 (25) → 🟢 (50) → 🔵 (75) → 🟣 (100)'),
            const SizedBox(height: 16),
            _buildAlgoRule('⚖️', 'RECIPROCITY', 'Status (Provider/Receiver) shows your net contribution.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('GOT IT', style: TextStyle(color: KizunaTheme.primaryBlue, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlgoRule(String emoji, String label, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsContent(ProfileStats stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildStatCard('TOTAL FAVOURS', stats.totalFavoursGiven, stats.totalFavoursReceived, stats.netFavours),
          const SizedBox(height: 12),
          _buildStatCard('TOTAL POINTS', stats.totalPointsGiven, stats.totalPointsReceived, stats.netPoints),
          const SizedBox(height: 16),
          _buildInfoMessage(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int given, int received, int net) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), // Reduced vertical padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (net >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NET: ${net >= 0 ? "+" : ""}$net',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: net >= 0 ? Colors.green : Colors.redAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatItem('GIVEN', given, Colors.green),
              const SizedBox(width: 60),
              _buildStatItem('RECEIVED', received, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildInfoMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KizunaTheme.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KizunaTheme.primaryBlue.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: KizunaTheme.primaryBlue, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Your reciprocity score is a reflection of your social integrity across all connections.',
              style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showHandshakeNotification(BuildContext context, dynamic action) {
    final bool isFriendRequest = action is Map && action['type'] == 'friend_request';
    final String title = isFriendRequest ? 'FRIEND REQUEST' : 'DOUBLE HANDSHAKE';
    final String message = isFriendRequest 
        ? '${action['data']?['initiator_name'] ?? 'Someone'} wants to connect.'
        : '${action['entity_name'] ?? 'New Commitment'} proposal received.';
    final IconData icon = isFriendRequest ? Icons.person_add_outlined : Icons.handshake_outlined;

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        elevation: 10,
        backgroundColor: Colors.transparent,
        content: GlassContainer(
          borderRadius: 16,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KizunaTheme.primaryBlue.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: KizunaTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(message,
                        style: const TextStyle(fontSize: 13, color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              if (isFriendRequest) {
                 // Forward to Friends tab or handled by screen navigation
                 // For now, just hide is fine as it's already in the list
              } else {
                final commitmentId = action['id'] ?? action['data']?['id'];
                if (commitmentId != null) {
                  context.read<DashboardBloc>().add(AcceptCommitment(commitmentId));
                }
              }
            },
            child: Text(isFriendRequest ? 'VIEW' : 'ACCEPT', style: TextStyle(color: KizunaTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              final commitmentId = action['id'] ?? action['data']?['id'];
              if (commitmentId != null && !isFriendRequest) {
                context.read<DashboardBloc>().add(DenyCommitment(commitmentId));
              }
            },
            child: Text(isFriendRequest ? 'DISMISS' : 'DECLINE', style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KizunaTheme.surfaceGlass,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white10)),
        title: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(LogoutRequested());
            },
            child: const Text('LOGOUT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting(BuildContext context, String? statsName) {
    final state = context.watch<AuthBloc>().state;
    String name = "";
    if (state is Authenticated) {
      name = state.userName;
    }
    
    // Fallback to name from stats if AuthBloc is empty
    if (name.isEmpty && statsName != null) {
      name = statsName;
    }

    final String shortName = NameUtils.getFirstName(name.isNotEmpty ? name : _displayName);
    final String fullText = shortName.isNotEmpty ? "¡HOLA! ${shortName.toUpperCase()}" : "¡HOLA!";
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _typewriterController,
              builder: (context, child) {
                final int characterCount = (_typewriterController.value * fullText.length).floor();
                return Flexible(
                  child: Text(
                    fullText.substring(0, characterCount),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                      color: KizunaTheme.primaryBlue,
                    ),
                  ),
                );
              },
            ),
            // Blinking Cursor
            AnimatedBuilder(
              animation: _cursorController,
              builder: (context, child) {
                return Opacity(
                  opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                  child: Container(
                    width: 2,
                    height: 24,
                    color: KizunaTheme.primaryBlue,
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _KizunaDashboardBackground extends StatelessWidget {
  const _KizunaDashboardBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildOrb(KizunaTheme.primaryBlue, 0.05, const Alignment(-0.8, -0.6)),
        _buildOrb(KizunaTheme.primaryPurple, 0.03, const Alignment(0.8, 0.4)),
      ],
    );
  }

  Widget _buildOrb(Color color, double opacity, Alignment alignment) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: alignment,
            colors: [
              color.withValues(alpha: opacity),
              Colors.transparent,
            ],
            radius: 1.2,
          ),
        ),
      ),
    );
  }
}
