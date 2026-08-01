import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  try {
    final res = await http.get(Uri.parse('http://127.0.0.1:3000/api/chat/conversations'));
    print(res.body);
  } catch (e) {
    print(e);
  }
}
