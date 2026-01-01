import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:js' as js; // Required for window.focus()
import 'xmpp_service.dart';
import 'backend_service.dart'; // Internal Service

class ChatOverlay extends StatefulWidget {
  final String currentUser;
  final String currentPass;
  final Widget child; // The Main App content

  const ChatOverlay({
    Key? key,
    required this.currentUser,
    required this.currentPass,
    required this.child,
  }) : super(key: key);

  @override
  _ChatOverlayState createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  // --- XMPP State ---
  late XmppService _xmpp;
  bool _isConnected = false;
  
  // --- UI Navigation State ---
  bool _isOpen = false;
  String? _activeChatId; // Null = Inbox, Value = Room/User ID
  bool _isGroupMode = true;

  // --- Data State (Fetched Internally) ---
  List<String> _myRooms = [];
  List<String> _myColleagues = [];
  bool _isLoadingInbox = true;

  // --- Chat Data ---
  final Map<String, List<String>> _history = {};
  final Map<String, Set<String>> _presenceMap = {}; // Tracks online users
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // 1. Request Notification Permissions
    if (html.Notification.permission != 'granted') {
      html.Notification.requestPermission();
    }

    // 2. Fetch Inbox Data from Backend
    _loadInbox();

    // 3. Initialize XMPP Service
    _xmpp = XmppService(
      onConnected: () {
        if (mounted) setState(() => _isConnected = true);
      },
      onMessage: (from, body, type) {
        // --- SENDER PARSING LOGIC ---
        String chatKey = from.split('@')[0]; // The ID (room or user)
        String sender;

        if (type == 'headline') {
           // System Alerts come from the Room Bare JID
           chatKey = from.split('@')[0]; 
           sender = "System";
        } 
        else if (type == 'groupchat') {
           // Room messages: room@conf/Nick
           chatKey = from.split('@')[0];
           sender = from.contains('/') ? from.split('/')[1] : "System";
        } 
        else {
           // DM: user@domain/Resource
           chatKey = from.split('@')[0];
           sender = chatKey; // In DM, sender is the user ID
        }

        // --- BACKGROUND NOTIFICATION ---
        if (html.document.visibilityState == 'hidden') {
           if (html.Notification.permission == 'granted') {
              var n = html.Notification("Msg from $sender", body: body);
              n.onClick.listen((e) { 
                // JS Focus Fix
                js.context.callMethod('focus'); 
                n.close();
                // Navigate to chat
                if (mounted) {
                  setState(() { _isOpen = true; _activeChatId = chatKey; });
                }
              });
           }
        }

        // --- UPDATE HISTORY ---
        if (mounted) {
          setState(() {
            if (!_history.containsKey(chatKey)) _history[chatKey] = [];
            _history[chatKey]!.add("$sender: $body");
          });
        }
      },
    );

    // 4. Presence Listener
    _xmpp.presenceStream.listen((event) {
      if (!mounted) return;
      String from = event['from']!; 
      String status = event['status']!; 
      
      setState(() {
        if (from.contains('/')) {
          // Group Presence (ticket_100@conf/Alice)
          String room = from.split('@')[0];
          String nick = from.split('/')[1];
          if (!_presenceMap.containsKey(room)) _presenceMap[room] = {};
          
          if (status == 'offline') _presenceMap[room]!.remove(nick);
          else _presenceMap[room]!.add(nick);
        } else {
          // Direct Presence (bob@domain)
          String user = from.split('@')[0];
          if (!_presenceMap.containsKey(user)) _presenceMap[user] = {};
          
          if (status == 'offline') _presenceMap[user]!.clear(); 
          else _presenceMap[user]!.add('online');
        }
      });
    });

    // 5. Connect
    _xmpp.connect(widget.currentUser, widget.currentPass);
  }

  // --- INTERNAL FETCHING ---
  void _loadInbox() async {
    setState(() => _isLoadingInbox = true);
    // Uses the internal BackendService moved to the module
    final data = await BackendService.getInbox(widget.currentUser);
    
    if (mounted) {
      setState(() {
        _myRooms = data['rooms']!;
        _myColleagues = data['colleagues']!;
        _isLoadingInbox = false;
      });
    }
  }

  void _send() {
    if (_ctrl.text.isEmpty || _activeChatId == null) return;
    String text = _ctrl.text;
    
    _xmpp.sendMessage(_activeChatId!, text, isGroup: _isGroupMode);
    
    setState(() {
      if (!_history.containsKey(_activeChatId!)) _history[_activeChatId!] = [];
      _history[_activeChatId!]!.add("Me: $text");
      _ctrl.clear();
    });
  }

  // --- WIDGETS ---

  Widget _buildHeader() {
    String title = _activeChatId!;
    String subtitle = "";
    Color statusColor = Colors.grey;

    if (_isGroupMode) {
      // Group Header Logic
      Set<String> participants = _presenceMap[_activeChatId] ?? {};
      int count = participants.length;
      if (count > 0) {
        subtitle = "${participants.take(3).join(', ')}";
        if (count > 3) subtitle += " +${count - 3}";
        statusColor = Colors.greenAccent;
      } else {
        subtitle = "Waiting for members...";
      }
    } else {
      // DM Header Logic
      bool isOnline = (_presenceMap[_activeChatId]?.isNotEmpty ?? false);
      subtitle = isOnline ? "Online" : "Offline";
      statusColor = isOnline ? Colors.greenAccent : Colors.grey;
    }

    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[800],
        // No rounded corners here, container below handles it
      ),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white), 
          onPressed: () => setState(() => _activeChatId = null)
        ),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(subtitle, style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        )
      ]),
    );
  }

  Widget _buildInbox() {
    if (_isLoadingInbox) return Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // Inbox Header with Refresh
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.blue[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Chats", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              InkWell(
                onTap: _loadInbox, 
                child: Icon(Icons.refresh, size: 20, color: Colors.blue[800])
              )
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (_myRooms.isEmpty && _myColleagues.isEmpty)
                Padding(padding: EdgeInsets.all(20), child: Text("No active chats found.")),

              if (_myRooms.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text("MY TICKETS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                ..._myRooms.map((r) => ListTile(
                  dense: true,
                  leading: Icon(Icons.confirmation_number, size: 20, color: Colors.blue),
                  title: Text(r),
                  onTap: () {
                     // Join room on tap
                     _xmpp.joinRoom(r, widget.currentUser);
                     setState(() { _history[r] = []; _activeChatId = r; _isGroupMode = true; });
                  },
                )),
              ],

              if (_myColleagues.isNotEmpty) ...[
                Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text("DIRECT MESSAGES", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                ..._myColleagues.map((u) => ListTile(
                  dense: true,
                  leading: Icon(Icons.person, size: 20, color: Colors.green),
                  title: Text(u),
                  // Presence Dot
                  trailing: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: (_presenceMap[u]?.isNotEmpty ?? false) ? Colors.green : Colors.grey[300],
                      shape: BoxShape.circle
                    ),
                  ),
                  onTap: () => setState(() {  _activeChatId = u; _isGroupMode = false; }),
                )),

              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: (_history[_activeChatId!] ?? []).length,
            itemBuilder: (ctx, i) {
              String msg = _history[_activeChatId!]![i];
              // Optional: You could parse "Sender: Body" here for better UI bubbles
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 4), 
                child: Text(msg)
              );
            },
          ),
        ),
        Divider(height: 1),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl, 
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    border: InputBorder.none
                  ),
                )
              ),
              IconButton(icon: Icon(Icons.send, color: Colors.blue), onPressed: _send)
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. The Main App (Background)
        widget.child,

        // 2. The Chat Window (Foreground)
        Positioned(
          bottom: 20, 
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_isOpen)
                Material(
                  elevation: 10, 
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  clipBehavior: Clip.antiAlias, // Clips the header cleanly
                  child: Container(
                    width: 320, 
                    height: 450,
                    child: _activeChatId == null ? _buildInbox() : _buildChat(),
                  ),
                ),
              SizedBox(height: 10),
              
              // Toggle Button
              FloatingActionButton(
                backgroundColor: Colors.blue[800],
                child: Icon(_isOpen ? Icons.close : Icons.chat),
                onPressed: () => setState(() => _isOpen = !_isOpen),
              )
            ],
          ),
        )
      ],
    );
  }
}
