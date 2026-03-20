import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/friends_repository.dart';
import '../widgets/glass_container.dart';
import '../widgets/kizuna_button.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  Map<String, dynamic>? _lookupResult;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _cleanPhoneNumber(String phone) {
    final trimmed = phone.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return hasPlus ? '+$digits' : digits;
  }

  void _pickContact() async {
    print('DEBUG: _pickContact started');
    try {
      final status = await Permission.contacts.request();
      print('DEBUG: Contact permission status: $status');

      if (status.isGranted) {
        print('DEBUG: Launching native picker via FlutterContacts.native.showPicker()');
        final id = await FlutterContacts.native.showPicker();
        print('DEBUG: Picker returned ID: $id');

        if (id != null) {
          //final fullContact = await FlutterContacts.get(id);
          //final fullContact = await FlutterContacts.getContact(id, withProperties: true);
          final fullContact = await FlutterContacts.get(id, properties: ContactProperties.all);
          print('DEBUG: Full contact details: $fullContact');

          if (fullContact != null && fullContact.phones.isNotEmpty) {
            if (fullContact.phones.length == 1) {
              _onContactSelected(fullContact, fullContact.phones.first.number);
            } else {
              _showPhoneSelectionSheet(fullContact);
            }
          } else {
            print('DEBUG: No phones found or contact fetch failed');
          }
        }
      } else if (status.isPermanentlyDenied) {
        print('DEBUG: Permission permanently denied');
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: KizunaTheme.surfaceGlass,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Contacts Permission',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: const Text(
                'Please enable contacts permission in settings to pick a member.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('SETTINGS', style: TextStyle(color: KizunaTheme.accentCyan)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: Error in _pickContact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Picker Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showPhoneSelectionSheet(Contact contact) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassContainer(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Number for ${contact.displayName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            ...contact.phones.map((phone) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_rounded, color: KizunaTheme.accentCyan),
                  title: Text(phone.number, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    phone.label.toString().split('.').last.toUpperCase(),
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onContactSelected(contact, phone.number);
                  },
                )),
          ],
        ),
      ),
    );
  }

void _onContactSelected(Contact contact, String rawPhone) {
    final phone = _cleanPhoneNumber(rawPhone);
    print('DEBUG: _onContactSelected: raw="$rawPhone", cleaned="$phone"');

    if (phone.isEmpty) return;

    // FIX 1: Put the controller updates inside setState so the screen reliably repaints.
    // FIX 2: Do this BEFORE unfocusing the keyboard to prevent data from being overwritten.
    setState(() {
      _phoneController.value = TextEditingValue(
        text: phone,
        selection: TextSelection.collapsed(offset: phone.length),
      );
      _emailController.clear();
      _lookupResult = null;
    });

    // Now that the text is safely set, we can dismiss the keyboard.
    FocusScope.of(context).unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleLookup(name: contact.displayName);
    });
  }


  void _handleLookup({String? name}) async {
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (email.isEmpty && phone.isEmpty) return;

    setState(() {
      _isLoading = true;
      _lookupResult = null;
    });

    try {
      final repo = context.read<FriendsRepository>();

      final result = await repo.lookupUser(
        email.isNotEmpty ? email : null,
        phone: phone.isNotEmpty ? _cleanPhoneNumber(phone) : null,
      );

      if (mounted) {
        setState(() {
          _lookupResult = result;
          if (_lookupResult!['exists'] == false && name != null) {
            _lookupResult!['name'] = name;
          }
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

  void _shareInvite() {
    const packageName = 'com.symbio.symbiosis_app';
    const playStoreLink = 'https://play.google.com/store/apps/details?id=$packageName';
    
    SharePlus.instance.share(
      ShareParams(
        text: 'Hey! Join me on Kizuna, the social integrity ledger. Download it here: $playStoreLink',
        title: 'Join me on Kizuna!',
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('INVITE', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: KizunaTheme.backgroundBlack)),
          Positioned(
            top: -50,
            right: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KizunaTheme.accentCyan.withOpacity(0.05),
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
                    'Search for someone on Kizuna or invite them to join you.',
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
                            hintText: 'Email Address',
                            prefixIcon: Icon(Icons.email_outlined, size: 20),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (val) {
                            if (val.isNotEmpty) {
                              setState(() {
                                _phoneController.clear();
                                _lookupResult = null;
                              });
                            }
                          },
                          onSubmitted: (_) => _handleLookup(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            hintText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_outlined, size: 20),
                          ),
                          keyboardType: TextInputType.phone,
                          onChanged: (val) {
                            if (val.isNotEmpty) {
                              setState(() {
                                _emailController.clear();
                                _lookupResult = null;
                              });
                            }
                          },
                          onSubmitted: (_) => _handleLookup(),
                        ),
                        const SizedBox(height: 16),
                        KizunaButton(
                          onPressed: _pickContact,
                          icon: Icons.contacts_rounded,
                          label: 'PICK FROM CONTACTS',
                          outline: true,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          fontSize: 11,
                        ),
                        const SizedBox(height: 20),
                        KizunaButton(
                          onPressed: _handleLookup,
                          isLoading: _isLoading,
                          label: 'SEARCH KIZUNA',
                          icon: Icons.search_rounded,
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
              '${_lookupResult!['name'] ?? 'User'} is on Kizuna!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            if (_emailController.text.isNotEmpty || _phoneController.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _emailController.text.isNotEmpty ? _emailController.text : _phoneController.text,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.3),
                    fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Send them a friend request to start building your trust ledger together.',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            KizunaButton(
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
              color: KizunaTheme.primaryBlue.withOpacity(0.1),
              border: Border.all(color: KizunaTheme.primaryBlue.withOpacity(0.3)),
            ),
            child: Icon(Icons.person_add_alt_1, color: KizunaTheme.primaryBlue, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Not on Kizuna yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (_emailController.text.isNotEmpty || _phoneController.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _emailController.text.isNotEmpty ? _emailController.text : _phoneController.text,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.3),
                  fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Share an invite link via WhatsApp or other apps so they can join you.',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          KizunaButton(
            onPressed: _shareInvite,
            icon: Icons.share_rounded,
            label: 'SHARE INVITE LINK',
          ),
        ],
      ),
    );
  }
}