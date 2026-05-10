import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import '../home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (mounted && auth.status == AuthStatus.authenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat, size: 64, color: Colors.blue),
                const SizedBox(height: 8),
                const Text('CloseTalk',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                Consumer<AuthProvider>(
                  builder: (_, auth, __) {
                    if (auth.error != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(auth.error!,
                            style:
                                const TextStyle(color: Colors.red)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),
                Consumer<AuthProvider>(
                  builder: (_, auth, __) => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          auth.status == AuthStatus.loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: auth.status == AuthStatus.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Text('Login',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen()),
                  ),
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
