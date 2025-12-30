import 'dart:convert';
import 'package:http/http.dart' as http;
import 'xmpp_config.dart'; // Import Config

class BackendService {
  // Use the dynamic URL from config
  static String get baseUrl => XmppConfig().restApiUrl;

  static Future<bool> registerUser(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users/register'),
        body: {'username': username, 'password': password},
      );
      return res.statusCode == 200;
    } catch (e) {
      print("Register Error: $e");
      return false;
    }
  }

  static Future<bool> createTicket(String ticketId, String creatorId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/tickets/create'),
        body: {'ticketId': ticketId, 'creator': creatorId},
      );
      return res.statusCode == 200;
    } catch (e) {
      print("Create Ticket Error: $e");
      return false;
    }
  }

  static Future<bool> assignTicket(String ticketId, String assigneeId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/tickets/assign'),
        body: {'ticketId': ticketId, 'assignee': assigneeId},
      );
      return res.statusCode == 200;
    } catch (e) {
      print("Assign Ticket Error: $e");
      return false;
    }
  }

  static Future<Map<String, List<String>>> getInbox(String userId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/chat/inbox?userId=$userId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {
          'rooms': List<String>.from(data['rooms'] ?? []),
          'colleagues': List<String>.from(data['colleagues'] ?? []),
        };
      }
    } catch (e) {
      print("Fetch Inbox Error: $e");
    }
    return {'rooms': [], 'colleagues': []};
  }
}
