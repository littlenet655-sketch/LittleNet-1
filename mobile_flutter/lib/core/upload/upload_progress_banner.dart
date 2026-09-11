import 'package:flutter/material.dart';
import 'upload_manager.dart';

/// Clean, responsive upload progress banner for LittleNet kids & feeds.
/// Floats or docks at the top of the screen when an upload is in flight.
class UploadProgressBanner extends StatelessWidget {
  const UploadProgressBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UploadManager.instance,
      builder: (context, _) {
        final state = UploadManager.instance.state;
        if (state.stage == UploadStage.idle) {
          return const SizedBox.shrink();
        }

        final (bgColor, iconData, iconColor) = switch (state.stage) {
          UploadStage.creatingSession || UploadStage.uploading => (
              const Color(0xFF1E293B), // Slate 800
              Icons.cloud_upload_outlined,
              const Color(0xFF60A5FA), // Blue 400
            ),
          UploadStage.processing => (
              const Color(0xFF312E81), // Indigo 900
              Icons.shield_outlined,
              const Color(0xFFA5B4FC), // Indigo 300
            ),
          UploadStage.allowed => (
              const Color(0xFF065F46), // Emerald 800
              Icons.check_circle_outline_rounded,
              const Color(0xFF34D399), // Emerald 400
            ),
          UploadStage.review => (
              const Color(0xFF78350F), // Amber 900
              Icons.visibility_outlined,
              const Color(0xFFFBBF24), // Amber 400
            ),
          UploadStage.blocked || UploadStage.failed => (
              const Color(0xFF881337), // Rose 900
              Icons.error_outline_rounded,
              const Color(0xFFFB7185), // Rose 400
            ),
          UploadStage.idle => (
              Colors.transparent,
              Icons.info_outline,
              Colors.white,
            ),
        };

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      // Status Icon / Mini Spinner
                      if (state.stage == UploadStage.uploading ||
                          state.stage == UploadStage.creatingSession ||
                          state.stage == UploadStage.processing) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            value: state.stage == UploadStage.uploading
                                ? (state.progress > 0 ? state.progress : null)
                                : null,
                            color: iconColor,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ] else ...[
                        Icon(iconData, size: 20, color: iconColor),
                      ],
                      const SizedBox(width: 12),

                      // Status Message
                      Expanded(
                        child: Text(
                          state.message.isNotEmpty
                              ? state.message
                              : 'Processing upload...',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      // Actions: Retry if failed, or Dismiss button
                      if (state.isFailed) ...[
                        TextButton(
                          onPressed: () => UploadManager.instance.retry(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],

                      // Close / Dismiss button
                      if (state.isCompleted || state.isFailed) ...[
                        GestureDetector(
                          onTap: () => UploadManager.instance.dismiss(),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Mini Progress Bar during upload
                if (state.stage == UploadStage.uploading &&
                    state.progress > 0.0 &&
                    state.progress < 1.0) ...[
                  LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
