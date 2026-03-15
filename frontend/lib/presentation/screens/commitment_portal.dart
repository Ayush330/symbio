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
  final _entityNameController = TextEditingController();
  double _rating = 50;
  String _type = 'MATERIALISTIC';
  bool _isLoading = false;
  bool _isNewEntity = true;
  String? _selectedEntityId;
  List<dynamic> _entities = [];

  @override
  void initState() {
    super.initState();
    _loadEntities();
  }

  Future<void> _loadEntities() async {
    try {
      final repo = context.read<FriendsRepository>();
      final entities = await repo.getEntities(_type == 'MATERIALISTIC' ? 'MATERIAL' : _type);
      if (mounted) {
        debugPrint('Loaded ${entities.length} entities for $_type');
        setState(() => _entities = entities);
      }
    } catch (e) {
      debugPrint('Error loading entities for $_type: $e');
    }
  }

  void _onTypeChanged(String type) {
    setState(() {
      _type = type;
      _selectedEntityId = null;
      _isNewEntity = true;
      _entityNameController.clear();
    });
    _loadEntities();
  }

  void _handleSubmit() async {
    setState(() => _isLoading = true);
    try {
      if (_isNewEntity) {
        await context.read<CommitmentRepository>().requestCommitment(
              targetUserId: _targetUserController.text,
              entityType: _type,
              rating: _rating.toInt(),
              entityName: _entityNameController.text,
            );
      } else {
        await context.read<CommitmentRepository>().requestCommitment(
              targetUserId: _targetUserController.text,
              entityType: _type,
              rating: 0,
              entityId: _selectedEntityId,
            );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proposal sent to the ledger.')),
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
        height: MediaQuery.of(context).size.height * 0.85,
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
                      'PROPOSE EVENT',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Initiate the double-handshake',
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
            const Text('NATURE OF SYMBIOSIS', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildTypeChip('MATERIALISTIC'),
                const SizedBox(width: 12),
                _buildTypeChip('EMOTIONAL'),
              ],
            ),
            const SizedBox(height: 24),
            const Text('ENTITY', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
            const SizedBox(height: 12),
            // Autocomplete entity field
            Autocomplete<Map<String, dynamic>>(
              optionsBuilder: (TextEditingValue value) {
                final list = _entities.cast<Map<String, dynamic>>();
                if (value.text.isEmpty) return const Iterable.empty();
                return list.where((e) {
                  final name = (e['name'] ?? '') as String;
                  return name.toLowerCase().contains(value.text.toLowerCase());
                });
              },
              displayStringForOption: (option) => option['name'] as String,
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: 'Search or create a subgroup...',
                    prefixIcon: Icon(Icons.hub_outlined, size: 20),
                  ),
                  onChanged: (value) {
                    final match = _entities.any((e) =>
                        (e['name'] as String).toLowerCase() == value.toLowerCase());
                    setState(() {
                      _isNewEntity = !match;
                      if (!match) _selectedEntityId = null;
                    });
                    _entityNameController.text = value;
                    debugPrint('Search query: $value, isNew: $_isNewEntity');
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    elevation: 12,
                    shadowColor: Colors.black54,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280, maxWidth: 320),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final votes = (option['users_votes'] as num?)?.toInt() ?? 0;
                            final totalScore = (option['total_score'] as num?)?.toInt() ?? 0;
                            final avg = votes > 0 ? totalScore / votes : 0.0;
                            final scoreColor = avg > 60
                                ? const Color(0xFF00E676)
                                : avg > 30
                                    ? const Color(0xFFFFD740)
                                    : const Color(0xFFFF9100);
                            
                            return InkWell(
                              onTap: () {
                                onSelected(option);
                                setState(() {
                                  _isNewEntity = false;
                                  _selectedEntityId = option['id'];
                                  _entityNameController.text = option['name'];
                                });
                                debugPrint('Selected entity: ${option['name']} (${option['id']})');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    // Score badge
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: scoreColor.withValues(alpha: 0.12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          avg.toStringAsFixed(0),
                                          style: TextStyle(
                                            color: scoreColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option['name'] ?? 'Unknown',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Text(
                                                'Avg: ${avg.toStringAsFixed(1)}',
                                                style: TextStyle(color: scoreColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(width: 10),
                                              Icon(Icons.people_outline, size: 11, color: Colors.white24),
                                              const SizedBox(width: 3),
                                              Text(
                                                '$votes vote${votes == 1 ? '' : 's'}',
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, size: 16, color: Colors.white24),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // Show rating only for NEW entities
            if (_isNewEntity) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('INTENSITY', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold, color: Colors.white38)),
                  Text('${_rating.toInt()}', style: TextStyle(color: SymbioTheme.primaryBlue, fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
              Slider(
                value: _rating,
                min: 1,
                max: 100,
                activeColor: SymbioTheme.primaryBlue,
                inactiveColor: Colors.white10,
                onChanged: (val) => setState(() => _rating = val),
              ),
            ] else ...[
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: const Color(0xFF00E676), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Existing entity selected — no rating needed.',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('EXECUTE PROPOSAL'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    bool isSelected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTypeChanged(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? SymbioTheme.primaryBlue : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? SymbioTheme.primaryBlue : Colors.white10,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              type,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
