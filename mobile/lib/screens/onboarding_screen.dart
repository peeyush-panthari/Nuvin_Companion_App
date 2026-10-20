import 'package:flutter/material.dart';
import '../models/user_profile.dart';

class OnboardingScreen extends StatefulWidget {
  final Function(UserProfile profile) onOnboardingComplete;

  const OnboardingScreen({super.key, required this.onOnboardingComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _showForm = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companionNameController = TextEditingController(text: 'Nuvin');
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  String _selectedAgeBand = '55-64';
  final String _selectedGender = 'female';
  final String _selectedLocale = 'en-IN';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: !_showForm ? _buildInitialChoiceView() : _buildFormView(),
        ),
      ),
    );
  }

  Widget _buildInitialChoiceView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.favorite_rounded, size: 72, color: Color(0xFF3B82F6)),
        const SizedBox(height: 20),
        const Text(
          "Welcome to Nuvin",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 12),
        const Text(
          "Your personal, trusted everyday companion and assistant.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 48),
        const Text(
          "How would you prefer to get started?",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () {
            // Voice Onboarding trigger
            _companionNameController.text = "Nuvin";
            _submitProfile(isVoiceSetup: true);
          },
          icon: const Icon(Icons.mic_rounded, size: 28),
          label: const Text("Talk to Set Up (Voice)", style: TextStyle(fontSize: 18)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _showForm = true;
            });
          },
          icon: const Icon(Icons.keyboard_rounded, size: 28),
          label: const Text("Type and Fill In Details", style: TextStyle(fontSize: 18)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1E293B),
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showForm = false),
              ),
              const Text("Setup Your Companion", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField("Your Name", _nameController, hint: "e.g., Ramesh Sharma"),
          const SizedBox(height: 16),
          _buildTextField("Your Phone Number", _phoneController, hint: "+91 9876543210"),
          const SizedBox(height: 16),
          _buildTextField("Companion's Name", _companionNameController, hint: "Name your companion (Default: Nuvin)"),
          const SizedBox(height: 16),
          const Text("Your Age Band", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedAgeBand,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: const [
              DropdownMenuItem(value: '18-34', child: Text("18–34 years (Ear Companion)")),
              DropdownMenuItem(value: '35-54', child: Text("35–54 years (Ear Companion)")),
              DropdownMenuItem(value: '55-64', child: Text("55–64 years (Active Elder Companion)")),
              DropdownMenuItem(value: '65-74', child: Text("65–74 years (Elder Companion)")),
              DropdownMenuItem(value: '75+', child: Text("75+ years (Elder Companion)")),
            ],
            onChanged: (val) => setState(() => _selectedAgeBand = val!),
          ),
          const SizedBox(height: 16),
          _buildTextField("Primary Emergency Contact Name", _emergencyNameController, hint: "e.g., Pooja (Daughter)"),
          const SizedBox(height: 16),
          _buildTextField("Emergency Contact Phone", _emergencyPhoneController, hint: "+91 9876543211"),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _submitProfile(isVoiceSetup: false),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Complete Setup & Start", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  void _submitProfile({required bool isVoiceSetup}) {
    bool isElder = ['55-64', '65-74', '75+'].contains(_selectedAgeBand);
    String companion = _companionNameController.text.trim().isNotEmpty
        ? _companionNameController.text.trim()
        : 'Nuvin';

    final profile = UserProfile(
      id: 'local_user_${DateTime.now().millisecondsSinceEpoch}',
      phoneE164: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : '+919999999999',
      displayName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Friend',
      persona: isElder ? 'elder' : 'ear',
      ageBand: _selectedAgeBand,
      gender: _selectedGender,
      companionName: companion,
      companionGender: _selectedGender,
      preferredTone: isElder ? 'respectful' : 'friendly',
      locale: _selectedLocale,
      wakeWordPhrase: 'Hey $companion',
      emergencyContacts: [
        if (_emergencyNameController.text.isNotEmpty)
          EmergencyContact(
            id: 'c1',
            displayName: _emergencyNameController.text.trim(),
            relationship: 'Family',
            phoneE164: _emergencyPhoneController.text.trim(),
          ),
      ],
    );

    widget.onOnboardingComplete(profile);
  }
}
