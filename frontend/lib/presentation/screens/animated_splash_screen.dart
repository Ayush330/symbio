import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../../core/theme/app_theme.dart';

class AnimatedSplashScreen extends StatefulWidget {
  final VoidCallback onInitializationComplete;

  const AnimatedSplashScreen({
    super.key,
    required this.onInitializationComplete,
  });

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _blurAnimation;
  late Animation<double> _opacityAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.1).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)), weight: 60),
    ]).animate(_controller);

    _blurAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playSting();
      FlutterNativeSplash.remove(); // Remove native splash when Flutter starts
    });
    
    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        widget.onInitializationComplete();
      });
    });
  }

  Future<void> _playSting() async {
    try {
      if (!mounted) return;
      
      // Give the engine a moment to stabilize
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      final source = UrlSource('https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3');
      
      // Explicitly set source before playing
      await _audioPlayer.setSource(source);
      
      if (mounted) {
        // Only resume if still valid and not playing
        await _audioPlayer.resume();
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Audio play error: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Match native splash exactly
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Static background ambient pulse
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  KizunaTheme.primaryBlue.withOpacity(0.03),
                  Colors.transparent,
                ],
                radius: 1.5,
              ),
            ),
          ),
          
          // Logo Animation
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(40),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Shadow/Glow layer
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: KizunaTheme.primaryBlue.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    // The main logo
                    Image.asset(
                      'assets/images/kizuna_icon.png',
                      width: MediaQuery.of(context).size.width * 0.5,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Text Animation
          Positioned(
            bottom: 80,
            child: RepaintBoundary(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Column(
                  children: [
                    Text(
                      'KIZUNA',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 12,
                        shadows: [
                          Shadow(
                            color: KizunaTheme.primaryBlue.withOpacity(0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 1,
                      color: KizunaTheme.primaryBlue.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
