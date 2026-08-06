import 'package:flutter/material.dart';

class AnswerButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onPressed;

  const AnswerButton({
    super.key,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.isDisabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isDisabled
        ? Colors.grey.shade800
        : isSelected
            ? color
            : color.withOpacity(0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onPressed,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: effectiveColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 4,
            ),
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: isDisabled ? Colors.white38 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
