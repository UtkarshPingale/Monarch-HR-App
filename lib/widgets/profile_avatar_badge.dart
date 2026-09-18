import 'package:flutter/material.dart';

class ProfileAvatarBadge extends StatelessWidget {
  final String name;
  final bool isIncomplete;
  final double radius;
  final double borderWidth;
  final double fontSize;
  final VoidCallback? onTap;

  const ProfileAvatarBadge({
    super.key,
    required this.name,
    required this.isIncomplete,
    this.radius = 16,
    this.borderWidth = 2.5,
    this.fontSize = 13,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    const amberDark = Color(0xFF895100);
    const alertRed = Color(0xFFFF2A55);

    Widget avatarContent = CircleAvatar(
      radius: radius,
      backgroundColor: amberDark,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
        ),
      ),
    );

    Widget widgetToRender;

    if (!isIncomplete) {
      widgetToRender = avatarContent;
    } else {
      widgetToRender = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Outer Red Ring with spacing
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: alertRed, width: borderWidth),
            ),
            child: avatarContent,
          ),

          // Exclamation '!' Badge
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: EdgeInsets.all(radius > 25 ? 3.5 : 2.0),
              decoration: BoxDecoration(
                color: alertRed,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: radius > 25 ? 12 : 9,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: widgetToRender,
      );
    }

    return widgetToRender;
  }
}
