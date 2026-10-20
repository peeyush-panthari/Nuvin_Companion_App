import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../models/open_ui_card.dart';

class OpenUiCardWidget extends StatefulWidget {
  final OpenUICard card;
  final bool isElder;
  final Function(String action, Map<String, dynamic> data)? onAction;

  const OpenUiCardWidget({
    super.key,
    required this.card,
    this.isElder = false,
    this.onAction,
  });

  @override
  State<OpenUiCardWidget> createState() => _OpenUiCardWidgetState();
}

class _OpenUiCardWidgetState extends State<OpenUiCardWidget> {
  bool _medicineExpanded = true;
  String _medicationStatus = 'due'; // 'due', 'taken', 'snoozed', 'skipped', 'help'

  @override
  Widget build(BuildContext context) {
    switch (widget.card.type) {
      case 'medication_card':
      case 'medication':
        return _buildMedicationCard();
      case 'memory_vault_card':
      case 'memory':
        return _buildMemoryCard();
      case 'crisis_card':
      case 'crisis':
        return _buildCrisisCard();
      default:
        return _buildGenericCard();
    }
  }

  Widget _buildMedicationCard() {
    final statusCopy = {
      'due': 'Due this afternoon',
      'taken': 'Marked as taken',
      'snoozed': 'Snoozed for 15 minutes',
      'skipped': 'Skipped for today',
      'help': 'Help requested',
    }[_medicationStatus] ?? 'Due this afternoon';

    final touchHeight = widget.isElder ? 54.0 : 44.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvinColors.card,
        borderRadius: BorderRadius.circular(NuvinColors.radius),
        border: Border.all(color: NuvinColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: NuvinColors.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.medication_rounded,
                  color: NuvinColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.card.title.isNotEmpty
                          ? widget.card.title
                          : 'Afternoon blood pressure medicine',
                      style: TextStyle(
                        fontSize: widget.isElder ? 19 : 16,
                        fontWeight: FontWeight.w700,
                        color: NuvinColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusCopy,
                      style: const TextStyle(
                        fontSize: 12,
                        color: NuvinColors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _medicineExpanded = !_medicineExpanded),
                icon: Icon(
                  _medicineExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: NuvinColors.mutedForeground,
                ),
              ),
            ],
          ),
          if (_medicineExpanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NuvinColors.secondary.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.card.data['detail'] ?? 'Amlodipine 5mg · 1 tablet with warm water',
                style: TextStyle(
                  fontSize: widget.isElder ? 17 : 14,
                  color: NuvinColors.text,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_medicationStatus == 'due')
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _actionButton(
                    label: 'Taken',
                    icon: Icons.check_circle_outline,
                    bg: NuvinColors.success.withOpacity(0.18),
                    fg: NuvinColors.success,
                    border: NuvinColors.success.withOpacity(0.4),
                    minHeight: touchHeight,
                    onTap: () {
                      setState(() => _medicationStatus = 'taken');
                      widget.onAction?.call('taken', {'medicine': 'Amlodipine 5mg'});
                    },
                  ),
                  _actionButton(
                    label: 'Snooze 15m',
                    icon: Icons.schedule_outlined,
                    bg: NuvinColors.secondary,
                    fg: NuvinColors.text,
                    border: NuvinColors.border,
                    minHeight: touchHeight,
                    onTap: () {
                      setState(() => _medicationStatus = 'snoozed');
                      widget.onAction?.call('snooze', {'minutes': 15});
                    },
                  ),
                  _actionButton(
                    label: 'Skip today',
                    icon: Icons.skip_next_outlined,
                    bg: NuvinColors.secondary,
                    fg: NuvinColors.mutedForeground,
                    border: NuvinColors.border,
                    minHeight: touchHeight,
                    onTap: () {
                      setState(() => _medicationStatus = 'skipped');
                      widget.onAction?.call('skip', {});
                    },
                  ),
                  _actionButton(
                    label: 'Need help',
                    icon: Icons.help_outline,
                    bg: NuvinColors.destructive.withOpacity(0.15),
                    fg: NuvinColors.destructive,
                    border: NuvinColors.destructive.withOpacity(0.35),
                    minHeight: touchHeight,
                    onTap: () {
                      setState(() => _medicationStatus = 'help');
                      widget.onAction?.call('help', {});
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _medicationStatus == 'taken' ? Icons.check_circle : Icons.info,
                        color: _medicationStatus == 'taken'
                            ? NuvinColors.success
                            : NuvinColors.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusCopy,
                        style: TextStyle(
                          color: _medicationStatus == 'taken'
                              ? NuvinColors.success
                              : NuvinColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: widget.isElder ? 16 : 13,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() => _medicationStatus = 'due'),
                    child: const Text('Undo', style: TextStyle(color: NuvinColors.primary)),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    required Color border,
    required double minHeight,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: widget.isElder ? 16 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryCard() {
    final text = widget.card.data['text'] ??
        widget.card.data['detail'] ??
        "Grandson Aarav's birthday is coming up on October 24th.";

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvinColors.card,
        borderRadius: BorderRadius.circular(NuvinColors.radius),
        border: Border.all(color: NuvinColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvinColors.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bookmark_outline,
                  color: NuvinColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memory saved',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: NuvinColors.text,
                      ),
                    ),
                    Text(
                      'Only on this device',
                      style: TextStyle(
                        fontSize: 12,
                        color: NuvinColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Nuvin noted: “$text”',
            style: TextStyle(
              fontSize: widget.isElder ? 17 : 14,
              fontStyle: FontStyle.italic,
              color: NuvinColors.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () {
                widget.onAction?.call('forget', widget.card.data);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.delete_outline, color: NuvinColors.dangerMuted, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Forget this',
                      style: TextStyle(
                        color: NuvinColors.dangerMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildCrisisCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvinColors.card,
        borderRadius: BorderRadius.circular(NuvinColors.radius),
        border: Border.all(color: NuvinColors.primary.withOpacity(0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvinColors.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: NuvinColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'We are here with you',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: NuvinColors.text,
                      ),
                    ),
                    Text(
                      'You can speak to a trained person',
                      style: TextStyle(
                        fontSize: 12,
                        color: NuvinColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'If you’re in immediate danger, call your local emergency number.',
            style: TextStyle(
              fontSize: widget.isElder ? 16 : 14,
              color: NuvinColors.text,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _helplinePill('Tele-MANAS · 14416'),
              _helplinePill('KIRAN · 1800-599-0019'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _helplinePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NuvinColors.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NuvinColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call, color: NuvinColors.primary, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: NuvinColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvinColors.card,
        borderRadius: BorderRadius.circular(NuvinColors.radius),
        border: Border.all(color: NuvinColors.border),
      ),
      child: Text(
        widget.card.title,
        style: const TextStyle(color: NuvinColors.text, fontWeight: FontWeight.w600),
      ),
    );
  }
}
