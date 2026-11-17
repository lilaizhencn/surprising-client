import 'package:material_ui/material_ui.dart';
import 'aetern_logo.dart';
import 'tokens.dart';

class DesignSystemGalleryPage extends StatelessWidget {
  const DesignSystemGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bgVoid,
      appBar: AppBar(
        backgroundColor: t.bgElevated1,
        title: const AeternBrandLockup(markSize: 24, fontSize: 16),
      ),
      body: ListView(
        padding: const EdgeInsets.all(SurprisingTokens.space4),
        children: [
          _SectionTitle(title: '1. Deep-Space Elevations (5 Levels)', tokens: t),
          Wrap(
            spacing: SurprisingTokens.space3,
            runSpacing: SurprisingTokens.space3,
            children: [
              _SwatchCard(label: 'bgVoid', color: t.bgVoid, tokens: t),
              _SwatchCard(label: 'bgElevated1', color: t.bgElevated1, tokens: t),
              _SwatchCard(label: 'bgElevated2', color: t.bgElevated2, tokens: t),
              _SwatchCard(label: 'bgElevated3', color: t.bgElevated3, tokens: t),
              _SwatchCard(label: 'bgElevated4', color: t.bgElevated4, tokens: t),
            ],
          ),
          const SizedBox(height: SurprisingTokens.space6),
          _SectionTitle(title: '2. Aurora Spectrum & 3 Gradients', tokens: t),
          Wrap(
            spacing: SurprisingTokens.space3,
            runSpacing: SurprisingTokens.space3,
            children: [
              _SwatchCard(label: 'auroraCyan', color: t.auroraCyan, tokens: t),
              _SwatchCard(label: 'auroraMagenta', color: t.auroraMagenta, tokens: t),
              _SwatchCard(label: 'auroraViolet', color: t.auroraViolet, tokens: t),
              _SwatchCard(label: 'auroraAcid', color: t.auroraAcid, tokens: t),
              _SwatchCard(label: 'auroraCorona', color: t.auroraCorona, tokens: t),
              _GradientCard(label: 'auroraPrimary', gradient: t.auroraPrimaryGradient, tokens: t),
              _GradientCard(label: 'auroraWarm', gradient: t.auroraWarmGradient, tokens: t),
              _GradientCard(label: 'auroraCool', gradient: t.auroraCoolGradient, tokens: t),
            ],
          ),
          const SizedBox(height: SurprisingTokens.space6),
          _SectionTitle(title: '3. Semantic Market Colors & Glow (0-3)', tokens: t),
          Wrap(
            spacing: SurprisingTokens.space3,
            runSpacing: SurprisingTokens.space3,
            children: [
              _SemanticTile(label: '▲ UP / LONG', color: t.upBase, bg: t.upSoftBg, tokens: t),
              _SemanticTile(label: '▼ DOWN / SHORT', color: t.downBase, bg: t.downSoftBg, tokens: t),
              for (final level in [0, 1, 2, 3])
                Container(
                  width: 140,
                  padding: const EdgeInsets.all(SurprisingTokens.space3),
                  decoration: BoxDecoration(
                    color: t.bgElevated2,
                    borderRadius: BorderRadius.circular(SurprisingTokens.radiusSm),
                    border: Border.all(color: t.borderDefault),
                    boxShadow: t.glow(level),
                  ),
                  child: Text(
                    'glow-$level',
                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.tokens});
  final String title;
  final SurprisingTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SurprisingTokens.space3),
      child: Text(
        title,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: SurprisingTokens.textXl,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SwatchCard extends StatelessWidget {
  const _SwatchCard({required this.label, required this.color, required this.tokens});
  final String label;
  final Color color;
  final SurprisingTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(SurprisingTokens.space2),
      decoration: BoxDecoration(
        color: tokens.bgElevated1,
        borderRadius: BorderRadius.circular(SurprisingTokens.radiusSm),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(SurprisingTokens.radiusXs),
              border: Border.all(color: tokens.borderSubtle),
            ),
          ),
          const SizedBox(height: SurprisingTokens.space2),
          Text(label, style: TextStyle(color: tokens.textPrimary, fontSize: SurprisingTokens.textXs)),
        ],
      ),
    );
  }
}

class _GradientCard extends StatelessWidget {
  const _GradientCard({required this.label, required this.gradient, required this.tokens});
  final String label;
  final LinearGradient gradient;
  final SurprisingTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(SurprisingTokens.space2),
      decoration: BoxDecoration(
        color: tokens.bgElevated1,
        borderRadius: BorderRadius.circular(SurprisingTokens.radiusSm),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(SurprisingTokens.radiusXs),
            ),
          ),
          const SizedBox(height: SurprisingTokens.space2),
          Text(label, style: TextStyle(color: tokens.textPrimary, fontSize: SurprisingTokens.textXs)),
        ],
      ),
    );
  }
}

class _SemanticTile extends StatelessWidget {
  const _SemanticTile({
    required this.label,
    required this.color,
    required this.bg,
    required this.tokens,
  });
  final String label;
  final Color color;
  final Color bg;
  final SurprisingTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(SurprisingTokens.space3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SurprisingTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: SurprisingTokens.textSm,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
