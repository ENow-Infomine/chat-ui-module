import 'dart:js' as js;
import 'dart:async';
import 'xmpp_config.dart';

class XmppService {
  final Function(String from, String body, String type, String? timestampStr) onMessage;
  final Function() onConnected;

  // 1. Restore Presence Stream
  final StreamController<Map<String, String>> _presenceController = StreamController.broadcast();
  Stream<Map<String, String>> get presenceStream => _presenceController.stream;

  XmppService({required this.onMessage, required this.onConnected});

  void connect(String user, String pass) {
    String jid = "$user@${XmppConfig().domain}";
    
    // 2. Pass the presence callback to JS
    js.context.callMethod('connectXmpp', [
      XmppConfig().wsUrl, jid, pass,
      js.allowInterop(() => onConnected()),
      js.allowInterop((from, body, type, timestampStr) => onMessage(from, body, type, timestampStr)),
      js.allowInterop((String from, String status) {
        _presenceController.add({'from': from, 'status': status});
      })
    ]);
  }

  void joinRoom(String room, String user) {
    String roomJid = "$room@conference.${XmppConfig().domain}/$user";
    js.context.callMethod('joinXmppRoom', [roomJid]);
  }

  void sendMessage(String to, String text, {bool isGroup = true}) {
    String domain = XmppConfig().domain;
    String jid = isGroup ? "$to@conference.$domain" : "$to@$domain";
    String type = isGroup ? 'groupchat' : 'chat';
    js.context.callMethod('sendXmppMessage', [jid, text, type]);
  }
}
