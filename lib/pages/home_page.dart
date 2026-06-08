import 'package:flutter/material.dart';
import '../models/card_info.dart';
import '../theme/app_theme.dart';
import '../widgets/card_template_widgets.dart';
import 'scan_page.dart';
import 'card_editor_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.darkBg, Color(0xFF12121A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium Top Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WELCOME BACK',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Card Scanner Pro',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontSize: 26,
                                color: Colors.white,
                              ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderCol),
                      ),
                      child: const Icon(Icons.business_center, color: AppTheme.primary, size: 24),
                    )
                  ],
                ),
                const SizedBox(height: 32),

                // Hero Scanner Action Card
                _buildHeroScannerCard(context),
                const SizedBox(height: 36),

                // Template Gallery Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DESIGN TEMPLATES',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const Icon(Icons.dashboard_customize, color: AppTheme.textSecondary, size: 18),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTemplateGrid(context),

                const SizedBox(height: 32),

                // Quick Tips Section
                _buildTipsSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroScannerCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppTheme.cyberGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(76), // 0.3 opacity -> 76
            blurRadius: 25,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          // Background abstract patterns
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.qr_code_scanner,
              size: 150,
              color: Colors.white.withAlpha(25), // 0.1 opacity -> 25
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.document_scanner, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'AI CARD READER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Instantly Scan & Populate Templates',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload or capture any customer ID card. Our on-device OCR extracts details and crops profile photos automatically.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(204), // 0.8 opacity -> 204
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ScanPage()),
                    );
                  },
                  icon: const Icon(Icons.camera_alt, color: AppTheme.primary, size: 18),
                  label: const Text('SCAN NEW CARD'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateGrid(BuildContext context) {
    final templates = [
      _TemplateItem(
        type: CardTemplateType.bangladeshNid,
        title: 'Bangladesh NID',
        subtitle: 'Horizontal NID template layout matching government design.',
        icon: Icons.credit_card_outlined,
        color: Colors.green,
      ),
      _TemplateItem(
        type: CardTemplateType.corporate,
        title: 'Corporate ID',
        subtitle: 'Vertical, modern and professional badge style.',
        icon: Icons.badge_outlined,
        color: const Color(0xFF0F172A),
      ),
      _TemplateItem(
        type: CardTemplateType.vipClub,
        title: 'VIP Elite Card',
        subtitle: 'Horizontal obsidian black and glowing gold.',
        icon: Icons.stars_outlined,
        color: AppTheme.accentGold,
      ),
      _TemplateItem(
        type: CardTemplateType.student,
        title: 'Student Pass',
        subtitle: 'Vertical, clean layout with dual color theme.',
        icon: Icons.school_outlined,
        color: const Color(0xFF0083B0),
      ),
      _TemplateItem(
        type: CardTemplateType.glassmorphic,
        title: 'Tech Pass',
        subtitle: 'Horizontal glassmorphic frosted neon design.',
        icon: Icons.nfc_outlined,
        color: AppTheme.primary,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.85,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final t = templates[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CardEditorPage(
                  initialInfo: const CardInfo(),
                  selectedTemplate: t.type,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderCol, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.color.withAlpha(25), // 0.1 opacity -> 25
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(t.icon, color: t.color, size: 22),
                ),
                const Spacer(),
                Text(
                  t.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Text(
                      'Use Template',
                      style: TextStyle(
                        color: AppTheme.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: AppTheme.secondary, size: 11),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTipsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg.withAlpha(127), // 0.5 opacity -> 127
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderCol.withAlpha(127)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: AppTheme.accentGold, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pro Tip for High Accuracy',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ensure the card is placed on a flat, contrasting background under bright light. Hold the camera steady when capturing.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _TemplateItem {
  final CardTemplateType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  _TemplateItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
