import 'package:flutter/material.dart';

import '../domain/product_summary.dart';
import 'product_image.dart';

/// Полноэкранный просмотр фото с масштабированием и листанием.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({super.key, required this.summary, this.initialIndex = 0});

  final ProductSummary summary;
  final int initialIndex;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.summary.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${photos.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: ProductImage(fileName: photos[i].fileName, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
