import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../i18n/client_messages.dart';

String affiliateRegistrationLink(String baseUrl, String inviteCode) {
  var origin = baseUrl.trim();
  while (origin.endsWith('/')) {
    origin = origin.substring(0, origin.length - 1);
  }
  return '$origin/auth/register?invite=${Uri.encodeQueryComponent(inviteCode.trim())}';
}

String formatAffiliateRatePercent(double value) {
  if (!value.isFinite || value <= 0) return '0';
  final rounded = value.truncateToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return rounded;
}

/// 与 Web 端 `posterGenerator.ts` 和 Telegram Bot 保持 1:1 视觉与数据逻辑一致的专属邀请函海报。
class AffiliateInvitationPosterCard extends StatelessWidget {
  const AffiliateInvitationPosterCard({
    super.key,
    required this.inviteCode,
    required this.inviteLink,
    required this.rebateRatePercent,
    required this.userId,
  });

  final String inviteCode;
  final String inviteLink;
  final double rebateRatePercent;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final rateLabel = formatAffiliateRatePercent(rebateRatePercent);
    final clippedLink = inviteLink.length > 36
        ? '${inviteLink.substring(0, 33)}...'
        : inviteLink;

    return AspectRatio(
      aspectRatio: 900 / 1360,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 900,
          height: 1360,
          child: Stack(
            children: [
              // Deep obsidian institutional background + ambient glows + grid
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: [0, 0.5, 1],
                      colors: [
                        Color(0xFF070912),
                        Color(0xFF0D1324),
                        Color(0xFF070910),
                      ],
                    ),
                  ),
                  child: CustomPaint(painter: _PosterBackdropPainter()),
                ),
              ),
              // Outer champagne-gold hairline frame
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0x59F5C451),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(76, 76, 76, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'AETERN',
                            style: TextStyle(
                              color: Color(0xFFF5C451),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Container(
                            width: 220,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0x24F5C451),
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: const Color(0x73F5C451),
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              'EXCLUSIVE INVITATION',
                              style: TextStyle(
                                color: Color(0xFFF9DFA0),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 54),
                      // Main headline
                      const Text(
                        '受邀开启机构级',
                        style: TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          height: 1.22,
                        ),
                      ),
                      const Text(
                        '数字资产交易体验',
                        style: TextStyle(
                          color: Color(0xFFF5C451),
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          height: 1.22,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '低延迟撮合 · 全产品线覆盖 · 透明资产托管',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 42),
                      // Three feature pillars
                      Row(
                        children: [
                          Expanded(
                            child: _pillarCard('微秒级撮合', 'Aeron 确定性核心引擎'),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _pillarCard('全产品矩阵', '现货 / 永续 / 交割 / 期权'),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _pillarCard('专属返佣', '最高 $rateLabel% 手续费回馈'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      // Centerpiece invite code card
                      Container(
                        width: double.infinity,
                        height: 236,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x24F5C451), Color(0x142DD4BF)],
                          ),
                          border: Border.all(
                            color: const Color(0x73F5C451),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '专属短邀请码',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              inviteCode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 64,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 4,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '邀请人 UID $userId · 注册即享专属返佣权益',
                              style: const TextStyle(
                                color: Color(0xFFF9DFA0),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      // Bottom QR card
                      Container(
                        width: double.infinity,
                        height: 392,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 42,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xE00F172A),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0x1FFFFFFF),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: QrImageView(
                                data: inviteLink,
                                size: 248,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF0A0D1A),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF0A0D1A),
                                ),
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                              ),
                            ),
                            const SizedBox(width: 44),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    '扫码加入 AETERN',
                                    style: TextStyle(
                                      color: Color(0xFFF8FAFC),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    '使用手机相机或浏览器扫码\n直达专属邀请注册页面',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 20,
                                      height: 1.55,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0x242DD4BF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      clippedLink,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF5EEAD4),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'AETERN · High-Performance Exchange & Derivatives',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillarCard(String title, String desc) {
    return Container(
      height: 134,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5C451),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _PosterBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final goldGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.8, 180),
        440,
        const [Color(0x38F5C451), Color(0x00F5C451)],
      );
    canvas.drawRect(Offset.zero & size, goldGlow);

    final cyanGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(140, size.height * 0.65),
        420,
        const [Color(0x242DD4BF), Color(0x002DD4BF)],
      );
    canvas.drawRect(Offset.zero & size, cyanGlow);

    final grid = Paint()
      ..color = const Color(0x09FFFFFF)
      ..strokeWidth = 1;
    for (double x = 60; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 60; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> showAffiliatePosterDialog(
  BuildContext context, {
  required String inviteCode,
  required String inviteLink,
  required double rebateRatePercent,
  required String userId,
  required Future<void> Function(String text, String label) onCopy,
}) async {
  final posterKey = GlobalKey();
  var sharing = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sharePoster() async {
            if (sharing) return;
            setDialogState(() => sharing = true);
            try {
              final boundary =
                  posterKey.currentContext?.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary == null) return;
              final image = await boundary.toImage(pixelRatio: 2.5);
              final byteData = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              if (byteData == null || !context.mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              final rateLabel = formatAffiliateRatePercent(rebateRatePercent);
              await SharePlus.instance.share(
                ShareParams(
                  title: clientLabel(context, 'AETERN 专属邀请函'),
                  text:
                      '受邀开启 AETERN 机构级数字资产交易体验，专属短邀请码：$inviteCode（最高 $rateLabel% 返佣）\n$inviteLink',
                  files: [
                    XFile.fromData(
                      byteData.buffer.asUint8List(),
                      mimeType: 'image/png',
                    ),
                  ],
                  fileNameOverrides: ['aetern-invite-$inviteCode.png'],
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            } finally {
              if (context.mounted) setDialogState(() => sharing = false);
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          clientLabel(context, '专属邀请函预览'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: clientLabel(context, '关闭'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: RepaintBoundary(
                            key: posterKey,
                            child: AffiliateInvitationPosterCard(
                              inviteCode: inviteCode,
                              inviteLink: inviteLink,
                              rebateRatePercent: rebateRatePercent,
                              userId: userId,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                onCopy(inviteLink, '专属注册链接已复制'),
                            icon: const Icon(Icons.link, size: 18),
                            label: const LText('复制链接'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: sharing ? null : sharePoster,
                            icon: sharing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.ios_share, size: 18),
                            label: const LText('分享 / 保存海报'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
