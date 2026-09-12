import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

enum ButtonVariant { primary, secondary, text, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
  });

  final String text;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;

    Widget child;
    if (isLoading) {
      child = SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(
            variant == ButtonVariant.primary || variant == ButtonVariant.danger
                ? Colors.white
                : AppColors.primary,
          ),
        ),
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
    } else {
      child = Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    Widget button;
    switch (variant) {
      case ButtonVariant.primary:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
        break;
      case ButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
        break;
      case ButtonVariant.text:
        button = TextButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
        break;
      case ButtonVariant.danger:
        button = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
            shape:
                const RoundedRectangleBorder(borderRadius: AppRadius.roundedMd),
            textStyle: AppTypography.labelLarge.copyWith(color: Colors.white),
            elevation: 0,
          ),
          onPressed: effectiveOnPressed,
          child: child,
        );
        break;
    }

    if (width != null) {
      return SizedBox(width: width, child: button);
    }
    return button;
  }
}
