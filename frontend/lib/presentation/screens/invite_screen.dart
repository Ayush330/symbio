import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';
import '../widgets/symbio_button.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _inputController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _lookupResult;

  void _handleLookup() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _lookupResult = null;
    });

    try {
      final repo = context.read<FriendsRepository>();
      
      // Basic detection for phone vs email
      final isPhone = RegExp(r'^[\d\+\-\(\)\s]{7,}$').hasMatch(query);
      
      final result = await repo.lookupUser(
        !isPhone ? query : null,
        phone: isPhone ? query : null,
      );
      
      if (mounted) {
        setState(() {
          _lookupResult = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _handleInvite() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final repo = context.read<FriendsRepository>();
      final isPhone = RegExp(r'^[\d\+\-\(\)\s]{7,}$').hasMatch(query);
      
      await repo.sendInvite(
        email: !isPhone ? query : null,
        phone: isPhone ? query : null,
      );
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invite Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _sendFriendRequest(String targetId) async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<FriendsRepository>();
      await repo.sendFriendRequest(targetId);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _shareInvite() {
    SharePlus.instance.share(
      ShareParams(
        text: 'Hey! Join me on Symbio — a trust ledger for real relationships. '
            'Download it here: https://symbio.app/invite',
        title: 'Join me on Symbio!',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('INVITE', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: SymbioTheme.backgroundBlack)),
          Positioned(
            top: -50,
            right: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SymbioTheme.accentCyan.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Find or Invite',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for someone on Symbio or invite them to join you.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), height: 1.5),
                  ),
                  const SizedBox(height: 40),
                  GlassContainer(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          controller: _inputController,
                          decoration: const InputDecoration(
                            hintText: 'Enter email or phone number',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                          ),
                          keyboardType: TextInputType.text,
                          onSubmitted: (_) => _handleLookup(),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: SymbioButton(
                                onPressed: _handleLookup,
                                isLoading: _isLoading,
                                label: 'SEARCH',
                                icon: Icons.search_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SymbioButton(
                                onPressed: _handleInvite,
                                isLoading: _isLoading,
                                label: 'INVITE',
                                icon: Icons.send_rounded,
                                outline: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_lookupResult != null) _buildResult(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final exists = _lookupResult!['exists'] == true;

    if (exists) {
      return GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E676).withValues(alpha: 0.1),
                border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              '${_lookupResult!['name'] ?? 'User'} is on Symbio!',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Send them a friend request to start building your trust ledger together.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SymbioButton(
              onPressed: () => _sendFriendRequest(_lookupResult!['user_id']),
              isLoading: _isLoading,
              icon: Icons.person_add,
              label: 'SEND FRIEND REQUEST',
            ),
          ],
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SymbioTheme.primaryBlue.withValues(alpha: 0.1),
              border: Border.all(color: SymbioTheme.primaryBlue.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.person_add_alt_1, color: SymbioTheme.primaryBlue, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Not on Symbio yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Share an invite link so they can join you.',
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SymbioButton(
            onPressed: _handleInvite,
            icon: Icons.mark_email_read_rounded,
            label: 'SEND FORMAL INVITE',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _shareInvite,
            icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white38),
            label: const Text('SHARE LINK INSTEAD', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
