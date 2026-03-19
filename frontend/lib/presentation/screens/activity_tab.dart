import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';
import '../../data/models/favour_models.dart';
import '../blocs/friends_bloc.dart';

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  List<ActivityGraphData> _graphData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    try {
      final repo = context.read<FriendsRepository>();
      final data = await repo.getActivityGraph();
      if (mounted) {
        setState(() {
          _graphData = data.map((e) => ActivityGraphData.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FriendsBloc, FriendsState>(
      listener: (context, state) {
        if (state is FriendsLoaded) {
          _loadGraph();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('ACTIVITY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: Container(color: KizunaTheme.backgroundBlack)),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_graphData.isEmpty)
              _buildEmptyState()
            else
              _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bar_chart_rounded, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text('No comparison data yet', style: TextStyle(color: Colors.white30)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 120, left: 24, right: 24, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('POINTS COMPARISON', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
          const SizedBox(height: 32),
          GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: _graphData.map((d) => _buildBar(d)).toList(),
            ),
          ),
          const SizedBox(height: 40),
          const Text('Your top 5 active connections in terms of total points exchanged.', 
            style: TextStyle(fontSize: 12, color: Colors.white24, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildBar(ActivityGraphData data) {
    // Determine max points for normalization (fallback to 100)
    final maxPoints = _graphData.map((e) => e.points).reduce((a, b) => a > b ? a : b).clamp(100, 1000000);
    final double percent = (data.points / maxPoints).clamp(0.05, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${data.points} pts', style: const TextStyle(color: KizunaTheme.primaryBlue, fontWeight: FontWeight.w900, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percent,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [KizunaTheme.primaryBlue, KizunaTheme.accentCyan]),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: KizunaTheme.primaryBlue.withOpacity(0.3), blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
