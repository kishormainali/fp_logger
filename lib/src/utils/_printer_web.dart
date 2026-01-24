import 'dart:js_interop';

import 'package:web/web.dart';

void outputLog(List<String> message) {
  for (final line in message) {
    console.log(line.toJS);
  }
}
