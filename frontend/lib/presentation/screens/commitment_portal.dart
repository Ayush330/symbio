import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../../presentation/widgets/pill_selector.dart';
import '../../presentation/widgets/error_dialog.dart';

class CommitmentPortal extends StatefulWidget {
  final String? initialEmail;
  final String? targetUserId;
  const CommitmentPortal({super.key, this.initialEmail, this.targetUserId});

  @override
  State<CommitmentPortal> createState() => _CommitmentPortalState();
}

class _CommitmentPortalState extends State<CommitmentPortal> {
  final _targetUserController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  // New Metric States (Mapped to 25, 50, 75)
  int _effort = 50;
  int _timeTaken = 50;
  int _sacrifice = 25;
  int _urgency = 25;
  int _intensity = 50;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _targetUserController.text = widget.initialEmail!;
    }
  }

  void _handleClassification() async {
    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the favour first.')),
      );
      return;
    }

    print('DEBUG: _handleClassification started');
    setState(() => _isLoading = true);
    try {
      final repo = context.read<FriendsRepository>();
      print('DEBUG: Calling classifyFavour with text: ${_descriptionController.text}');
      final classification = await repo.classifyFavour(_descriptionController.text);
      print('DEBUG: Classification response: $classification');
      
      if (mounted) {
        print('DEBUG: Showing confirmation dialog');
        final category = classification['category']?.toString() ?? 'Other';
        final points = (classification['points'] as num?)?.toInt() ?? 10;
        
        _showConfirmationDialog(category, points);
      }
    } catch (e) {
      print('DEBUG: Classification error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      print('DEBUG: _handleClassification finished');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showConfirmationDialog(String category, int points) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KizunaTheme.surfaceGlass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: KizunaTheme.primaryBlue.withOpacity(0.2)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KizunaTheme.primaryBlue.withOpacity(0.1),
              ),
              child: Icon(Icons.psychology_outlined, color: KizunaTheme.primaryBlue, size: 32),
            ),
            const SizedBox(width: 16),
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
                color: KizunaTheme.primaryBlue,
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
              backgroundColor: KizunaTheme.primaryBlue,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(120, 48),
            ),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  void _submitFavour() async {
    print('DEBUG: _submitFavour started');
    setState(() => _isLoading = true);
    
    // Store context before async calls
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ctx = context;

    try {
      final repo = context.read<FriendsRepository>();
      
      String? targetId = widget.targetUserId;
      print('DEBUG: Initial targetId: $targetId');
      
      // Look up target user ID from email if not provided
      if (targetId == null) {
        if (_targetUserController.text.trim().isEmpty) {
          throw 'Recipient email is required';
        }
        print('DEBUG: Looking up user: ${_targetUserController.text}');
        final targetUser = await repo.lookupUser(_targetUserController.text.trim());
        targetId = targetUser['user_id']?.toString();
        print('DEBUG: Lookup result targetId: $targetId');
      }
      
      if (targetId == null) {
        throw 'Recipient not found';
      }

      print('DEBUG: Creating favour for targetId: $targetId');
      await repo.createFavour(
        targetId, 
        _descriptionController.text,
        effort: _effort ~/ 10,
        timeTaken: _timeTaken ~/ 10,
        sacrifice: _sacrifice ~/ 10,
        urgency: _urgency ~/ 10,
        intensity: _intensity.toDouble(),
      );
      print('DEBUG: Favour creation success');
      
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Contribution logged.')),
        );
      }
    } catch (e) {
      print('DEBUG: Favour creation error: $e');
      if (mounted) {
        ErrorDialog.show(ctx, e.toString(), title: 'LOG FAILED');
      }
    } finally {
      print('DEBUG: _submitFavour finished');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: KizunaTheme.backgroundBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LOG FAVOUR',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 32),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prominent Text Area
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'What did you do?',
                      hintStyle: TextStyle(color: Colors.white12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Metrics Collection
                  PillSelector(
                    label: 'EFFORT',
                    selectedValue: _effort,
                    onChanged: (v) => setState(() => _effort = v),
                  ),
                  const SizedBox(height: 32),
                  PillSelector(
                    label: 'TIME SPENT',
                    selectedValue: _timeTaken,
                    onChanged: (v) => setState(() => _timeTaken = v),
                  ),
                  const SizedBox(height: 32),
                  PillSelector(
                    label: 'SACRIFICE',
                    selectedValue: _sacrifice,
                    onChanged: (v) => setState(() => _sacrifice = v),
                  ),
                  const SizedBox(height: 32),
                  PillSelector(
                    label: 'URGENCY',
                    selectedValue: _urgency,
                    onChanged: (v) => setState(() => _urgency = v),
                  ),
                  const SizedBox(height: 32),
                  PillSelector(
                    label: 'INTENSITY',
                    selectedValue: _intensity,
                    onChanged: (v) => setState(() => _intensity = v),
                  ),
                  const SizedBox(height: 48),

                  // Subtle Recipient Info
                  if (widget.initialEmail == null) ...[
                    const Text('TO RECIPIENT', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.white24)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _targetUserController,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                      decoration: const InputDecoration(
                        hintText: 'partner@symbio.app',
                        hintStyle: TextStyle(color: Colors.white10),
                        prefixIcon: Icon(Icons.alternate_email, size: 16, color: Colors.white24),
                        filled: false,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Text('TO:', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.white24)),
                        const SizedBox(width: 8),
                        Text(widget.initialEmail!.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: KizunaTheme.primaryBlue.withOpacity(0.6))),
                      ],
                    ),
                  ],
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleClassification,
              style: ElevatedButton.styleFrom(
                backgroundColor: KizunaTheme.primaryBlue,
                foregroundColor: Colors.black,
                minimumSize: const Size(260, 64),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                elevation: 10,
                shadowColor: KizunaTheme.primaryBlue.withOpacity(0.4),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('RECORD PROPOSAL', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
