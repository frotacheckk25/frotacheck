import 'dart:js_interop';

@JS('window.location.reload')
external void _reloadPage();

void reloadPage() => _reloadPage();
