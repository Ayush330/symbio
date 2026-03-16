import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/glass_container.dart';

class FavourDetailScreen extends StatelessWidget {
  final dynamic favour;

  const FavourDetailScreen({super.key, required this.favour});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAVOUR DETAILS', style: TextStyle(letterSpacing: 2, fontSize: 14, fontWeight: FontWeight.w900)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: SymbioTheme.backgroundBlack)),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: GlassContainer(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favour['category']?.toUpperCase() ?? 'OTHER',
                    style: const TextStyle(color: SymbioTheme.primaryBlue, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    favour['text'] ?? 'Legacy Commitment',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.4),
                  ),
                  const SizedBox(height: 40),
                  _buildDetailRow(Icons.calendar_today_outlined, 'DATE', favour['created_at'].toString().substring(0, 10)),
                  const SizedBox(height: 24),
                  _buildDetailRow(Icons.stars_rounded, 'POINTS', '${favour['points'] ?? 0} PTS'),
                  const SizedBox(height: 24),
                  _buildDetailRow(Icons.person_outline, 'BY', favour['initiator_name'] ?? 'Unknown'),
                  const SizedBox(height: 24),
                  _buildDetailRow(Icons.check_circle_outline, 'STATUS', favour['status'] ?? 'PENDING'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white24),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70)),
          ],
        ),
      ],
    );
  }
}
