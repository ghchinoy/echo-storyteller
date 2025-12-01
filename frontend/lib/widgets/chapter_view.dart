import 'package:flutter/material.dart';
import '../models/chapter.dart';

class ChapterView extends StatelessWidget {
  final Chapter chapter;
  final Color textColor;
  final bool showImage;

  const ChapterView({
    super.key,
    required this.chapter,
    required this.textColor,
    required this.showImage,
  });

  void _showImageDialog(BuildContext context) {
    if (chapter.image == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              alignment: Alignment.center,
              children: [
                InteractiveViewer(
                  maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(chapter.image!),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleWidget = chapter.title != null
        ? Padding(
            padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
            child: Text(
              chapter.title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'Georgia',
                color: textColor,
              ),
            ),
          )
        : const SizedBox.shrink();

    final textWidget = SelectableText(
      chapter.text,
      style: TextStyle(
        fontSize: 18,
        height: 1.6,
        fontFamily: 'Georgia',
        color: textColor,
      ),
    );

    final imageWidget = showImage
        ? AnimatedSize(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutQuart,
            child: chapter.image == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: GestureDetector(
                      onTap: () => _showImageDialog(context),
                      child: Hero(
                        tag: chapter.hashCode,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            chapter.image!,
                            fit: BoxFit.cover,
                            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded) return child;
                              return AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(seconds: 1),
                                curve: Curves.easeOut,
                                child: child,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
          )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleWidget,
        if (showImage) imageWidget,
        textWidget,
        const Divider(height: 48, thickness: 0.5),
      ],
    );
  }
}
