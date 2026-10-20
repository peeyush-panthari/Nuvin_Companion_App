import 'package:flutter/material.dart';

class IntroSlideData {
  final String imageAsset;
  final String title;
  final String subtitle;
  final Color fallbackColor;

  const IntroSlideData({
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    required this.fallbackColor,
  });
}

class WelcomeIntroScreen extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSkipToLogin;

  const WelcomeIntroScreen({
    super.key,
    required this.onGetStarted,
    required this.onSkipToLogin,
  });

  @override
  State<WelcomeIntroScreen> createState() => _WelcomeIntroScreenState();
}

class _WelcomeIntroScreenState extends State<WelcomeIntroScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<IntroSlideData> _slides = const [
    IntroSlideData(
      imageAsset: 'assets/intro/clean_bg_1.jpg',
      title: "A safe space for what\nyou can't say out loud.",
      subtitle: "Nuvin listens — gently, without\njudgment, whenever you need.",
      fallbackColor: Color(0xFF4A4E54),
    ),
    IntroSlideData(
      imageAsset: 'assets/intro/clean_bg_2.jpg',
      title: "Talk, type,\nor simply breathe.",
      subtitle: "Open a chat, make a call,\nor sit together in quiet.",
      fallbackColor: Color(0xFF55654C),
    ),
    IntroSlideData(
      imageAsset: 'assets/intro/clean_bg_3.jpg',
      title: "Little nudges\nfor your day.",
      subtitle: "Medicines, birthdays, the small things —\nI'll remember with you.",
      fallbackColor: Color(0xFF5A6660),
    ),
  ];

  void _onNext() {
    if (_currentIndex < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      widget.onGetStarted();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Carousel Slides
          PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Background Image with Fallback Color
                  Container(
                    color: slide.fallbackColor,
                    child: Image.asset(
                      slide.imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                slide.fallbackColor,
                                const Color(0xFF10192A),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Atmospheric Dark Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.12),
                          Colors.black.withOpacity(0.08),
                          Colors.black.withOpacity(0.55),
                          Colors.black.withOpacity(0.88),
                        ],
                        stops: const [0.0, 0.35, 0.68, 1.0],
                      ),
                    ),
                  ),

                  // Slide Typography (Positioned in lower half)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Elegant Headline (Max 2 rows)
                          Text(
                            slide.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 27,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                              height: 1.22,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Subtitle (Max 2 rows)
                          Text(
                            slide.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withOpacity(0.92),
                              height: 1.42,
                            ),
                          ),

                          // Reserved space for bottom controls
                          const SizedBox(height: 160),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Bottom Controls (Dots, Continue Button, Skip)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Carousel Indicator Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final isActive = i == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3.5),
                        width: isActive ? 30 : 6.5,
                        height: isActive ? 4.5 : 6.5,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),

                  // Continue Button
                  InkWell(
                    onTap: _onNext,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      height: 56,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFBF9),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'Continue',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF1A1A1A),
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Skip Action
                  TextButton(
                    onPressed: widget.onSkipToLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      _currentIndex == _slides.length - 1
                          ? 'I already have an account'
                          : 'Skip',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
