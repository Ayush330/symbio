import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/kizuna_button.dart';
import '../widgets/glass_container.dart';

class AddFavourScreen extends StatefulWidget {
  const AddFavourScreen({super.key});

  @override
  State<AddFavourScreen> createState() => _AddFavourScreenState();
}

class _AddFavourScreenState extends State<AddFavourScreen> {
  String _selectedCategory = 'social';
  int _timeLevel = 3;
  int _effortLevel = 3;
  int _sacrificeLevel = 2;
  int _urgencyLevel = 2;

  final Map<String, int> _categoryWeights = {
    'emergency': 100,
    'health': 95,
    'family': 90,
    'money': 85,
    'legal': 85,
    'career': 80,
    'startup': 80,
    'emotional': 75,
    'relationship': 75,
    'education': 70,
    'mentorship': 70,
    'networking': 65,
    'tech': 65,
    'travel': 60,
    'community': 60,
    'social': 55,
    'household': 50,
    'fitness': 45,
    'food': 35,
    'fun': 25,
  };

  final List<String> _timeLabels = ["5m", "30m", "1h", "1/2d", "Full"];
  final List<String> _effortLabels = ["Easy", "Norm", "Hard", "VHard", "Ex"];
  final List<String> _sacrificeLabels = ["None", "Small", "Med", "Big", "Huge"];
  final List<String> _urgencyLabels = ["Low", "Norm", "Urg", "VUrg", "Emer"];

  double get _intensity {
    return 5.0 * (_effortLevel + _timeLevel + _sacrificeLevel + _urgencyLevel) / 4.0;
  }

  double get _intensity100 => _intensity * 4.0;

  int get _finalScore {
    int weight = _categoryWeights[_selectedCategory] ?? 10;
    double score = (weight * _intensity100) / 100.0;
    return score.round().clamp(1, 100);
  }

  @override
  Widget build(BuildContext context) {
    final auraColor = KizunaTheme.getKarmaColor(_finalScore.toDouble());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('ADD FAVOUR', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: KizunaTheme.backgroundBlack)),
          // Top glow
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  auraColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('CATEGORY', _buildCategoryDropdown(auraColor)),
                  const SizedBox(height: 24),
                  _buildSection('TIME SPENT', _buildChoiceChips(_timeLabels, _timeLevel, auraColor, (v) => setState(() => _timeLevel = v))),
                  const SizedBox(height: 24),
                  _buildSection('EFFORT', _buildChoiceChips(_effortLabels, _effortLevel, auraColor, (v) => setState(() => _effortLevel = v))),
                  const SizedBox(height: 24),
                  _buildSection('SACRIFICE', _buildChoiceChips(_sacrificeLabels, _sacrificeLevel, auraColor, (v) => setState(() => _sacrificeLevel = v))),
                  const SizedBox(height: 24),
                  _buildSection('URGENCY', _buildChoiceChips(_urgencyLabels, _urgencyLevel, auraColor, (v) => setState(() => _urgencyLevel = v))),
                  
                  const SizedBox(height: 48),
                  _buildPulseIndicator(auraColor),
                  const SizedBox(height: 40),
                  
                  KizunaButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Favour Recorded in Vault'), backgroundColor: Colors.black),
                      );
                      Navigator.pop(context);
                    },
                    label: 'SAVE TO LEDGER',
                    icon: Icons.security_rounded,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildCategoryDropdown(Color color) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          dropdownColor: KizunaTheme.surfaceGlass,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: color),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
          onChanged: (v) => setState(() => _selectedCategory = v!),
          items: _categoryWeights.keys.map((c) => DropdownMenuItem(
            value: c,
            child: Text(c.toUpperCase(), style: const TextStyle(letterSpacing: 1)),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildChoiceChips(List<String> labels, int currentVal, Color auraColor, Function(int) onSelected) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isSelected = currentVal == (index + 1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(index + 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? auraColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? auraColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white38,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPulseIndicator(Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('INTENSITY', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
            Text('${_intensity100.toInt()}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 16),
        Stack(
          children: [
            Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(5))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 10,
              width: (MediaQuery.of(context).size.width - 48) * (_intensity100 / 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withValues(alpha: 0.5), color]),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 1)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('KARMA SCORE:', style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white38)),
              const SizedBox(width: 12),
              Text('$_finalScore', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}
