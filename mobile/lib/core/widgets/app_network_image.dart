import 'package:flutter/material.dart';

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    super.key,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final Widget image = imageUrl.trim().isEmpty
        ? _fallback()
        : Image.network(
            imageUrl,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _fallback(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;

              return SizedBox(
                width: width,
                height: height,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
          );

    if (borderRadius == null) return image;

    return ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _fallback() {
    return SizedBox(
      width: width,
      height: height,
      child:
          placeholder ??
          const ColoredBox(
            color: Color(0xFFECEFF1),
            child: Center(
              child: Icon(Icons.person, size: 40, color: Color(0xFF607D8B)),
            ),
          ),
    );
  }
}
