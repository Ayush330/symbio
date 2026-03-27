import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../blocs/auth_bloc.dart';
import '../widgets/glass_container.dart';
import '../../core/theme/app_theme.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLogin = true;

  String _cleanPhoneNumber(String phone) {
    final trimmed = phone.trim();
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return hasPlus ? '+$digits' : digits;
  }

  void _pickContact() async {
    try {
      final status = await Permission.contacts.request();
      if (status.isGranted) {
        final id = await FlutterContacts.native.showPicker();
        if (id != null) {
          //final fullContact = await FlutterContacts.get(id);
          final fullContact = await FlutterContacts.get(id, properties: ContactProperties.all);
          if (fullContact != null && fullContact.phones.isNotEmpty) {
            if (fullContact.phones.length == 1) {
              _onContactSelected(fullContact.phones.first.number);
            } else {
              _showPhoneSelectionSheet(fullContact);
            }
          }
        }
      }
    } catch (e) {
      print('DEBUG: Error in _pickContact: $e');
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
                  onTap: () {
                    Navigator.pop(ctx);
                    _onContactSelected(phone.number);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _onContactSelected(String rawPhone) {
    final phone = _cleanPhoneNumber(rawPhone);
    print('DEBUG: LoginScreen _onContactSelected: $phone');
    if (mounted) {
      FocusScope.of(context).unfocus();
      setState(() {
        _phoneController.text = phone;
        _emailController.clear();
        
        _phoneController.selection = TextSelection.fromPosition(
          TextPosition(offset: phone.length),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    KizunaTheme.primaryBlue.withOpacity(0.05),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 80),
                  // Logo / Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: KizunaTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.sync_alt, size: 32, color: Colors.black),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isLogin ? 'Welcome Back' : 'Join Kizuna',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isLogin ? 'Sign in to your account' : 'Start your Kizuna journey',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 48),
                  GlassContainer(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (!_isLogin) ...[
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              hintText: 'Phone Number',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (val) {
                              if (_isLogin && val.isNotEmpty) {
                                setState(() => _emailController.clear());
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _pickContact,
                            icon: const Icon(Icons.contacts_rounded, size: 16, color: KizunaTheme.accentCyan),
                            label: const Text('PICK FROM CONTACTS', style: TextStyle(color: KizunaTheme.accentCyan, fontSize: 11)),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (val) {
                            if (_isLogin && val.isNotEmpty) {
                              setState(() => _phoneController.clear());
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            hintText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                        ),
                      ],
                    ),
                  ),
                  if (_isLogin) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                        ),
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(color: KizunaTheme.primaryBlue.withOpacity(0.8)),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                  ],
                  const SizedBox(height: 8),
                  BlocConsumer<AuthBloc, AuthState>(
                    listener: (context, state) {
                      if (state is AuthFailure) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(state.message),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    builder: (context, state) {
                      return Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: KizunaTheme.primaryBlue.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: state is AuthLoading
                              ? null
                              : () {
                                  if (_isLogin) {
                                    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Email and Password are required'), backgroundColor: Colors.orangeAccent),
                                      );
                                      return;
                                    }
                                    context.read<AuthBloc>().add(
                                          LoginRequested(
                                            _emailController.text.trim(),
                                            _passwordController.text,
                                          ),
                                        );
                                  } else {
                                    // Validation for Signup
                                    if (_nameController.text.isEmpty ||
                                        _emailController.text.isEmpty ||
                                        _passwordController.text.isEmpty ||
                                        _phoneController.text.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('All fields are mandatory'), backgroundColor: Colors.orangeAccent),
                                      );
                                      return;
                                    }
                                    context.read<AuthBloc>().add(
                                          SignupRequested(
                                            _emailController.text.trim(),
                                            _passwordController.text,
                                            _nameController.text.trim(),
                                            phone: _phoneController.text.trim(),
                                          ),
                                        );
                                  }
                                },
                          child: state is AuthLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : Text(_isLogin ? 'Sign In' : 'Create Account'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: RichText(
                        text: TextSpan(
                          text: _isLogin ? "Don't have an account? " : 'Already have an account? ',
                          style: const TextStyle(color: Colors.white54),
                          children: [
                            TextSpan(
                              text: _isLogin ? 'Sign Up' : 'Sign In',
                              style: TextStyle(
                                color: KizunaTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
