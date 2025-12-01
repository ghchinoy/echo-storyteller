import 'dart:typed_data';

class Chapter {
  String? title;
  Uint8List? image;
  final StringBuffer textBuffer = StringBuffer();
  
  String get text => textBuffer.toString();
}
