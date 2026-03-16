import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/dashboard_bloc.dart';
import '../blocs/auth_bloc.dart';
import '../../data/models/favour_models.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';
import 'commitment_portal.dart';

class SymbiosisDashboard extends StatefulWidget {
  const SymbiosisDashboard({super.key});

  @override
  State<SymbiosisDashboard> createState() => _SymbiosisDashboardState();
}

class _SymbiosisDashboardState extends State<SymbiosisDashboard> with TickerProviderStateMixin {
  late AnimationController _scoreGlow;
  late Animation<double> _glowAnim;
  ProfileStats? _stats;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _scoreGlow = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.18).animate(
      CurvedAnimation(parent: _scoreGlow, curve: Curves.easeInOut),
    );
    _loadStats();
  }

  @override
  void dispose() {
    _scoreGlow.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final repo = context.read<FriendsRepository>();
      final data = await repo.getProfileStats();
      if (mounted) {
        setState(() {
          _stats = ProfileStats.fromJson(data);
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('SYMBIO', style: TextStyle(letterSpacing: 6, fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          IconButton(
            onPressed: () => _showCommitmentPortal(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SymbioTheme.primaryBlue.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.add, color: SymbioTheme.primaryBlue, size: 22),
            ),
          ),
          IconButton(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded, color: Colors.white38, size: 22),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient background orbs
          Positioned.fill(child: Container(color: SymbioTheme.backgroundBlack)),
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  SymbioTheme.primaryBlue.withValues(alpha: 0.06),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  SymbioTheme.accentCyan.withValues(alpha: 0.04),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          BlocListener<DashboardBloc, DashboardState>(
            listener: (context, state) {
              if (state.pendingActions.isNotEmpty) {
                _showHandshakeNotification(context, state.pendingActions.last);
              }
            },
            child: BlocBuilder<DashboardBloc, DashboardState>(
              builder: (context, state) {
                return SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildReciprocityHeart(state.reciprocityScore),
                      const SizedBox(height: 32),
                      Expanded(
                        child: _isLoadingStats
                            ? const Center(child: CircularProgressIndicator())
                            : _stats == null
                                ? const Center(child: Text('Failed to load stats', style: TextStyle(color: Colors.white38)))
                                : _buildStatsContent(),
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

  Widget _buildReciprocityHeart(double score) {
    Color heartColor;
    String status;

    if (score > 60) {
      heartColor = const Color(0xFF00E676); // Healthy Green
      status = 'PROVIDER';
    } else if (score >= 40) {
      heartColor = SymbioTheme.primaryBlue; // Balanced Blue
      status = 'BALANCED';
    } else {
      heartColor = const Color(0xFFFF9100); // Indebted Orange/Red
      status = 'RECEIVER';
    }

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Glowing Backdrop
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: heartColor.withValues(alpha: _glowAnim.value),
                    blurRadius: 60,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
            // The Heart
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        heartColor,
                        heartColor.withValues(alpha: 0.7),
                      ],
                    ).createShader(bounds),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 140,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            // Label & Info
            Positioned(
              bottom: 20,
              child: Column(
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
                ],
              ),
            ),
            // Info Button
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: () => _showAlgorithmInfo(context),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white10),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: const Icon(Icons.info_outline, size: 14, color: Colors.white38),
                ),
              ),
            ),
          ],
        );
      },
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
                color: SymbioTheme.primaryBlue.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.auto_awesome_outlined, color: SymbioTheme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 16),
            const Text('KARMA ALGO', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAlgoRule('💚', 'PROVIDER', 'Score > 60. You are a social legend! You have given more than you have taken. Go ahead, ask for a favour!'),
            const SizedBox(height: 16),
            _buildAlgoRule('💙', 'BALANCED', 'Score 40-60. Perfect symbiosis. You are in harmony with your tribe.'),
            const SizedBox(height: 16),
            _buildAlgoRule('🟠', 'RECEIVER', 'Score < 40. You are currently indebted. Your social credit is low—time to give back and earn some karma points!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('GOT IT', style: TextStyle(color: SymbioTheme.primaryBlue, fontWeight: FontWeight.bold, letterSpacing: 1)),
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

  Widget _buildStatsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildStatCard('TOTAL FAVOURS', _stats!.totalFavoursGiven, _stats!.totalFavoursReceived),
          const SizedBox(height: 24),
          _buildStatCard('TOTAL POINTS', _stats!.totalPointsGiven, _stats!.totalPointsReceived),
          const SizedBox(height: 32),
          _buildInfoMessage(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int given, int received) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatItem('GIVEN', given, Colors.green),
              const SizedBox(width: 40),
              _buildStatItem('RECEIVED', received, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        color: SymbioTheme.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SymbioTheme.primaryBlue.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: SymbioTheme.primaryBlue, size: 20),
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
                  color: SymbioTheme.primaryBlue.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.handshake_outlined, color: SymbioTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('DOUBLE HANDSHAKE',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${action['entity_name'] ?? 'New Commitment'} proposal received.',
                        style: TextStyle(fontSize: 13, color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: Text('ACCEPT', style: TextStyle(color: SymbioTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('DECLINE', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SymbioTheme.surfaceGlass,
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

  void _showCommitmentPortal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) => const CommitmentPortal(),
    );
  }
}
