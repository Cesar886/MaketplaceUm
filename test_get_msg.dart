import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  try {
    final query = <String, String>{};
    query['userId'] = 'u_prueba_gbl2';
    final url = Uri.parse('http://127.0.0.1:3000/api/chat/conversations/conv_1785081315742_f1da9a/messages').replace(queryParameters: query.isNotEmpty ? query : null);
    print('Fetching from: $url');
    final res = await http.get(url);
    print('Status: ${res.statusCode}');
    if (res.statusCode != 200) {
      print('Error: ${res.body}');
      return;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final msgs = data['messages'] as List<dynamic>;
    print('Messages count: ${msgs.length}');
  } catch (e) {
    print('Exception: $e');
  }
}
