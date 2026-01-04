import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:js' as js; 
import 'xmpp_service.dart';
import 'backend_service.dart'; 

class ChatOverlay extends StatefulWidget {
  final String currentUser;
  final String currentPass;
  final Widget child; 

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

  // --- Data State ---
  List<String> _myRooms = [];
  List<String> _myColleagues = [];
  bool _isLoadingInbox = true;
  int _unreadCount = 0;

  // --- Chat Data ---
  final Map<String, List<String>> _history = {};
  final Map<String, Set<String>> _presenceMap = {}; 
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    if (html.Notification.permission != 'granted') {
      html.Notification.requestPermission();
    }

    _loadInbox();

    _xmpp = XmppService(
      onConnected: () {
        if (mounted) setState(() => _isConnected = true);
      },
      onMessage: (from, body, type) {
        String chatKey = from.split('@')[0];
        String sender;

        if (type == 'headline') {
          if (body == 'REFRESH_INBOX') {
            _loadInbox(); 
            if (!_isOpen && mounted) setState(() => _unreadCount++);
          }
          return; 
        } 
        else if (type == 'groupchat') {
           chatKey = from.split('@')[0];
           sender = from.contains('/') ? from.split('/')[1] : "System";
        } 
        else {
           chatKey = from.split('@')[0];
           sender = chatKey; 
        }

        if (html.document.visibilityState == 'hidden') {
           if (html.Notification.permission == 'granted') {
              var n = html.Notification("Msg from $sender", body: body);
              n.onClick.listen((e) { 
                js.context.callMethod('focus'); 
                n.close();
                if (mounted) {
                  setState(() { _isOpen = true; _activeChatId = chatKey; });
                }
              });
           }
        }

        if (mounted) {
          setState(() {
            if (!_isOpen) _unreadCount++;            
            if (!_history.containsKey(chatKey)) _history[chatKey] = [];
            _history[chatKey]!.add("$sender: $body");
          });
        }
      },
    );

    _xmpp.presenceStream.listen((event) {
      if (!mounted) return;
      String from = event['from']!; 
      String status = event['status']!; 
      
      setState(() {
        if (from.contains('/')) {
          String room = from.split('@')[0];
          String nick = from.split('/')[1];
          if (!_presenceMap.containsKey(room)) _presenceMap[room] = {};
          
          if (status == 'offline') _presenceMap[room]!.remove(nick);
          else _presenceMap[room]!.add(nick);
        } else {
          String user = from.split('@')[0];
          if (!_presenceMap.containsKey(user)) _presenceMap[user] = {};
          
          if (status == 'offline') _presenceMap[user]!.clear(); 
          else _presenceMap[user]!.add('online');
        }
      });
    });

    _xmpp.connect(widget.currentUser, widget.currentPass);
  }

  Future<void> _loadInbox() async {
    setState(() => _isLoadingInbox = true);
    final data = await BackendService.getInbox(widget.currentUser);
    
    if (mounted) {
      setState(() {
        _myRooms = data['rooms']!;
        _myColleagues = data['colleagues']!;
        _isLoadingInbox = false;
      });
    }
  }

  void _toggleChat() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _unreadCount = 0; 
        _loadInbox();     
      }
    });
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

  Widget _buildInbox() {
    return Column(
      children: [
        // 1. Inbox Header (Updated: Close Button instead of Refresh)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.blue[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Chats", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[900])),
              
              // Minimized/Close Button
              IconButton(
                icon: Icon(Icons.close, size: 22, color: Colors.blue[800]),
                onPressed: _toggleChat, // Minimizes the window
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              )
            ],
          ),
        ),

        // 2. Inbox List
        Expanded(
          child: _isLoadingInbox 
            ? Center(child: CircularProgressIndicator())
            : RefreshIndicator( // Added Pull-to-Refresh since icon is gone
                onRefresh: _loadInbox,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (_myRooms.isEmpty && _myColleagues.isEmpty)
                      Padding(padding: EdgeInsets.all(20), child: Text("No active chats found.")),

                    if (_myRooms.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text("MY TICKETS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      ..._myRooms.map((r) => ListTile(
                        dense: true,
                        leading: Icon(Icons.confirmation_number, size: 20, color: Colors.blue),
                        title: Text(r),
                        onTap: () {
                           _xmpp.joinRoom(r, widget.currentUser);
                           setState(() { 
                             _history[r] = _history[r] ?? []; // Ensure history exists
                             _activeChatId = r; 
                             _isGroupMode = true; 
                           });
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
                        trailing: Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: (_presenceMap[u]?.isNotEmpty ?? false) ? Colors.green : Colors.grey[300],
                            shape: BoxShape.circle
                          ),
                        ),
                        onTap: () => setState(() {  
                          _history[u] = _history[u] ?? [];
                          _activeChatId = u; 
                          _isGroupMode = false; 
                        }),
                      )),
                    ],
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        // 1. Header (Includes Back & Close Buttons)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: Colors.blue[800], 
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => setState(() => _activeChatId = null),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeChatId ?? "Chat",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "Online", // You can wire up presence here later
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    )
                  ],
                ),
              ),
              // Close / Minimize Button
              IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: _toggleChat,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
            ],
          ),
        ),

        // 2. Message List
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: (_history[_activeChatId!] ?? []).length,
              itemBuilder: (ctx, i) {
                String msg = _history[_activeChatId!]![i];
                bool isMe = msg.startsWith("Me:");
                String displayMsg = msg.contains(":") ? msg.substring(msg.indexOf(":") + 1).trim() : msg;
                String senderName = msg.contains(":") ? msg.split(":")[0] : "Anon";

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[100] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: isMe ? Radius.circular(12) : Radius.circular(0),
                        bottomRight: isMe ? Radius.circular(0) : Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe) 
                          Text(
                            senderName, 
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600])
                          ),
                        Text(displayMsg, style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // 3. Input Area
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          padding: EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    isDense: true,
                    fillColor: Colors.grey[50],
                    filled: true,
                  ),
                ),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blue[800],
                radius: 18,
                child: IconButton(
                  icon: Icon(Icons.send, color: Colors.white, size: 16),
                  onPressed: _send,
                  padding: EdgeInsets.zero,
                ),
              )
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

        // 2. The Chat Window (Only visible if Open)
        if (_isOpen)
          Positioned(
            bottom: 20, 
            right: 20,
            child: Material(
              elevation: 10, 
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 320, 
                height: 450,
                child: _activeChatId == null ? _buildInbox() : _buildChat(),
              ),
            ),
          ),

        // 3. The Toggle Button (Only visible if CLOSED)
        // This if condition fixes your issue of the button showing over the chat
        if (!_isOpen)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.blue[800],
              onPressed: _toggleChat,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.chat),
                  
                  // Red Badge
                  if (_unreadCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            _unreadCount > 9 ? "9+" : "$_unreadCount",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),        
      ],
    );
  }
}