import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
                    SymbioTheme.primaryBlue.withOpacity(0.05),
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
                      gradient: SymbioTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.sync_alt, size: 32, color: Colors.black),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isLogin ? 'Welcome Back' : 'Join Symbio',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin ? 'Sign in to your account' : 'Start your symbiosis journey',
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
                          style: TextStyle(color: SymbioTheme.primaryBlue.withOpacity(0.8)),
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
                              color: SymbioTheme.primaryBlue.withOpacity(0.2),
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
                                    context.read<AuthBloc>().add(
                                          LoginRequested(
                                            _emailController.text,
                                            _passwordController.text,
                                          ),
                                        );
                                  } else {
                                    context.read<AuthBloc>().add(
                                          SignupRequested(
                                            _emailController.text,
                                            _passwordController.text,
                                            _nameController.text,
                                            phone: _phoneController.text,
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
                                color: SymbioTheme.primaryBlue,
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
