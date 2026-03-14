import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/dashboard_bloc.dart';
import '../blocs/auth_bloc.dart';
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
  List<dynamic> _materialEntities = [];
  List<dynamic> _emotionalEntities = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scoreGlow = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.06, end: 0.18).animate(
      CurvedAnimation(parent: _scoreGlow, curve: Curves.easeInOut),
    );
    _loadAllEntities();
  }

  @override
  void dispose() {
    _scoreGlow.dispose();
    super.dispose();
  }

  Future<void> _loadAllEntities() async {
    try {
      final repo = context.read<FriendsRepository>();
      final mat = await repo.getEntities('MATERIAL');
      final emo = await repo.getEntities('EMOTIONAL');
      if (mounted) {
        setState(() {
          _materialEntities = mat;
          _emotionalEntities = emo;
        });
      }
    } catch (_) {}
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
                      _buildScoreCircle(state.reciprocityScore),
                      const SizedBox(height: 32),
                      Expanded(
                        child: DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: TabBar(
                                  dividerColor: Colors.transparent,
                                  indicator: BoxDecoration(
                                    color: SymbioTheme.primaryBlue,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  labelColor: Colors.black,
                                  unselectedLabelColor: Colors.white38,
                                  labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5),
                                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 1.5),
                                  indicatorSize: TabBarIndicatorSize.tab,
                                  padding: const EdgeInsets.all(4),
                                  tabs: const [
                                    Tab(text: 'MATERIALISTIC'),
                                    Tab(text: 'EMOTIONAL'),
                                  ],
                                ),
                              ),
                              // Search bar
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search subgroups...',
                                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.04),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                                ),
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _buildEntityGrid('MATERIAL', _materialEntities, state.materialisticEntities),
                                    _buildEntityGrid('EMOTIONAL', _emotionalEntities, state.emotionalEntities),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildScoreCircle(double score) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        return Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: SymbioTheme.primaryBlue.withValues(alpha: _glowAnim.value),
                blurRadius: 60,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  color: SymbioTheme.primaryBlue,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${score.toInt()}',
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -2,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: SymbioTheme.primaryBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RECIPROCITY',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                        color: SymbioTheme.primaryBlue.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntityGrid(String type, List<dynamic> allEntities, List<dynamic> dashboardEntities) {
    // Merge: all entities gives us stats, dashboard gives us live data
    final entities = allEntities.isNotEmpty ? allEntities : dashboardEntities;
    
    final filtered = _searchQuery.isEmpty
        ? entities
        : entities.where((e) => 
            ((e['name'] ?? '') as String).toLowerCase().contains(_searchQuery)).toList();

    return Column(
      children: [
        // Create subgroup button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: GestureDetector(
            onTap: () => _showCreateSubgroupDialog(type),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: SymbioTheme.primaryBlue.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: [
                    SymbioTheme.primaryBlue.withValues(alpha: 0.08),
                    SymbioTheme.primaryBlue.withValues(alpha: 0.02),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, size: 18, color: SymbioTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Text(
                    'CREATE SUBGROUP',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w900,
                      color: SymbioTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type == 'MATERIAL' ? Icons.account_balance_wallet_outlined : Icons.favorite_outline,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty ? 'No subgroups yet' : 'No matches found',
                        style: TextStyle(color: Colors.white30, letterSpacing: 1),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entity = filtered[index];
                    return _buildEntityCard(entity, type);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEntityCard(dynamic entity, String type) {
    final name = entity['name'] ?? 'Unknown';
    final totalScore = (entity['total_score'] as num?)?.toInt() ?? 0;
    final usersVotes = (entity['users_votes'] as num?)?.toInt() ?? 0;
    final avgScore = usersVotes > 0 ? totalScore / usersVotes : 0.0;
    // Fallback for dashboard entities that have 'reliability'
    final reliability = (entity['reliability'] as num?)?.toDouble();
    final displayScore = reliability ?? avgScore;

    final scoreColor = displayScore > 60
        ? const Color(0xFF00E676)
        : displayScore > 30
            ? const Color(0xFFFFD740)
            : displayScore > 0
                ? const Color(0xFFFF9100)
                : Colors.white38;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                // Icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scoreColor.withValues(alpha: 0.15),
                        scoreColor.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: Icon(
                    type == 'MATERIAL' ? Icons.monetization_on_outlined : Icons.favorite_outline,
                    color: scoreColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Name + type tag
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(fontSize: 8, color: Colors.white38, letterSpacing: 1.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (usersVotes > 0) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.people_outline, size: 12, color: Colors.white24),
                            const SizedBox(width: 3),
                            Text(
                              '$usersVotes vote${usersVotes == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Score display
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scoreColor.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        displayScore.toStringAsFixed(1),
                        style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AVG SCORE',
                      style: TextStyle(fontSize: 7, letterSpacing: 1.2, color: Colors.white24, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
            // Score bar
            if (usersVotes > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (displayScore / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  color: scoreColor,
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCreateSubgroupDialog(String type) {
    final nameController = TextEditingController();
    final ratingController = TextEditingController(text: '50');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: GlassContainer(
            borderRadius: 28,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: SymbioTheme.primaryBlue.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        type == 'MATERIAL' ? Icons.monetization_on_outlined : Icons.favorite_outline,
                        color: SymbioTheme.primaryBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CREATE SUBGROUP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        Text(type.toLowerCase(), style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 1)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Subgroup name...',
                    prefixIcon: Icon(Icons.label_outline, size: 20),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                const Text('INITIAL RATING', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setSliderState) {
                    double rating = double.tryParse(ratingController.text) ?? 50;
                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('1', style: TextStyle(fontSize: 11, color: Colors.white24)),
                            Text(
                              '${rating.toInt()}',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: SymbioTheme.primaryBlue),
                            ),
                            Text('100', style: TextStyle(fontSize: 11, color: Colors.white24)),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          ),
                          child: Slider(
                            value: rating,
                            min: 1,
                            max: 100,
                            activeColor: SymbioTheme.primaryBlue,
                            inactiveColor: Colors.white10,
                            onChanged: (v) {
                              setSliderState(() {
                                ratingController.text = v.toStringAsFixed(0);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      final name = nameController.text.trim();
                      final rating = double.tryParse(ratingController.text) ?? 50.0;
                      
                      try {
                        await context.read<FriendsRepository>().createEntity(name, type, rating);
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Subgroup "$name" created!'),
                              backgroundColor: SymbioTheme.primaryBlue.withValues(alpha: 0.9),
                            ),
                          );
                          _loadAllEntities();
                        }
                      } catch (e) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                           );
                         }
                      }
                    },
                    child: const Text('CREATE'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
