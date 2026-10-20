import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../models/user_profile.dart';
import '../widgets/nuvin_mark.dart';

class OnboardingWizardScreen extends StatefulWidget {
  final UserProfile initialProfile;
  final Function(UserProfile updatedProfile) onComplete;
  final VoidCallback onSkip;

  const OnboardingWizardScreen({
    super.key,
    required this.initialProfile,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  int _currentStep = 0;
  final int _totalSteps = 5;

  // Form Controllers
  late TextEditingController _userNameController;
  late TextEditingController _companionNameController;
  late TextEditingController _ageController;
  late TextEditingController _kinNameController;
  late TextEditingController _kinPhoneController;

  bool _isElder = true;
  String _selectedOccupation = 'Retired & Relaxing';
  final Set<String> _selectedTopics = {
    'Daily Medicines & Health',
    'Family & Relationships',
  };

  final List<String> _companionSuggestions = ['Nuvin', 'Saathi', 'Mitra'];

  final List<Map<String, String>> _occupations = [
    {
      'title': 'Retired & Relaxing',
      'icon': '🏡',
      'sub': 'Enjoying free time, family, and peaceful days',
    },
    {
      'title': 'Homemaker',
      'icon': '🍳',
      'sub': 'Caring for home, family, and daily cooking',
    },
    {
      'title': 'Working Professional',
      'icon': '💼',
      'sub': 'Navigating career, meetings, and busy hours',
    },
    {
      'title': 'Student',
      'icon': '🎓',
      'sub': 'Studies, exams, and learning new things',
    },
    {
      'title': 'Taking a Quiet Break',
      'icon': '🌿',
      'sub': 'Healing, resting, or in a transition phase',
    },
    {
      'title': 'Self-Employed / Business',
      'icon': '✍️',
      'sub': 'Independent projects and entrepreneurship',
    },
  ];

  final List<Map<String, String>> _topicOptions = [
    {'title': 'Daily Medicines & Health', 'icon': '💊'},
    {'title': 'Family & Relationships', 'icon': '👨‍👩‍👧'},
    {'title': 'Morning & Evening Routines', 'icon': '🌅'},
    {'title': 'Reminiscing & Stories', 'icon': '📖'},
    {'title': 'Stress Relief & Quiet Time', 'icon': '😌'},
    {'title': 'Casual Daily Chai Chats', 'icon': '☕'},
    {'title': 'Books, News & Daily World', 'icon': '📰'},
    {'title': 'Gentle Bedtime Sleep Reflections', 'icon': '🌙'},
  ];

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController(
      text: widget.initialProfile.displayName != 'Nuvin member' &&
              widget.initialProfile.displayName != 'Friend'
          ? widget.initialProfile.displayName
          : '',
    );
    _companionNameController = TextEditingController(
      text: widget.initialProfile.companionName.isNotEmpty
          ? widget.initialProfile.companionName
          : 'Nuvin',
    );
    _ageController = TextEditingController(
      text: widget.initialProfile.isElder ? '62' : '29',
    );
    _kinNameController = TextEditingController(
      text: widget.initialProfile.emergencyContacts.isNotEmpty
          ? widget.initialProfile.emergencyContacts.first.displayName
          : '',
    );
    _kinPhoneController = TextEditingController(
      text: widget.initialProfile.emergencyContacts.isNotEmpty
          ? widget.initialProfile.emergencyContacts.first.phoneE164
          : '',
    );
    _isElder = widget.initialProfile.isElder;
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _companionNameController.dispose();
    _ageController.dispose();
    _kinNameController.dispose();
    _kinPhoneController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      _saveAndFinish();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  void _saveAndFinish() {
    final finalName = _userNameController.text.trim().isNotEmpty
        ? _userNameController.text.trim()
        : 'Nuvin member';
    final finalCompanion = _companionNameController.text.trim().isNotEmpty
        ? _companionNameController.text.trim()
        : 'Nuvin';
    final ageParsed = int.tryParse(_ageController.text.trim()) ?? (_isElder ? 62 : 29);
    final isElderly = _isElder || ageParsed >= 55;

    List<EmergencyContact> finalContacts = [];
    final kinName = _kinNameController.text.trim();
    final kinPhone = _kinPhoneController.text.trim();
    if (kinName.isNotEmpty) {
      finalContacts.add(EmergencyContact(
        id: 'ec-primary',
        displayName: kinName,
        relationship: 'Trusted Kin',
        phoneE164: kinPhone.isNotEmpty ? kinPhone : '+91 98765 43210',
      ));
    }

    final updated = widget.initialProfile.copyWith(
      displayName: finalName,
      companionName: finalCompanion,
      persona: isElderly ? 'elder' : 'ear',
      ageBand: isElderly ? '55-64' : '25-34',
      occupation: _selectedOccupation,
      talkTopics: _selectedTopics.toList(),
      emergencyContacts: finalContacts,
    );

    widget.onComplete(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvinColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: NuvinColors.text),
                      onPressed: _prevStep,
                    )
                  else
                    const NuvinMark(size: 32),
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(
                        color: NuvinColors.mutedForeground,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Progress Rail
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: NuvinColors.secondary,
                  valueColor: const AlwaysStoppedAnimation<Color>(NuvinColors.primary),
                  minHeight: 4,
                ),
              ),
            ),

            // Step Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Kicker
                    Text(
                      'STEP ${_currentStep + 1} OF $_totalSteps',
                      style: const TextStyle(
                        color: NuvinColors.mutedForeground,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Step Renderers
                    if (_currentStep == 0) _buildStepName(),
                    if (_currentStep == 1) _buildStepAgeAndPersona(),
                    if (_currentStep == 2) _buildStepOccupation(),
                    if (_currentStep == 3) _buildStepTopics(),
                    if (_currentStep == 4) _buildStepTrustedContact(),
                  ],
                ),
              ),
            ),

            // Bottom Navigation CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: InkWell(
                onTap: _nextStep,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  height: 54,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: NuvinColors.primary,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentStep == _totalSteps - 1
                            ? 'Complete Setup & Start Talking'
                            : 'Continue',
                        style: const TextStyle(
                          color: NuvinColors.primaryForeground,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: NuvinColors.primaryForeground,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 1: Name & Companion Name
  Widget _buildStepName() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What should I call you?',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF1F5F8),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'A friendly name you feel comfortable hearing.',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 14),
        ),
        const SizedBox(height: 24),

        const Text(
          'YOUR NAME',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _userNameController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration('e.g. Ramesh or Pooja'),
        ),
        const SizedBox(height: 28),

        const Text(
          'COMPANION NAME',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'What would you like to call me?',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _companionNameController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration('Companion Name (Default: Nuvin)'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: _companionSuggestions.map((suggestion) {
            final isSelected = _companionNameController.text == suggestion;
            return ChoiceChip(
              label: Text(suggestion),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _companionNameController.text = suggestion;
                });
              },
              selectedColor: const Color(0xFF48CAE4),
              backgroundColor: const Color(0xFF162138),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF0B132B) : const Color(0xFFAAB7C9),
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF48CAE4) : const Color(0xFF28364F),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP 2: Age & Persona
  Widget _buildStepAgeAndPersona() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How old are you?',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF1F5F8),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This adapts text size, touch targets, and conversation tone. Stored privately on this device.',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 14),
        ),
        const SizedBox(height: 22),

        const Text(
          'ENTER YOUR AGE',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration('e.g. 62 or 29'),
          onChanged: (val) {
            final parsed = int.tryParse(val);
            if (parsed != null) {
              setState(() {
                _isElder = parsed >= 55;
              });
            }
          },
        ),
        const SizedBox(height: 24),

        const Text(
          'RECOMMENDED PERSONA',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        // Elder Persona Card
        InkWell(
          onTap: () => setState(() => _isElder = true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isElder
                  ? const Color(0xFF48CAE4).withOpacity(0.12)
                  : const Color(0xFF131E33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isElder ? const Color(0xFF48CAE4) : const Color(0xFF28364F),
                width: _isElder ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                const Text('🧓', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Elder Care & Support (55+)',
                        style: TextStyle(
                          color: Color(0xFFF1F5F8),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Respectful tone (Ji / Namaste), larger text, medicine reminders, and daily check-ins.',
                        style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (_isElder)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF48CAE4), size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Everyday Ear Persona Card
        InkWell(
          onTap: () => setState(() => _isElder = false),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: !_isElder
                  ? const Color(0xFF48CAE4).withOpacity(0.12)
                  : const Color(0xFF131E33),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: !_isElder ? const Color(0xFF48CAE4) : const Color(0xFF28364F),
                width: !_isElder ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                const Text('🎧', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Everyday Ear (20–50)',
                        style: TextStyle(
                          color: Color(0xFFF1F5F8),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Friendly, attentive sounding board for daily stress, work thoughts, and calm reflection.',
                        style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (!_isElder)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF48CAE4), size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // STEP 3: What do you do? (Occupation)
  Widget _buildStepOccupation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What fills your days?',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF1F5F8),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Helps Nuvin understand your daily rhythm, active hours, and free moments.',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 14),
        ),
        const SizedBox(height: 20),

        ..._occupations.map((occ) {
          final isSelected = _selectedOccupation == occ['title'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() => _selectedOccupation = occ['title']!),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF48CAE4).withOpacity(0.12)
                      : const Color(0xFF131E33),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF48CAE4) : const Color(0xFF28364F),
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Text(occ['icon']!, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            occ['title']!,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F8),
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            occ['sub']!,
                            style: const TextStyle(
                              color: Color(0xFFAAB7C9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF48CAE4), size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // STEP 4: Topics
  Widget _buildStepTopics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What would you like to talk about?',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF1F5F8),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select all that interest you. You can chat about anything at any time.',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 14),
        ),
        const SizedBox(height: 20),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _topicOptions.map((topic) {
            final title = topic['title']!;
            final isSelected = _selectedTopics.contains(title);
            return FilterChip(
              avatar: Text(topic['icon']!, style: const TextStyle(fontSize: 16)),
              label: Text(title),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTopics.add(title);
                  } else {
                    if (_selectedTopics.length > 1) {
                      _selectedTopics.remove(title);
                    }
                  }
                });
              },
              backgroundColor: const Color(0xFF131E33),
              selectedColor: const Color(0xFF48CAE4).withOpacity(0.2),
              checkmarkColor: const Color(0xFF48CAE4),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF48CAE4) : const Color(0xFFE6EDF4),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF48CAE4) : const Color(0xFF28364F),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP 5: Trusted Contact
  Widget _buildStepTrustedContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add a person you trust',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF1F5F8),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Optional. In case of an emergency or distress, Nuvin can reach out to this person.',
          style: TextStyle(color: Color(0xFFAAB7C9), fontSize: 14),
        ),
        const SizedBox(height: 24),

        const Text(
          'CONTACT NAME · OPTIONAL',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _kinNameController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration('e.g. Aarav Sharma (Son) or Pooja'),
        ),
        const SizedBox(height: 20),

        const Text(
          'PHONE NUMBER · OPTIONAL',
          style: TextStyle(
            color: Color(0xFF8F9FB5),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _kinPhoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: _inputDecoration('+91 98765 43210'),
        ),
        const SizedBox(height: 24),

        // Device privacy note
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.lock_outline_rounded, color: Color(0xFF48CAE4), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Personal setup and contacts are stored strictly on this device. Never shared without your explicit consent.',
                style: TextStyle(color: Color(0xFF8F9FB5), fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: NuvinColors.mutedForeground.withOpacity(0.55), fontSize: 14),
      filled: true,
      fillColor: NuvinColors.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NuvinColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NuvinColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NuvinColors.primary, width: 1.5),
      ),
    );
  }
}
