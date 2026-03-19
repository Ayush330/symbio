import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PillSelector extends StatelessWidget {
  final String label;
  final int selectedValue; // 25, 50, 75
  final ValueChanged<int> onChanged;

  const PillSelector({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w900,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildPill('LOW', 25),
            const SizedBox(width: 8),
            _buildPill('MED', 50),
            const SizedBox(width: 8),
            _buildPill('HIGH', 75),
          ],
        ),
      ],
    );
  }

  Widget _buildPill(String text, int value) {
    final bool isSelected = selectedValue == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? KizunaTheme.primaryBlue
                : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? KizunaTheme.primaryBlue
                  : Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: isSelected ? Colors.black : Colors.white38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
