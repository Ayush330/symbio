import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/glass_container.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _handleSubmit() async {
    setState(() => _isLoading = true);
    try {
      await context.read<AuthRepository>().resetPassword(
            _tokenController.text,
            _passwordController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully!')),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Access')),
      body: Container(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reset Password',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Enter the token from your console and your new secure password.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 48),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                hintText: 'Recovery Token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                hintText: 'New Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('UPDATE PASSWORD'),
            ),
          ],
        ),
      ),
    );
  }
}
