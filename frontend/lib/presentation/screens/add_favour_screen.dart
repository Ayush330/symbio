import 'package:flutter/material.dart';
import 'dart:math' as math;

class AddFavourScreen extends StatefulWidget {
  const AddFavourScreen({super.key});

  @override
  State<AddFavourScreen> createState() => _AddFavourScreenState();
}

class _AddFavourScreenState extends State<AddFavourScreen> {
  String _selectedCategory = 'social';
  int _timeLevel = 1;
  int _effortLevel = 1;
  int _sacrificeLevel = 1;
  int _urgencyLevel = 1;

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

  final List<String> _timeLabels = ["5 min", "30 min", "1 hr", "Half day", "Full day"];
  final List<String> _effortLabels = ["Easy", "Normal", "Hard", "Very Hard", "Extreme"];
  final List<String> _sacrificeLabels = ["None", "Small", "Medium", "Big", "Huge"];
  final List<String> _urgencyLabels = ["Low", "Normal", "Urgent", "Very Urgent", "Emergency"];

  double get _intensity {
    // intensity = 5 * (effort + time + sacrifice + urgency) / 4
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Add Favour',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Category'),
            const SizedBox(height: 12),
            _buildCategoryDropdown(colorScheme),
            
            const SizedBox(height: 24),
            _buildSectionTitle('Time spent'),
            const SizedBox(height: 12),
            _buildChoiceChips(_timeLabels, _timeLevel, (val) => setState(() => _timeLevel = val)),
            
            const SizedBox(height: 24),
            _buildSectionTitle('Effort'),
            const SizedBox(height: 12),
            _buildChoiceChips(_effortLabels, _effortLevel, (val) => setState(() => _effortLevel = val)),
            
            const SizedBox(height: 24),
            _buildSectionTitle('Sacrifice'),
            const SizedBox(height: 12),
            _buildChoiceChips(_sacrificeLabels, _sacrificeLevel, (val) => setState(() => _sacrificeLevel = val)),
            
            const SizedBox(height: 24),
            _buildSectionTitle('Urgency'),
            const SizedBox(height: 12),
            _buildChoiceChips(_urgencyLabels, _urgencyLevel, (val) => setState(() => _urgencyLevel = val)),
            
            const SizedBox(height: 40),
            _buildIntensityIndicator(colorScheme),
            
            const SizedBox(height: 32),
            _buildSaveButton(colorScheme),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey[600],
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildCategoryDropdown(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(16),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() => _selectedCategory = newValue);
            }
          },
          items: _categoryWeights.keys.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value[0].toUpperCase() + value.substring(1)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChoiceChips(List<String> labels, int currentVal, Function(int) onSelected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(labels.length, (index) {
        final isSelected = currentVal == (index + 1);
        return ChoiceChip(
          label: Text(labels[index]),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) onSelected(index + 1);
          },
          showCheckmark: false,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
          selectedColor: Colors.black,
          backgroundColor: Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isSelected ? Colors.black : Colors.transparent),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        );
      }),
    );
  }

  Widget _buildIntensityIndicator(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Intensity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            Text(
              '${_intensity100.toInt()}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _intensity100 / 100,
            minHeight: 12,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(_getIntensityColor(_intensity100)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Karma Score: $_finalScore',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Color _getIntensityColor(double intensity) {
    if (intensity < 30) return Colors.blueAccent;
    if (intensity < 60) return Colors.greenAccent[700]!;
    if (intensity < 85) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _buildSaveButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: () {
          // TODO: Implement save logic
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Favour Saved!'), behavior: SnackBarBehavior.floating),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: const Text(
          'Save favour',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }
}
