import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
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

    _playSting();
    _controller.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        widget.onInitializationComplete();
      });
    });
  }

  Future<void> _playSting() async {
    try {
      // High-end minimalist UI "whoosh/sting" sound
      await _audioPlayer.play(UrlSource('https://assets.mixkit.co/active_storage/sfx/2568/2568-preview.mp3'));
    } catch (e) {
      debugPrint('Audio play error: $e');
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
      backgroundColor: KizunaTheme.backgroundBlack,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background ambient pulse
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      KizunaTheme.primaryBlue.withValues(alpha: 0.05 * _opacityAnimation.value),
                      Colors.transparent,
                    ],
                    radius: 1.5 * _scaleAnimation.value,
                  ),
                ),
              );
            },
          ),
          
          // Logo Animation
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: ImageFiltered(
                    imageFilter: ColorFilter.mode(
                      Colors.transparent, 
                      BlendMode.multiply,
                    ),
                    // Adding a subtle blur that clears up
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
                                  color: KizunaTheme.primaryBlue.withValues(alpha: 0.2 * _opacityAnimation.value),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          // The main logo
                          Image.asset(
                            'assets/icon/app_icon.png',
                            width: 180,
                            height: 180,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Text Animation
          Positioned(
            bottom: 80,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: Column(
                children: [
                  Text(
                    'KIZUNA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                      shadows: [
                        Shadow(
                          color: KizunaTheme.primaryBlue.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 1,
                    color: KizunaTheme.primaryBlue.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
