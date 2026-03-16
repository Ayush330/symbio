import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/commitment_repository.dart';
import '../../data/repositories/friends_repository.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/glass_container.dart';

class CommitmentPortal extends StatefulWidget {
  const CommitmentPortal({super.key});

  @override
  State<CommitmentPortal> createState() => _CommitmentPortalState();
}

class _CommitmentPortalState extends State<CommitmentPortal> {
  final _targetUserController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  void _handleClassification() async {
    if (_targetUserController.text.isEmpty || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = context.read<FriendsRepository>();
      final classification = await repo.classifyFavour(_descriptionController.text);
      
      if (mounted) {
        _showConfirmationDialog(classification['category'], classification['points']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showConfirmationDialog(String category, int points) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SymbioTheme.surfaceGlass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: SymbioTheme.primaryBlue.withOpacity(0.2)),
        ),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SymbioTheme.primaryBlue.withOpacity(0.1),
              ),
              child: Icon(Icons.psychology_outlined, color: SymbioTheme.primaryBlue, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'CLASSIFICATION',
              style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.toUpperCase(),
              style: TextStyle(
                color: SymbioTheme.primaryBlue,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+$points POINTS',
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            Text(
              '“${_descriptionController.text}”',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('EDIT', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitFavour();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SymbioTheme.primaryBlue,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  void _submitFavour() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<FriendsRepository>();
      
      // Look up target user ID from email
      final targetUser = await repo.lookupUser(_targetUserController.text);
      final targetId = targetUser['user_id']?.toString();
      
      if (targetId == null) {
        throw 'Recipient not found. Please check the email.';
      }

      await repo.createFavour(targetId, _descriptionController.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favour added to the ledger.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 32,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOG FAVOUR',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Record a social contribution',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('RECIPIENT EMAIL', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
            const SizedBox(height: 12),
            TextField(
              controller: _targetUserController,
              decoration: const InputDecoration(
                hintText: 'partner@symbio.com',
                prefixIcon: Icon(Icons.alternate_email, size: 20),
              ),
            ),
            const SizedBox(height: 24),
            const Text('WHAT HAPPENED?', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _descriptionController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'e.g., Helped Rahul with interview prep',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 120),
                    child: Icon(Icons.description_outlined, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleClassification,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('REVIEW PROPOSAL'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
