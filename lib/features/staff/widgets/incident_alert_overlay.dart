import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';

enum StaffIncidentType { fire, medical }

class IncidentAlertOverlay extends StatelessWidget {
  const IncidentAlertOverlay({
    required this.type,
    required this.locationText,
    required this.onAccept,
    required this.onReject,
    super.key,
  });

  final StaffIncidentType type;
  final String locationText;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final icon = type == StaffIncidentType.fire
        ? Icons.local_fire_department
        : Icons.medical_services;
    final title = type == StaffIncidentType.fire
        ? 'URGENT: FIRE REPORTED'
        : 'URGENT: MEDICAL SOS';

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.7)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Location: $locationText',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 64, color: AppColors.background),
                  ),
                  const SizedBox(height: 34),
                  StandardButton(
                    label: 'ACCEPT & RESPOND',
                    onPressed: onAccept,
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                  ),
                  const SizedBox(height: 12),
                  StandardButton(
                    label: 'REJECT / BUSY',
                    onPressed: onReject,
                    isOutlined: true,
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