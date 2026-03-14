import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _lookupResult;

  void _handleLookup() async {
    if (_emailController.text.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _lookupResult = null;
    });

    try {
      final repo = context.read<FriendsRepository>();
      final result = await repo.lookupUser(_emailController.text.trim());
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
                color: SymbioTheme.accentCyan.withOpacity(0.05),
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
                    style: TextStyle(color: Colors.white.withOpacity(0.4), height: 1.5),
                  ),
                  const SizedBox(height: 40),
                  GlassContainer(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            hintText: 'Enter their email address',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          onSubmitted: (_) => _handleLookup(),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLookup,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                                  )
                                : const Text('SEARCH'),
                          ),
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
                color: const Color(0xFF00E676).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
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
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading 
                    ? null 
                    : () => _sendFriendRequest(_lookupResult!['user_id']),
                icon: const Icon(Icons.person_add, size: 18),
                label: _isLoading 
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('SEND FRIEND REQUEST'),
              ),
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
              color: SymbioTheme.primaryBlue.withOpacity(0.1),
              border: Border.all(color: SymbioTheme.primaryBlue.withOpacity(0.3)),
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
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _shareInvite,
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('SHARE INVITE'),
            ),
          ),
        ],
      ),
    );
  }
}
